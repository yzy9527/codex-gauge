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
              "windowDurationMins": 300,
              "resetsAt": 3000
            },
            "secondary": {
              "usedPercent": 65,
              "windowDurationMins": 10080,
              "resetsAt": 6000
            },
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

    XCTAssertEqual(snapshot.windows.count, 2)
    XCTAssertEqual(snapshot.displayWindow?.usedPercentage, 35)
    XCTAssertEqual(snapshot.displayWindow?.resetDate, Date(timeIntervalSince1970: 3_000))
    XCTAssertEqual(snapshot.displaySelection?.period, .fiveHour)
    XCTAssertEqual(snapshot.weeklyWindow?.usedPercentage, 65)
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

  func testIdentifiesFiveHourWindowWhenProtocolPositionsAreReversed() throws {
    let response = Data(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 70,
            "windowDurationMins": 10080,
            "resetsAt": 7000
          },
          "secondary": {
            "usedPercent": 25,
            "windowDurationMins": 300,
            "resetsAt": 2500
          }
        }
      }
      """.utf8
    )

    let snapshot = try CodexQuotaMapper.snapshot(from: response)

    XCTAssertEqual(snapshot.fiveHourWindow?.id, "secondary")
    XCTAssertEqual(snapshot.weeklyWindow?.id, "primary")
    XCTAssertEqual(snapshot.displayWindow?.id, "secondary")
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

  func testResolverSkipsSavedDirectoryAndFindsExecutableOnPath() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("codex")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let suiteName = "CodexGaugeResolverTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(directory.path, forKey: "CodexGauge.codexExecutablePath")

    XCTAssertFalse(CodexExecutableResolver.isValidExecutable(at: directory))
    XCTAssertEqual(
      CodexExecutableResolver.resolve(environment: ["PATH": directory.path], defaults: defaults),
      executable
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
    XCTAssertFalse(CodexExecutableResolver.isValidExecutable(at: executable))
    XCTAssertFalse(CodexExecutableResolver.isValidExecutable(at: directory.appendingPathComponent("missing")))
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
