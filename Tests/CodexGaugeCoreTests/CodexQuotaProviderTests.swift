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
      guard case CodexQuotaMappingError.invalidResponse = error else {
        return XCTFail("Unexpected mapping error: \(error)")
      }
    }
  }

  func testRejectsMalformedWindowEvenWhenOtherWindowIsValid() throws {
    for slot in ["primary", "secondary"] {
      for resetField in ["", #", "resetsAt": null"#, #", "resetsAt": "invalid""#] {
        let other = slot == "primary" ? "secondary" : "primary"
        let response = Data("""
          {"rateLimits": {
            "\(slot)": {"usedPercent": 95, "windowDurationMins": 300\(resetField)},
            "\(other)": {"usedPercent": 20, "windowDurationMins": 10080, "resetsAt": 6000}
          }}
          """.utf8)
        XCTAssertThrowsError(try CodexQuotaMapper.snapshot(from: response)) { error in
          guard case CodexQuotaMappingError.invalidResponse = error else {
            return XCTFail("Unexpected mapping error: \(error)")
          }
        }
      }
    }
  }

  func testAbsentWindowStillAllowsWeeklySnapshot() throws {
    for slot in ["primary", "secondary"] {
      let other = slot == "primary" ? "secondary" : "primary"
      for absentField in ["", ", \"\(other)\": null"] {
        let response = Data("""
          {"rateLimits": {
            "\(slot)": {"usedPercent": 20, "windowDurationMins": 10080, "resetsAt": 6000}
            \(absentField)
          }}
          """.utf8)
        let snapshot = try CodexQuotaMapper.snapshot(from: response)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.displaySelection?.period, .weekly)
        XCTAssertEqual(snapshot.displayWindow?.remainingPercentage, 80)
      }
    }
  }

  @MainActor
  func testTransportHandshakeAndMalformedRefreshPreservesSnapshot() async throws {
    let fixture = try AppServerFixture(onRead: """
      if (++$reads == 1) { print qq({"id":$id,"result":\(AppServerFixture.validResult)}\\n); }
      else { print qq({"id":$id,"result":{"rateLimits":{"primary":{"usedPercent":95,"windowDurationMins":300},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":6000}}}}\\n); }
      """)
    defer { fixture.remove() }
    let provider = CodexQuotaProvider(client: fixture.client())
    await provider.refresh()
    let previous = try XCTUnwrap(provider.currentState.snapshot)
    XCTAssertEqual(previous.fiveHourWindow?.remainingPercentage, 5)
    XCTAssertEqual(previous.weeklyWindow?.remainingPercentage, 80)
    await provider.refresh()
    XCTAssertEqual(provider.currentState, .failed(issue: .incompatibleResponse, previous: previous))
    await provider.shutdown()
  }

  @MainActor
  func testTransportInitializationAndReadTimeouts() async throws {
    for duringInitialization in [true, false] {
      let fixture = try AppServerFixture(
        onInitialize: duringInitialization ? "sleep 60;" : nil,
        onRead: "sleep 60;"
      )
      defer { fixture.remove() }
      let provider = CodexQuotaProvider(client: fixture.client(timeout: .milliseconds(100)))
      await provider.refresh()
      XCTAssertEqual(provider.currentState, .failed(issue: .timeout, previous: nil))
      await provider.shutdown()
    }
  }

  func testPeerExitDuringHandshakeDoesNotTerminateApplication() async throws {
    let fixture = try AppServerFixture(
      onInitialize: #"print qq({"id":$id,"result":{}}\n); exit 1;"#,
      onRead: "exit 1;"
    )
    defer { fixture.remove() }
    for _ in 0..<10 {
      let client = fixture.client()
      do {
        _ = try await client.readRateLimits()
        XCTFail("Expected an interrupted connection")
      } catch {
        guard case CodexAppServerError.processExited = error else {
          await client.shutdown()
          return XCTFail("Unexpected error: \(error)")
        }
      }
      await client.shutdown()
    }
  }

  @MainActor
  func testTransportClassifiesMethodMissingAndSignedOut() async throws {
    for (code, message, expected) in [
      (-32601, "Method not found", QuotaProviderState.unsupported(issue: .methodUnavailable, previous: nil)),
      (-32000, "Unauthorized", QuotaProviderState.signedOut(previous: nil)),
    ] {
      let fixture = try AppServerFixture(onRead:
        "print qq({\"id\":$id,\"error\":{\"code\":\(code),\"message\":\"\(message)\"}}\\n);")
      defer { fixture.remove() }
      let provider = CodexQuotaProvider(client: fixture.client())
      await provider.refresh()
      XCTAssertEqual(provider.currentState, expected)
      await provider.shutdown()
    }
  }

  @MainActor
  func testRepeatedExitsPauseAutomaticRestartsAndManualRefreshRecovers() async throws {
    let fixture = try AppServerFixture(onRead: """
      if ($launch <= 3) { exit 1; }
      print qq({"id":$id,"result":\(AppServerFixture.validResult)}\\n);
      """)
    defer { fixture.remove() }
    let provider = CodexQuotaProvider(client: fixture.client(), automaticRefreshInterval: .milliseconds(30))
    await provider.refresh()
    for _ in 0..<100 {
      if case .failed(issue: .automaticRefreshPaused, _) = provider.currentState { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertEqual(provider.currentState, .failed(issue: .automaticRefreshPaused, previous: nil))
    try await Task.sleep(for: .milliseconds(120))
    XCTAssertEqual(try fixture.launchCount(), 3)
    await provider.refresh()
    XCTAssertNotNil(provider.currentState.snapshot)
    XCTAssertEqual(try fixture.launchCount(), 4)
    await provider.shutdown()
    try await Task.sleep(for: .milliseconds(120))
    XCTAssertEqual(try fixture.launchCount(), 4)
  }

  @MainActor
  func testIdleProcessExitPreservesSnapshotAndPausesAfterThreeExits() async throws {
    let fixture = try AppServerFixture(onRead: """
      print qq({"id":$id,"result":\(AppServerFixture.validResult)}\\n);
      select(undef, undef, undef, 0.02);
      exit 1;
      """)
    defer { fixture.remove() }
    let provider = CodexQuotaProvider(client: fixture.client(), automaticRefreshInterval: .milliseconds(70))
    await provider.refresh()
    for _ in 0..<150 {
      if case .failed(issue: .automaticRefreshPaused, _) = provider.currentState { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    guard case .failed(issue: .automaticRefreshPaused, let previous) = provider.currentState else {
      await provider.shutdown()
      return XCTFail("Expected automatic refresh to pause")
    }
    XCTAssertEqual(previous?.fiveHourWindow?.remainingPercentage, 5)
    XCTAssertEqual(try fixture.launchCount(), 3)
    await provider.shutdown()
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

// A local stdio peer with fictional data; never resolves the user's Codex installation.
private struct AppServerFixture {
  static let validResult = #"{"rateLimits":{"primary":{"usedPercent":95,"windowDurationMins":300,"resetsAt":3000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":6000}}}"#
  let directory: URL
  let executable: URL

  init(onInitialize: String? = nil, onRead: String) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("gauge-peer-" + UUID().uuidString)
    executable = directory.appendingPathComponent("codex")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = """
      #!/bin/sh
      export LC_ALL=C
      exec /usr/bin/perl -x "$0" "$@"
      #!perl
      use strict;
      use warnings;
      $| = 1;
      my $counter = '\(directory.appendingPathComponent("launches").path)';
      my $launch = 0;
      if (open(my $in, '<', $counter)) { $launch = <$in>; close($in); }
      open(my $out, '>', $counter) or die;
      ++$launch;
      print {$out} $launch;
      close($out);
      my $initialized = 0;
      my $reads = 0;
      while (my $line = <STDIN>) {
        my ($id) = $line =~ /"id"\\s*:\\s*(\\d+)/;
        if ($line =~ /"method"\\s*:\\s*"initialize"/) {
          \(onInitialize ?? #"print qq({"id":$id,"result":{}}\n);"#)
        } elsif ($line =~ /"method"\\s*:\\s*"initialized"/) {
          $initialized = 1;
        } elsif (defined $id) {
          die 'missing initialized notification' unless $initialized;
          \(onRead)
        }
      }
      """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
  }

  func client(timeout: Duration = .seconds(2)) -> CodexAppServerClient {
    CodexAppServerClient(initializationTimeout: timeout, rateLimitsTimeout: timeout, executableURL: executable)
  }

  func launchCount() throws -> Int {
    Int(try String(contentsOf: directory.appendingPathComponent("launches"), encoding: .utf8)) ?? 0
  }

  func remove() { try? FileManager.default.removeItem(at: directory) }
}
