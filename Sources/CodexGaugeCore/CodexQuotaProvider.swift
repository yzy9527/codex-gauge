import Foundation

public enum CodexExecutableResolver {
  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    defaults: UserDefaults = .standard
  ) -> URL? {
    var candidates: [String] = []

    if let selectedPath = defaults.string(forKey: "CodexGauge.codexExecutablePath") {
      candidates.append(selectedPath)
    }

    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map { directory in
          URL(fileURLWithPath: String(directory))
            .appendingPathComponent("codex")
            .path
        }
      )
    }

    candidates.append(
      contentsOf: [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
      ]
    )

    return
      candidates
      .map { NSString(string: $0).expandingTildeInPath }
      .first { FileManager.default.isExecutableFile(atPath: $0) }
      .map(URL.init(fileURLWithPath:))
  }
}

enum CodexQuotaMappingError: Error {
  case invalidResponse
  case missingQuotaWindow
}

enum CodexQuotaMapper {
  static func snapshot(from data: Data, now: Date = Date()) throws -> QuotaSnapshot {
    let response: RateLimitsResponse
    do {
      response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
    } catch {
      throw CodexQuotaMappingError.invalidResponse
    }

    let selectedLimits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
    guard let selectedLimits else {
      throw CodexQuotaMappingError.missingQuotaWindow
    }

    let windows = [
      makeWindow(id: "primary", from: selectedLimits.primary),
      makeWindow(id: "secondary", from: selectedLimits.secondary),
    ].compactMap { $0 }

    guard !windows.isEmpty else {
      throw CodexQuotaMappingError.missingQuotaWindow
    }

    let resetCredits = response.rateLimitResetCredits.map { summary in
      QuotaResetCredits(
        availableCount: summary.availableCount,
        credits: summary.credits?.map { credit in
          QuotaResetCredit(
            expirationDate: credit.expiresAt.map {
              Date(timeIntervalSince1970: TimeInterval($0))
            }
          )
        }
      )
    }

    return QuotaSnapshot(
      windows: windows,
      resetCredits: resetCredits,
      lastUpdated: now
    )
  }

  private static func makeWindow(
    id: String,
    from value: RateLimitWindow?
  ) -> QuotaWindow? {
    guard let value, let resetsAt = value.resetsAt else {
      return nil
    }
    return QuotaWindow(
      id: id,
      usedPercentage: value.usedPercent,
      resetDate: Date(timeIntervalSince1970: TimeInterval(resetsAt)),
      windowDurationMinutes: value.windowDurationMins ?? 0
    )
  }
}

private struct RateLimitsResponse: Decodable {
  let rateLimits: RateLimitSnapshot?
  let rateLimitsByLimitId: [String: RateLimitSnapshot]?
  let rateLimitResetCredits: ResetCreditsSummary?
}

private struct RateLimitSnapshot: Decodable {
  let primary: RateLimitWindow?
  let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
  let usedPercent: Double
  let windowDurationMins: Int?
  let resetsAt: Int64?
}

private struct ResetCreditsSummary: Decodable {
  let availableCount: Int
  let credits: [ResetCredit]?
}

private struct ResetCredit: Decodable {
  let expiresAt: Int64?
}

private enum CodexAppServerError: Error {
  case executableNotFound
  case launchFailed
  case timeout
  case processExited
  case invalidMessage
  case methodUnavailable
  case signedOut
  case remoteFailure
}

