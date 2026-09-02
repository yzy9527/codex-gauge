import XCTest

@testable import CodexGaugeCore

final class QuotaModelsTests: XCTestCase {
  func testRemainingPercentageIsDerivedAndClamped() {
    let now = Date(timeIntervalSince1970: 1_000)

    XCTAssertEqual(
      QuotaWindow(
        id: "over",
        usedPercentage: 125,
        resetDate: now,
        windowDurationMinutes: 300
      ).remainingPercentage,
      0
    )
    XCTAssertEqual(
      QuotaWindow(
        id: "under",
        usedPercentage: -8,
        resetDate: now,
        windowDurationMinutes: 300
      ).remainingPercentage,
      100
    )
  }

  func testDisplayWindowPrefersFiveHourWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
      windows: [
        QuotaWindow(
          id: "primary",
          usedPercentage: 30,
          resetDate: now.addingTimeInterval(10_000),
          windowDurationMinutes: 300
        ),
        QuotaWindow(
          id: "secondary",
          usedPercentage: 60,
          resetDate: now.addingTimeInterval(20_000),
          windowDurationMinutes: 10_080
        ),
      ],
      resetCredits: nil,
      lastUpdated: now
    )

    XCTAssertEqual(snapshot.displayWindow?.id, "primary")
    XCTAssertEqual(snapshot.displaySelection?.period, .fiveHour)
  }

  func testDisplayWindowFallsBackToWeeklyWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
      windows: [
        QuotaWindow(
          id: "weekly",
          usedPercentage: 60,
          resetDate: now.addingTimeInterval(20_000),
          windowDurationMinutes: 10_080
        )
      ],
      resetCredits: nil,
      lastUpdated: now
    )

    XCTAssertEqual(snapshot.displayWindow?.id, "weekly")
    XCTAssertEqual(snapshot.displaySelection?.period, .weekly)
  }

  func testDisplayWindowFallsBackToTheTightestUnknownWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
      windows: [
        QuotaWindow(
          id: "later",
          usedPercentage: 50,
          resetDate: now.addingTimeInterval(20_000),
          windowDurationMinutes: 60
        ),
        QuotaWindow(
          id: "earlier",
          usedPercentage: 50,
          resetDate: now.addingTimeInterval(10_000),
          windowDurationMinutes: 120
        ),
      ],
      resetCredits: nil,
      lastUpdated: now
    )

    XCTAssertEqual(snapshot.displayWindow?.id, "earlier")
    XCTAssertEqual(snapshot.displaySelection?.period, .unknown)
  }

  func testWindowPeriodUsesDurationInsteadOfProtocolPosition() {
    let now = Date(timeIntervalSince1970: 1_000)
    let fiveHour = QuotaWindow(
      id: "secondary",
      usedPercentage: 10,
      resetDate: now,
      windowDurationMinutes: 300
    )
    let weekly = QuotaWindow(
      id: "primary",
      usedPercentage: 20,
      resetDate: now,
      windowDurationMinutes: 10_080
    )
    let unknown = QuotaWindow(
      id: "future",
      usedPercentage: 30,
      resetDate: now,
      windowDurationMinutes: 1_440
    )

    XCTAssertEqual(fiveHour.period, .fiveHour)
    XCTAssertEqual(weekly.period, .weekly)
    XCTAssertEqual(unknown.period, .unknown)
  }

  func testResetCreditCountIsClampedAndMissingDetailsAreTracked() {
    let summary = QuotaResetCredits(
      availableCount: 3,
      credits: [QuotaResetCredit(expirationDate: nil)]
    )

    XCTAssertEqual(summary.availableCount, 3)
    XCTAssertEqual(summary.unavailableDetailCount, 2)
    XCTAssertEqual(
      QuotaResetCredits(availableCount: -1, credits: nil).availableCount,
      0
    )
  }

  func testResetCreditsSortExpiringCreditsBeforeLongLivedCredits() {
    let now = Date(timeIntervalSince1970: 1_000)
    let later = now.addingTimeInterval(20_000)
    let earlier = now.addingTimeInterval(10_000)
    let summary = QuotaResetCredits(
      availableCount: 3,
      credits: [
        QuotaResetCredit(expirationDate: nil),
        QuotaResetCredit(expirationDate: later),
        QuotaResetCredit(expirationDate: earlier),
      ]
    )

    XCTAssertEqual(
      summary.displayCredits.map(\.expirationDate),
      [earlier, later, nil]
    )
  }

  func testFailureStateKeepsTheLastSuccessfulSnapshot() {
    let snapshot = QuotaSnapshot.preview(now: Date(timeIntervalSince1970: 1_000))
    let state = QuotaProviderState.failed(
      issue: .connectionInterrupted,
      previous: snapshot
    )

    XCTAssertEqual(state.snapshot, snapshot)
  }
}
