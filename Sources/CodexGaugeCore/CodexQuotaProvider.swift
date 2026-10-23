import Foundation

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
  private var recentExits: [ContinuousClock.Instant] = []
  private var automaticRefreshPaused = false
  private var isShutdown = false
  private let automaticRefreshInterval: Duration?

  public init() {
    client = CodexAppServerClient()
    automaticRefreshInterval = nil
  }

  init(client: CodexAppServerClient, automaticRefreshInterval: Duration? = nil) {
    self.client = client
    self.automaticRefreshInterval = automaticRefreshInterval
  }

  public func observeState(
    _ observer: @escaping @MainActor (QuotaProviderState) -> Void
  ) {
    self.observer = observer
    observer(currentState)
  }

  public func refresh() async {
    guard !isRefreshing, !isShutdown else { return }
    // An explicit retry starts a new recovery attempt after the circuit opens.
    if automaticRefreshPaused {
      automaticRefreshPaused = false
      recentExits.removeAll()
      consecutiveFailureCount = 0
    }
    await performRefresh()
  }

  private func refreshAutomatically() async {
    guard !automaticRefreshPaused, !isShutdown else { return }
    await performRefresh()
  }

  private func performRefresh() async {
    guard !isRefreshing, !isShutdown else { return }
    isRefreshing = true
    defer {
      isRefreshing = false
      scheduleNextRefresh()
    }

    await configureUpdatesIfNeeded()
    let previous = currentState.snapshot
    publish(.loading(previous: previous))

    do {
      let data = try await client.readRateLimits()
      guard !isShutdown else { return }
      let snapshot = try CodexQuotaMapper.snapshot(from: data)
      consecutiveFailureCount = 0
      publish(.available(snapshot))
    } catch CodexAppServerError.executableNotFound {
      consecutiveFailureCount += 1
      publish(.unsupported(issue: .executableNotFound, previous: previous))
    } catch CodexAppServerError.methodUnavailable {
      consecutiveFailureCount += 1
      publish(.unsupported(issue: .methodUnavailable, previous: previous))
    } catch CodexAppServerError.signedOut {
      consecutiveFailureCount += 1
      publish(.signedOut(previous: previous))
    } catch CodexQuotaMappingError.missingQuotaWindow {
      consecutiveFailureCount += 1
      publish(.unavailable(issue: .quotaUnavailable, previous: previous))
    } catch CodexAppServerError.timeout {
      consecutiveFailureCount += 1
      publish(.failed(issue: .timeout, previous: previous))
    } catch CodexAppServerError.launchFailed {
      consecutiveFailureCount += 1
      publish(.unsupported(issue: .launchFailed, previous: previous))
    } catch CodexAppServerError.processExited {
      recordProcessExit()
    } catch CodexAppServerError.invalidMessage,
      CodexQuotaMappingError.invalidResponse
    {
      consecutiveFailureCount += 1
      publish(.failed(issue: .incompatibleResponse, previous: previous))
    } catch CodexAppServerError.remoteFailure {
      consecutiveFailureCount += 1
      publish(.failed(issue: .remoteFailure, previous: previous))
    } catch {
      consecutiveFailureCount += 1
      publish(.failed(issue: .unknown, previous: previous))
    }
  }

  public func selectCodexExecutable(at url: URL) async throws {
    guard CodexExecutableResolver.isValidExecutable(at: url) else {
      throw QuotaProviderConfigurationError.invalidExecutable
    }

    UserDefaults.standard.set(
      url.path,
      forKey: "CodexGauge.codexExecutablePath"
    )
    await client.shutdown()
    didConfigureUpdates = false
    await refresh()
  }

  public func shutdown() async {
    isShutdown = true
    notificationRefreshTask?.cancel()
    periodicRefreshTask?.cancel()
    notificationRefreshTask = nil
    periodicRefreshTask = nil
    didConfigureUpdates = false
    await client.shutdown()
  }

  private func configureUpdatesIfNeeded() async {
    guard !didConfigureUpdates else { return }
    didConfigureUpdates = true
    await client.setUpdateHandler { [weak self] in
      await self?.scheduleNotificationRefresh()
    }
    await client.setExitHandler { [weak self] in
      await self?.recordProcessExit()
    }
  }

  private func recordProcessExit() {
    guard !isShutdown else { return }
    let now = ContinuousClock.now
    recentExits.removeAll { $0.duration(to: now) > .seconds(600) }
    recentExits.append(now)
    consecutiveFailureCount += 1
    if recentExits.count >= 3 {
      automaticRefreshPaused = true
      periodicRefreshTask?.cancel()
      periodicRefreshTask = nil
      notificationRefreshTask?.cancel()
      notificationRefreshTask = nil
    }
    publish(.failed(
      issue: automaticRefreshPaused ? .automaticRefreshPaused : .connectionInterrupted,
      previous: currentState.snapshot
    ))
    if !isRefreshing { scheduleNextRefresh() }
  }

  private func scheduleNotificationRefresh() {
    guard !automaticRefreshPaused, !isShutdown else { return }
    notificationRefreshTask?.cancel()
    notificationRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await self?.refreshAutomatically()
    }
  }

  private func scheduleNextRefresh() {
    periodicRefreshTask?.cancel()
    periodicRefreshTask = nil
    guard !automaticRefreshPaused, !isShutdown else { return }
    let delay = refreshDelay
    periodicRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      periodicRefreshTask = nil
      await refreshAutomatically()
    }
  }

  private var refreshDelay: Duration {
    if let automaticRefreshInterval { return automaticRefreshInterval }
    return switch consecutiveFailureCount {
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
