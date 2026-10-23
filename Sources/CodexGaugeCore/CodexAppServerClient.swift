import Foundation

enum CodexAppServerError: Error {
  case executableNotFound
  case launchFailed
  case timeout
  case processExited
  case invalidMessage
  case methodUnavailable
  case signedOut
  case remoteFailure
}

actor CodexAppServerClient {
  typealias UpdateHandler = @Sendable () async -> Void

  private struct PendingRequest {
    let continuation: CheckedContinuation<Data, Error>
    let timeoutTask: Task<Void, Never>
  }

  private let initializationTimeout: Duration
  private let rateLimitsTimeout: Duration
  private let executableURL: URL?
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
  private var exitHandler: UpdateHandler?

  init(
    initializationTimeout: Duration = .seconds(5),
    rateLimitsTimeout: Duration = .seconds(15),
    executableURL: URL? = nil
  ) {
    self.initializationTimeout = initializationTimeout
    self.rateLimitsTimeout = rateLimitsTimeout
    self.executableURL = executableURL
  }

  func setUpdateHandler(_ handler: UpdateHandler?) {
    updateHandler = handler
  }

  func setExitHandler(_ handler: UpdateHandler?) {
    exitHandler = handler
  }

  func readRateLimits() async throws -> Data {
    try await ensureInitialized()
    return try await request(
      method: "account/rateLimits/read",
      params: nil,
      timeout: rateLimitsTimeout
    )
  }

  func shutdown() {
    updateHandler = nil
    exitHandler = nil
    let requestIDs = Array(pendingRequests.keys)
    for requestID in requestIDs {
      finishRequest(requestID, with: .failure(CodexAppServerError.processExited))
    }
    stopProcess()
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
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
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
    guard let executableURL = executableURL ?? CodexExecutableResolver.resolve() else {
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
        await self?.receive(data, from: processIdentifier)
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

  private func receive(_ data: Data, from identifier: ObjectIdentifier) {
    guard let process, ObjectIdentifier(process) == identifier else { return }
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
    // In-flight reads report their own failure; idle exits need a separate event.
    if requestIDs.isEmpty {
      let handler = exitHandler
      Task { await handler?() }
    }
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
