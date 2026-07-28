import AppKit
import CodexGaugeCore
import Foundation

@MainActor
final class GaugeViewModel: ObservableObject {
  @Published private(set) var state: QuotaProviderState
  @Published private(set) var actionMessage: String?

  private let provider: any QuotaProvider
  private var hasStarted = false

  init(provider: any QuotaProvider) {
    self.provider = provider
    state = provider.currentState

    provider.observeState { [weak self] state in
      self?.state = state
    }
  }

  var snapshot: QuotaSnapshot? {
    state.snapshot
  }

  var displayWindow: QuotaWindow? {
    snapshot?.displayWindow
  }

  var canSelectCodexExecutable: Bool {
    guard case .unsupported(let issue, _) = state else { return false }
    return issue == .executableNotFound
  }

  var menuBarAccessibilityLabel: String {
    guard let remaining = displayWindow?.remainingPercentage else {
      return L10n.text("accessibility.menuBarUnavailable")
    }
    return L10n.menuBarRemaining(Int(remaining.rounded()))
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    refresh()
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

  func openCodex() {
    let bundleIdentifiers = [
      "com.openai.codex"
    ]

    let applicationURL =
      bundleIdentifiers
      .lazy
      .compactMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
      .first
      ?? existingApplicationURL()

    guard let applicationURL else {
      actionMessage = L10n.text("error.codexAppNotFound")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    ) { [weak self] _, error in
      Task { @MainActor in
        self?.actionMessage =
          error == nil ? nil : L10n.text("error.codexAppOpenFailed")
      }
    }
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
