import AppKit

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
