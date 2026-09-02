import Foundation

public enum QuotaWindowPeriod: Equatable, Sendable {
  case fiveHour
  case weekly
  case unknown
}

public struct QuotaWindow: Identifiable, Equatable, Sendable {
  public let id: String
  public let usedPercentage: Double
  public let resetDate: Date
  public let windowDurationMinutes: Int

  public init(
    id: String,
    usedPercentage: Double,
    resetDate: Date,
    windowDurationMinutes: Int
  ) {
    self.id = id
    self.usedPercentage = usedPercentage
    self.resetDate = resetDate
    self.windowDurationMinutes = windowDurationMinutes
  }

  public var remainingPercentage: Double {
    min(max(100 - usedPercentage, 0), 100)
  }

  public var period: QuotaWindowPeriod {
    switch windowDurationMinutes {
    case 300:
      .fiveHour
    case 10_080:
      .weekly
    default:
      .unknown
    }
  }
}

public struct QuotaDisplaySelection: Equatable, Sendable {
  public let window: QuotaWindow
  public let period: QuotaWindowPeriod

  public init(window: QuotaWindow) {
    self.window = window
    period = window.period
  }
}

public struct QuotaResetCredit: Equatable, Sendable {
  public let expirationDate: Date?

  public init(expirationDate: Date?) {
    self.expirationDate = expirationDate
  }
}

public struct QuotaResetCredits: Equatable, Sendable {
  public let availableCount: Int
  public let credits: [QuotaResetCredit]?

  public init(
    availableCount: Int,
    credits: [QuotaResetCredit]?
  ) {
    self.availableCount = max(availableCount, 0)
    self.credits = credits
  }

  public var displayCredits: [QuotaResetCredit] {
    let sortedCredits = (credits ?? []).sorted { left, right in
      switch (left.expirationDate, right.expirationDate) {
      case (.some(let leftDate), .some(let rightDate)):
        leftDate < rightDate
      case (.some, .none):
        true
      case (.none, .some):
        false
      case (.none, .none):
        false
      }
    }
    return Array(sortedCredits.prefix(availableCount))
  }

  public var unavailableDetailCount: Int {
    max(availableCount - displayCredits.count, 0)
  }
}

public struct QuotaSnapshot: Equatable, Sendable {
  public let windows: [QuotaWindow]
  public let resetCredits: QuotaResetCredits?
  public let lastUpdated: Date

  public init(
    windows: [QuotaWindow],
    resetCredits: QuotaResetCredits?,
    lastUpdated: Date
  ) {
    self.windows = windows
    self.resetCredits = resetCredits
    self.lastUpdated = lastUpdated
  }

  public var fiveHourWindow: QuotaWindow? {
    preferredWindow(in: windows.filter { $0.period == .fiveHour })
  }

  public var weeklyWindow: QuotaWindow? {
    preferredWindow(in: windows.filter { $0.period == .weekly })
  }

  public var displaySelection: QuotaDisplaySelection? {
    if let fiveHourWindow {
      return QuotaDisplaySelection(window: fiveHourWindow)
    }
    if let weeklyWindow {
      return QuotaDisplaySelection(window: weeklyWindow)
    }
    guard let fallback = preferredWindow(in: windows) else { return nil }
    return QuotaDisplaySelection(window: fallback)
  }

  public var displayWindow: QuotaWindow? {
    displaySelection?.window
  }

  private func preferredWindow(in candidates: [QuotaWindow]) -> QuotaWindow? {
    candidates.min { left, right in
      if left.remainingPercentage == right.remainingPercentage {
        return left.resetDate < right.resetDate
      }
      return left.remainingPercentage < right.remainingPercentage
    }
  }
}

public enum QuotaProviderIssue: Equatable, Sendable {
  case executableNotFound
  case methodUnavailable
  case quotaUnavailable
  case timeout
  case launchFailed
  case connectionInterrupted
  case incompatibleResponse
  case remoteFailure
  case unknown
}

public enum QuotaProviderState: Equatable, Sendable {
  case idle
  case loading(previous: QuotaSnapshot?)
  case available(QuotaSnapshot)
  case signedOut(previous: QuotaSnapshot?)
  case unsupported(issue: QuotaProviderIssue, previous: QuotaSnapshot?)
  case unavailable(issue: QuotaProviderIssue, previous: QuotaSnapshot?)
  case failed(issue: QuotaProviderIssue, previous: QuotaSnapshot?)

  public var snapshot: QuotaSnapshot? {
    switch self {
    case .idle:
      nil
    case .loading(let previous),
      .signedOut(let previous),
      .unsupported(_, let previous),
      .unavailable(_, let previous),
      .failed(_, let previous):
      previous
    case .available(let snapshot):
      snapshot
    }
  }

  public var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }
}
