import Foundation

@MainActor
public protocol QuotaProvider: AnyObject {
  var currentState: QuotaProviderState { get }

  func observeState(
    _ observer: @escaping @MainActor (QuotaProviderState) -> Void
  )
  func refresh() async
  func selectCodexExecutable(at url: URL) async throws
  func shutdown() async
}

public enum QuotaProviderConfigurationError: Error, Equatable {
  case invalidExecutable
}

@MainActor
public final class MockQuotaProvider: QuotaProvider {
  public private(set) var currentState: QuotaProviderState

  private var observer: (@MainActor (QuotaProviderState) -> Void)?
  private var refreshCount = 0

  public init(initialState: QuotaProviderState = .available(.preview)) {
    currentState = initialState
  }

  public func observeState(
    _ observer: @escaping @MainActor (QuotaProviderState) -> Void
  ) {
    self.observer = observer
    observer(currentState)
  }

  public func refresh() async {
    let previous = currentState.snapshot
    publish(.loading(previous: previous))

    try? await Task.sleep(for: .milliseconds(650))

    refreshCount += 1
    let usedDelta = Double(refreshCount % 4)
    publish(.available(.preview(usedDelta: usedDelta)))
  }

  public func selectCodexExecutable(at url: URL) async throws {
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw QuotaProviderConfigurationError.invalidExecutable
    }
    await refresh()
  }

  public func shutdown() async {}

  private func publish(_ state: QuotaProviderState) {
    currentState = state
    observer?(state)
  }
}

extension QuotaSnapshot {
  public static var preview: QuotaSnapshot {
    preview()
  }

  public static func preview(
    now: Date = Date(),
    usedDelta: Double = 0
  ) -> QuotaSnapshot {
    QuotaSnapshot(
      windows: [
        QuotaWindow(
          id: "weekly",
          usedPercentage: 38 + usedDelta,
          resetDate: now.addingTimeInterval(5 * 24 * 60 * 60 + 3 * 60 * 60),
          windowDurationMinutes: 10_080
        )
      ],
      resetCredits: QuotaResetCredits(
        availableCount: 2,
        credits: [
          QuotaResetCredit(
            expirationDate: now.addingTimeInterval(4 * 24 * 60 * 60 + 8 * 60 * 60)
          ),
          QuotaResetCredit(
            expirationDate: now.addingTimeInterval(16 * 24 * 60 * 60 + 8 * 60 * 60)
          ),
        ]
      ),
      lastUpdated: now
    )
  }
}
