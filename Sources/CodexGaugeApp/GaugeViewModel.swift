import AppKit
import CodexGaugeCore
import Foundation

@MainActor
protocol CodexApplicationOpening: AnyObject {
  func installedApplicationURL() -> URL?
  func openApplication(at url: URL) async -> Bool
}

@MainActor
final class WorkspaceCodexApplicationOpener: CodexApplicationOpening {
  func installedApplicationURL() -> URL? {
    let bundleIdentifiers = [
      "com.openai.codex"
    ]

    return
      bundleIdentifiers
      .lazy
      .compactMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
      .first
      ?? existingApplicationURL()
  }

  func openApplication(at url: URL) async -> Bool {
    await WorkspaceApplicationLaunchRequest.openApplication(at: url)
  }

  private func existingApplicationURL() -> URL? {
    let candidates = [
      "/Applications/Codex.app",
      NSString(string: "~/Applications/Codex.app").expandingTildeInPath,
    ]
    return
      candidates
      .map(URL.init(fileURLWithPath:))
      .first { FileManager.default.fileExists(atPath: $0.path) }
  }
}

private enum WorkspaceApplicationLaunchRequest {
  static func openApplication(at url: URL) async -> Bool {
    await withCheckedContinuation { continuation in
      let configuration = NSWorkspace.OpenConfiguration()
      NSWorkspace.shared.openApplication(
        at: url,
        configuration: configuration
      ) { _, error in
        continuation.resume(returning: error == nil)
      }
    }
  }
}

@MainActor
final class GaugeViewModel: ObservableObject {
  @Published private(set) var state: QuotaProviderState
  @Published private(set) var actionMessage: String?

  private let provider: any QuotaProvider
  private let applicationOpener: any CodexApplicationOpening
  private var hasStarted = false
  private var launchObserver: NSObjectProtocol?

  init(
    provider: any QuotaProvider,
    applicationOpener: any CodexApplicationOpening = WorkspaceCodexApplicationOpener()
  ) {
    self.provider = provider
    self.applicationOpener = applicationOpener
    state = provider.currentState

    provider.observeState { [weak self] state in
      self?.state = state
    }
  }

  var snapshot: QuotaSnapshot? {
    state.snapshot
  }

  var displaySelection: QuotaDisplaySelection? {
    snapshot?.displaySelection
  }

  var canSelectCodexExecutable: Bool {
    guard case .unsupported(let issue, _) = state else { return false }
    return issue == .executableNotFound
  }

  var menuBarAccessibilityLabel: String {
    guard let displaySelection else {
      return L10n.text("accessibility.menuBarUnavailable")
    }
    return L10n.menuBarRemaining(
      Int(displaySelection.window.remainingPercentage.rounded()),
      period: displaySelection.period
    )
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    refresh()
  }

  func startWhenApplicationFinishesLaunching() {
    guard launchObserver == nil else { return }
    if NSApplication.shared.isRunning {
      startIfNeeded()
      return
    }

    launchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: NSApplication.shared,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.removeLaunchObserver()
        self?.startIfNeeded()
      }
    }
  }

  func refresh() {
    Task {
      await provider.refresh()
    }
  }

  func selectCodexExecutable() {
    let panel = NSOpenPanel()
    panel.title = L10n.text("action.selectCodexCLI")
    panel.message = L10n.text("cliPicker.message")
    panel.prompt = L10n.text("action.choose")
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let executableURL = panel.url else { return }
    Task {
      do {
        try await provider.selectCodexExecutable(at: executableURL)
        actionMessage = nil
      } catch {
        actionMessage = L10n.text("error.invalidExecutable")
      }
    }
  }

  func openCodex() async {
    guard let applicationURL = applicationOpener.installedApplicationURL() else {
      actionMessage = L10n.text("error.codexAppNotFound")
      return
    }

    let didOpen = await applicationOpener.openApplication(at: applicationURL)
    actionMessage = didOpen ? nil : L10n.text("error.codexAppOpenFailed")
  }

  func quit() {
    Task {
      await provider.shutdown()
      NSApplication.shared.terminate(nil)
    }
  }

  func dismissActionMessage() {
    actionMessage = nil
  }

  private func removeLaunchObserver() {
    guard let launchObserver else { return }
    NotificationCenter.default.removeObserver(launchObserver)
    self.launchObserver = nil
  }
}