private actor CodexAppServerClient {
  typealias UpdateHandler = @Sendable () async -> Void

  private struct PendingRequest {
    let continuation: CheckedContinuation<Data, Error>
    let timeoutTask: Task<Void, Never>
  }

  private let initializationTimeout: Duration
  private let rateLimitsTimeout: Duration
  private var process: Process?
  private var inputPipe: Pipe?
  private var outputPipe: Pipe?
  private var errorPipe: Pipe?
  private var outputReadTask: Task<Void, Never>?
  private var errorReadTask: Task<Void, Never>?
  private var receiveBuffer = Data()
  private var nextRequestID = 1
  private var pendingRequests: [Int: PendingRequest] = [:]
  private var isInitialized = false
  private var updateHandler: UpdateHandler?

  init(
    initializationTimeout: Duration = .seconds(5),
    rateLimitsTimeout: Duration = .seconds(15)
  ) {
    self.initializationTimeout = initializationTimeout
    self.rateLimitsTimeout = rateLimitsTimeout
  }

  func setUpdateHandler(_ handler: UpdateHandler?) {
    updateHandler = handler
  }

  func readRateLimits() async throws -> Data {
    try await ensureInitialized()
    return try await request(
      method: "account/rateLimits/read",
      params: nil,
      timeout: rateLimitsTimeout
    )
  }

  private func ensureInitialized() async throws {
    if isInitialized, process?.isRunning == true {
      return
    }

    stopProcess()
    try startProcess()

    let params: [String: Any] = [
      "clientInfo": [
        "name": "codex-gauge",
        "version": "0.1.0",
      ],
      "capabilities": [
        "experimentalApi": true
      ],
    ]
    _ = try await request(
      method: "initialize",
      params: params,
      timeout: initializationTimeout
    )
    try sendNotification(method: "initialized", params: nil)
    isInitialized = true
  }

  private func startProcess() throws {
    guard let executableURL = CodexExecutableResolver.resolve() else {
      throw CodexAppServerError.executableNotFound
    }

    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = executableURL
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    process.environment = Self.minimumEnvironment()

    let processIdentifier = ObjectIdentifier(process)
    process.terminationHandler = { [weak self] _ in
      Task {
        await self?.processDidExit(processIdentifier)
      }
    }

    do {
      try process.run()
    } catch {
      throw CodexAppServerError.launchFailed
    }

    self.process = process
    self.inputPipe = inputPipe
    self.outputPipe = outputPipe
    self.errorPipe = errorPipe
    outputReadTask = Task.detached { [weak self, outputPipe] in
      let handle = outputPipe.fileHandleForReading
      while !Task.isCancelled {
        let data = handle.availableData
        guard !data.isEmpty else { return }
        await self?.receive(data)
      }
    }
    errorReadTask = Task.detached { [errorPipe] in
      let handle = errorPipe.fileHandleForReading
      while !Task.isCancelled {
        guard !handle.availableData.isEmpty else { return }
      }
    }
  }

  private func request(
    method: String,
    params: Any?,
    timeout: Duration
  ) async throws -> Data {
    let requestID = nextRequestID
    nextRequestID += 1

    var message: [String: Any] = [
      "id": requestID,
      "method": method,
    ]
    message["params"] = params ?? NSNull()
    let messageData = try encodedLine(message)

    return try await withCheckedThrowingContinuation { continuation in
      let timeoutTask = Task { [weak self, timeout] in
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        await self?.requestDidTimeout(requestID)
      }
      pendingRequests[requestID] = PendingRequest(
        continuation: continuation,
        timeoutTask: timeoutTask
      )

      do {
        guard let inputPipe else {
          finishRequest(requestID, with: .failure(CodexAppServerError.processExited))
          return
        }
        try inputPipe.fileHandleForWriting.write(contentsOf: messageData)
      } catch {
        finishRequest(requestID, with: .failure(CodexAppServerError.processExited))
      }
    }
  }

  private func sendNotification(method: String, params: Any?) throws {
    var message: [String: Any] = ["method": method]
    if let params {
      message["params"] = params
    }
    guard let inputPipe else {
      throw CodexAppServerError.processExited
    }
    try inputPipe.fileHandleForWriting.write(contentsOf: encodedLine(message))
  }

  private func encodedLine(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw CodexAppServerError.invalidMessage
    }
    var data = try JSONSerialization.data(withJSONObject: object)
    data.append(0x0A)
    return data
  }

  private func receive(_ data: Data) {
    receiveBuffer.append(data)

    while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
      let line = receiveBuffer[..<newlineIndex]
      receiveBuffer.removeSubrange(...newlineIndex)
      guard !line.isEmpty else { continue }
      handleMessage(Data(line))
    }
  }

  private func handleMessage(_ data: Data) {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let message = object as? [String: Any]
    else {
      return
    }

    if let requestID = (message["id"] as? NSNumber)?.intValue {
      if let result = message["result"] {
        guard JSONSerialization.isValidJSONObject(result),
          let resultData = try? JSONSerialization.data(withJSONObject: result)
        else {
          finishRequest(requestID, with: .failure(CodexAppServerError.invalidMessage))
          return
        }
        finishRequest(requestID, with: .success(resultData))
        return
      }

      if let error = message["error"] as? [String: Any] {
        finishRequest(requestID, with: .failure(classifyRemoteError(error)))
      }
      return
    }

    guard message["method"] as? String == "account/rateLimits/updated" else {
      return
    }
    let handler = updateHandler
    Task {
      await handler?()
    }
  }

  private func classifyRemoteError(_ value: [String: Any]) -> CodexAppServerError {
    let code = (value["code"] as? NSNumber)?.intValue
    let message = (value["message"] as? String)?.lowercased() ?? ""
    if code == -32601 || message.contains("method not found") {
      return .methodUnavailable
    }
    if message.contains("login") || message.contains("auth") || message.contains("unauthorized") {
      return .signedOut
    }
    return .remoteFailure
  }

  private func requestDidTimeout(_ requestID: Int) {
    finishRequest(requestID, with: .failure(CodexAppServerError.timeout))
    stopProcess()
  }

  private func finishRequest(_ requestID: Int, with result: Result<Data, Error>) {
    guard let pendingRequest = pendingRequests.removeValue(forKey: requestID) else {
      return
    }
    pendingRequest.timeoutTask.cancel()
    pendingRequest.continuation.resume(with: result)
  }

  private func processDidExit(_ identifier: ObjectIdentifier) {
    guard let process, ObjectIdentifier(process) == identifier else {
      return
    }
    let requestIDs = Array(pendingRequests.keys)
    for requestID in requestIDs {
      finishRequest(requestID, with: .failure(CodexAppServerError.processExited))
    }
    clearProcessReferences()
  }

  private func stopProcess() {
    if process?.isRunning == true {
      process?.terminate()
    }
    clearProcessReferences()
  }

  private func clearProcessReferences() {
    inputPipe?.fileHandleForWriting.closeFile()
    outputPipe?.fileHandleForReading.closeFile()
    errorPipe?.fileHandleForReading.closeFile()
    outputReadTask?.cancel()
    errorReadTask?.cancel()
    process = nil
    inputPipe = nil
    outputPipe = nil
    errorPipe = nil
    outputReadTask = nil
    errorReadTask = nil
    receiveBuffer.removeAll(keepingCapacity: true)
    isInitialized = false
  }

  private static func minimumEnvironment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    let allowedKeys = [
      "HOME",
      "PATH",
      "CODEX_HOME",
      "TMPDIR",
      "LANG",
      "LC_ALL",
      "USER",
      "LOGNAME",
      "SHELL",
      "__CF_USER_TEXT_ENCODING",
    ]
    return allowedKeys.reduce(into: [:]) { result, key in
      if let value = source[key] {
        result[key] = value
      }
    }
  }
}

