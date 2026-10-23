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
        "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
      ]
    )

    return
      candidates
      .map { NSString(string: $0).expandingTildeInPath }
      .first { isValidExecutable(at: URL(fileURLWithPath: $0)) }
      .map(URL.init(fileURLWithPath:))
  }

  public static func isValidExecutable(at url: URL) -> Bool {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
      && fileManager.isExecutableFile(atPath: url.path)
  }
}
