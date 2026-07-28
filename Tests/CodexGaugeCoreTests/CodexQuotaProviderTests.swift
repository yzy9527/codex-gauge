import XCTest

@testable import CodexGaugeCore

final class CodexQuotaProviderTests: XCTestCase {
  @MainActor
  func testLiveProviderWhenExplicitlyEnabled() async throws {
    guard ProcessInfo.processInfo.environment["CODEX_GAUGE_LIVE_TEST"] == "1" else {
      throw XCTSkip("Live account test is opt-in")
    }

    let provider = CodexQuotaProvider()
    await provider.refresh()

    guard case .available(let snapshot) = provider.currentState else {
      let category: String
      switch provider.currentState {
      case .idle:
        category = "idle"
      case .loading:
        category = "loading"
      case .signedOut:
        category = "signedOut"
      case .unsupported(let issue, _):
        category = "unsupported: \(issue)"
      case .unavailable(let issue, _):
        category = "unavailable: \(issue)"
      case .failed(let issue, _):
        category = "failed: \(issue)"
      case .available:
        category = "available"
      }
      return XCTFail("Live quota read state category: \(category)")
    }
    XCTAssertNotNil(snapshot.displayWindow)
  }

  func testMapsCodexBucketAndResetCreditsWithoutKeepingMetadata() throws {
    let response = Data(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 8,
            "windowDurationMins": 300,
            "resetsAt": 2000
          }
        },
        "rateLimitsByLimitId": {
          "codex": {
            "primary": {
              "usedPercent": 35,
              "windowDurationMins": 10080,
              "resetsAt": 3000
            },
            "secondary": null,
            "unknownFutureField": true
          }
        },
        "rateLimitResetCredits": {
          "availableCount": 2,
          "credits": [
            { "expiresAt": 5000, "unknownFutureField": "ignored" },
            { "expiresAt": null }
          ]
        },
        "unknownFutureField": { "nested": true }
      }
      """.utf8
    )

    let snapshot = try CodexQuotaMapper.snapshot(
      from: response,
      now: Date(timeIntervalSince1970: 1_000)
    )

    XCTAssertEqual(snapshot.windows.count, 1)
    XCTAssertEqual(snapshot.displayWindow?.usedPercentage, 35)
    XCTAssertEqual(snapshot.displayWindow?.resetDate, Date(timeIntervalSince1970: 3_000))
    XCTAssertEqual(snapshot.resetCredits?.availableCount, 2)
    XCTAssertEqual(
      snapshot.resetCredits?.displayCredits.map(\.expirationDate),
      [Date(timeIntervalSince1970: 5_000), nil]
    )
    XCTAssertEqual(snapshot.lastUpdated, Date(timeIntervalSince1970: 1_000))
  }

  func testFallsBackToLegacyRateLimitsBucket() throws {
    let response = Data(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 72,
            "windowDurationMins": null,
            "resetsAt": 4000
          }
        },
        "rateLimitsByLimitId": null,
        "rateLimitResetCredits": null
      }
      """.utf8
    )

    let snapshot = try CodexQuotaMapper.snapshot(from: response)

    XCTAssertEqual(snapshot.displayWindow?.remainingPercentage, 28)
    XCTAssertEqual(snapshot.displayWindow?.windowDurationMinutes, 0)
    XCTAssertNil(snapshot.resetCredits)
  }

  func testRejectsResponseWithoutUsableResetDate() {
    let response = Data(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 20,
            "resetsAt": null
          }
        }
      }
      """.utf8
    )

    XCTAssertThrowsError(try CodexQuotaMapper.snapshot(from: response)) { error in
      guard case CodexQuotaMappingError.missingQuotaWindow = error else {
        return XCTFail("Unexpected mapping error: \(error)")
      }
    }
  }

  func testExecutableResolverUsesPathWithoutEmbeddingAccountData() {
    let executable = CodexExecutableResolver.resolve(
      environment: ["PATH": "/path/that/does/not/exist"],
      defaults: UserDefaults(suiteName: "CodexGaugeResolverTests")!
    )

    XCTAssertTrue(
      executable == nil || FileManager.default.isExecutableFile(atPath: executable!.path))
  }
}