@MainActor
public final class CodexQuotaProvider: QuotaProvider {
  public private(set) var currentState: QuotaProviderState = .idle

  private let client: CodexAppServerClient
  private var observer: (@MainActor (QuotaProviderState) -> Void)?
  private var isRefreshing = false
  private var didConfigureUpdates = false
  private var notificationRefreshTask: Task<Void, Never>?
  private var periodicRefreshTask: Task<Void, Never>?
  private var consecutiveFailureCount = 0

  public init() {
    client = CodexAppServerClient()
  }

  public func observeState(
    _ observer: @escaping @MainActor (QuotaProviderState) -> Void
  ) {
    self.observer = observer
    observer(currentState)
  }

  public func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer {
      isRefreshing = false
      startPeriodicRefreshIfNeeded()
    }

    await configureUpdatesIfNeeded()
    let previous = currentState.snapshot
    publish(.loading(previous: previous))

    do {
      let data = try await client.readRateLimits()
      let snapshot = try CodexQuotaMapper.snapshot(from: data)
      consecutiveFailureCount = 0
      publish(.available(snapshot))
    } catch CodexAppServerError.executableNotFound {
      consecutiveFailureCount += 1
      publish(.unsupported(message: "未找到 Codex CLI，请先安装 Codex。", previous: previous))
    } catch CodexAppServerError.methodUnavailable {
      consecutiveFailureCount += 1
      publish(.unsupported(message: "当前 Codex 版本不支持额度读取。", previous: previous))
    } catch CodexAppServerError.signedOut {
      consecutiveFailureCount += 1
      publish(.signedOut(previous: previous))
    } catch CodexQuotaMappingError.missingQuotaWindow {
      consecutiveFailureCount += 1
      publish(.unavailable(message: "当前账号暂时没有可用的额度数据。", previous: previous))
    } catch CodexAppServerError.timeout {
      consecutiveFailureCount += 1
      publish(.failed(message: "读取额度超时，请重试。", previous: previous))
    } catch CodexAppServerError.launchFailed {
      consecutiveFailureCount += 1
      publish(.unsupported(message: "无法启动本机 Codex CLI。", previous: previous))
    } catch CodexAppServerError.processExited {
      consecutiveFailureCount += 1
      publish(.failed(message: "Codex 连接已中断，请重试。", previous: previous))
    } catch CodexAppServerError.invalidMessage,
      CodexQuotaMappingError.invalidResponse
    {
      consecutiveFailureCount += 1
      publish(.failed(message: "Codex 返回了不兼容的数据。", previous: previous))
    } catch CodexAppServerError.remoteFailure {
      consecutiveFailureCount += 1
      publish(.failed(message: "Codex 暂时无法读取额度。", previous: previous))
    } catch {
      consecutiveFailureCount += 1
      publish(.failed(message: "无法从本机 Codex 读取额度。", previous: previous))
    }
  }

  private func configureUpdatesIfNeeded() async {
    guard !didConfigureUpdates else { return }
    didConfigureUpdates = true
    await client.setUpdateHandler { [weak self] in
      await MainActor.run {
        self?.scheduleNotificationRefresh()
      }
    }
  }

  private func scheduleNotificationRefresh() {
    notificationRefreshTask?.cancel()
    notificationRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }

  private func startPeriodicRefreshIfNeeded() {
    guard periodicRefreshTask == nil else { return }
    periodicRefreshTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let delay = refreshDelay
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        await refresh()
      }
    }
  }

  private var refreshDelay: Duration {
    switch consecutiveFailureCount {
    case 0:
      .seconds(300)
    case 1:
      .seconds(60)
    case 2:
      .seconds(120)
    case 3:
      .seconds(300)
    default:
      .seconds(600)
    }
  }

  private func publish(_ state: QuotaProviderState) {
    currentState = state
    observer?(state)
  }
}
