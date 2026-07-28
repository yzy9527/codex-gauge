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

  var menuBarAccessibilityLabel: String {
    guard let remaining = displayWindow?.remainingPercentage else {
      return "Codex Gauge，额度不可用"
    }
    return "Codex Gauge，剩余 \(Int(remaining.rounded()))%"
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
      actionMessage = "未找到 Codex 应用"
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: configuration
    ) { [weak self] _, error in
      Task { @MainActor in
        self?.actionMessage = error == nil ? nil : "无法打开 Codex"
      }
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
