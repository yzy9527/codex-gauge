import AppKit
import CodexGaugeCore
import SwiftUI
import XCTest
import UserNotifications

#if SWIFT_PACKAGE
  @testable import CodexGaugeApp
#endif

final class GaugeSnapshotTests: XCTestCase {

  @MainActor
  func testSystemNotificationCallbacksResumeFromBackgroundQueue() async throws {
    let granted = try await withCheckedThrowingContinuation { continuation in
      let callback = SystemRecoveryNotifier.permissionCompletion(continuation)
      DispatchQueue.global().async { callback(true, nil) }
    }
    XCTAssertTrue(granted)
    let denied = try await withCheckedThrowingContinuation { continuation in
      let callback = SystemRecoveryNotifier.permissionCompletion(continuation)
      DispatchQueue.global().async { callback(false, nil) }
    }
    XCTAssertFalse(denied)
    try await withCheckedThrowingContinuation { continuation in
      let callback = SystemRecoveryNotifier.deliveryCompletion(continuation)
      DispatchQueue.global().async { callback(nil) }
    }
    do {
      try await withCheckedThrowingContinuation { continuation in
        let callback = SystemRecoveryNotifier.deliveryCompletion(continuation)
        DispatchQueue.global().async { callback(CocoaError(.fileReadUnknown)) }
      }
      XCTFail("Delivery error must reach the caller")
    } catch {
      XCTAssertEqual((error as NSError).code, CocoaError.fileReadUnknown.rawValue)
    }
    do {
      let _: Bool = try await withCheckedThrowingContinuation { continuation in
        let callback = SystemRecoveryNotifier.permissionCompletion(continuation)
        DispatchQueue.global().async { callback(false, CocoaError(.fileReadUnknown)) }
      }
      XCTFail("Permission error must reach the caller")
    } catch {
      XCTAssertEqual((error as NSError).code, CocoaError.fileReadUnknown.rawValue)
    }
  }

  @MainActor
  func testNotificationPriorityAndSuppression() async throws {
    let provider = RecoveryTestProvider()
    let notifier = RecoveryTestNotifier()
    let suite = "GaugeNotifications." + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = GaugeViewModel(provider: provider, notifier: notifier, preferences: preferences)
    XCTAssertFalse(model.recoveryNotificationsEnabled)
    await model.setRecoveryNotificationsEnabled(true)
    XCTAssertTrue(model.recoveryNotificationsEnabled)
    XCTAssertTrue(model.recoveryNotificationsActive)
    XCTAssertTrue(preferences.bool(forKey: "recoveryNotificationsEnabled"))
    provider.send(.available(recoverySnapshot(1, five: 10, weekly: 20)))
    provider.send(.available(recoverySnapshot(2, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(notifier.periods, [.weekly])
    provider.send(.available(recoverySnapshot(3, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(notifier.periods, [.weekly])
    provider.send(.available(recoverySnapshot(4, five: 10, weekly: 100)))
    provider.send(.available(recoverySnapshot(5, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(notifier.periods, [.weekly, .fiveHour])
    await model.setRecoveryNotificationsEnabled(false)
    provider.send(.available(recoverySnapshot(6, five: 10, weekly: 20)))
    provider.send(.available(recoverySnapshot(7, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(notifier.periods.count, 2)
    XCTAssertFalse(preferences.bool(forKey: "recoveryNotificationsEnabled"))
  }

  @MainActor
  func testNotificationAuthorizationDeniedRevokedAndErrors() async throws {
    let provider = RecoveryTestProvider()
    let notifier = RecoveryTestNotifier()
    let suite = "GaugePermissions." + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = GaugeViewModel(provider: provider, notifier: notifier, preferences: preferences)
    notifier.status = .notDetermined
    notifier.grant = false
    await model.setRecoveryNotificationsEnabled(true)
    XCTAssertEqual(notifier.requests, 1)
    XCTAssertFalse(model.recoveryNotificationsEnabled)
    XCTAssertEqual(model.notificationAuthorization, .denied)
    XCTAssertFalse(model.recoveryNotificationsActive)
    await model.setRecoveryNotificationsEnabled(true)
    XCTAssertEqual(notifier.requests, 1)
    notifier.status = .authorized
    await model.setRecoveryNotificationsEnabled(true)
    notifier.status = .denied
    provider.send(.available(recoverySnapshot(1, five: 10, weekly: 20)))
    provider.send(.available(recoverySnapshot(2, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertTrue(notifier.periods.isEmpty)
    XCTAssertEqual(model.notificationAuthorization, .denied)
    XCTAssertFalse(model.recoveryNotificationsActive)
    notifier.status = .authorized
    notifier.failSend = true
    provider.send(.available(recoverySnapshot(3, five: 10, weekly: 20)))
    provider.send(.available(recoverySnapshot(4, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(model.notificationError, L10n.text("recovery.sendError"))
    notifier.status = .notDetermined
    notifier.failPermission = true
    await model.setRecoveryNotificationsEnabled(true)
    XCTAssertEqual(model.notificationError, L10n.text("recovery.permissionError"))
    XCTAssertFalse(model.isChangingNotificationPermission)
  }

  @MainActor
  func testRecoveryIgnoresInitialMissingSignedOutAndStaleSnapshots() async throws {
    let provider = RecoveryTestProvider()
    let notifier = RecoveryTestNotifier()
    let suite = "GaugeBaseline." + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = GaugeViewModel(provider: provider, notifier: notifier, preferences: preferences)
    await model.setRecoveryNotificationsEnabled(true)
    provider.send(.available(recoverySnapshot(1, five: nil, weekly: 100)))
    provider.send(.available(recoverySnapshot(2, five: 100, weekly: 100)))
    provider.send(.available(recoverySnapshot(3, five: 10, weekly: 10)))
    provider.send(.available(recoverySnapshot(2, five: 100, weekly: 100)))
    provider.send(.signedOut(previous: provider.currentState.snapshot))
    provider.send(.available(recoverySnapshot(4, five: 100, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertTrue(notifier.periods.isEmpty)
    provider.send(.available(recoverySnapshot(5, five: nil, weekly: 10)))
    provider.send(.failed(issue: .timeout, previous: provider.currentState.snapshot))
    provider.send(.available(recoverySnapshot(6, five: nil, weekly: 99.9)))
    XCTAssertTrue(notifier.periods.isEmpty)
    provider.send(.available(recoverySnapshot(7, five: nil, weekly: 100)))
    await model.notificationTask?.value
    XCTAssertEqual(notifier.periods, [.weekly])
  }

  @MainActor
  func testDisablingNotificationsCancelsScheduledDelivery() async throws {
    let provider = RecoveryTestProvider()
    let notifier = RecoveryTestNotifier()
    let suite = "GaugeCancellation." + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = GaugeViewModel(provider: provider, notifier: notifier, preferences: preferences)
    await model.setRecoveryNotificationsEnabled(true)
    provider.send(.available(recoverySnapshot(1, five: 10, weekly: 20)))
    provider.send(.available(recoverySnapshot(2, five: 100, weekly: 100)))
    await model.setRecoveryNotificationsEnabled(false)
    await model.notificationTask?.value
    XCTAssertTrue(notifier.periods.isEmpty)
    XCTAssertGreaterThan(notifier.removals, 0)
  }

  @MainActor
  func testNotificationClickOpensReusableQuotaPanel() throws {
    _ = NSApplication.shared
    let notifier = RecoveryTestNotifier()
    let model = GaugeViewModel(provider: RecoveryTestProvider(), notifier: notifier)
    notifier.onOpen?()
    let panel = try XCTUnwrap(NSApplication.shared.windows.first {
      $0 is NSPanel && $0.title == "Codex Gauge"
    })
    defer {
      panel.close()
      panel.contentView = nil
    }
    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.contentView?.frame.width ?? 0, 326, accuracy: 1)
    panel.close()
    notifier.onOpen?()
    XCTAssertTrue(panel.isVisible)
    XCTAssertNil(model.snapshot)
    XCTAssertNotNil(panel.contentView)
  }

  @MainActor
  func testPermissionRequestHidesPanelBeforePromptOnlyWhenNeeded() async throws {
    let notifier = RecoveryTestNotifier()
    notifier.status = .notDetermined
    let suite = "GaugePromptOrder." + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let model = GaugeViewModel(provider: RecoveryTestProvider(), notifier: notifier, preferences: preferences)
    var hides = 0
    await model.setRecoveryNotificationsEnabled(true) {
      XCTAssertEqual(notifier.requests, 0)
      hides += 1
    }
    XCTAssertEqual(hides, 1)
    XCTAssertEqual(notifier.requests, 1)
    await model.setRecoveryNotificationsEnabled(false) { hides += 1 }
    await model.setRecoveryNotificationsEnabled(true) { hides += 1 }
    XCTAssertEqual(hides, 1)
  }

  @MainActor
  func testNotificationContent() {
    for period in [QuotaWindowPeriod.fiveHour, .weekly] {
      let content = SystemRecoveryNotifier.content(for: period)
      XCTAssertEqual(content.title, L10n.text(period == .weekly ? "recovery.weekly" : "recovery.fiveHour"))
      XCTAssertEqual(content.body, L10n.text("recovery.body"))
      XCTAssertNotNil(content.sound)
    }
  }

  private func recoverySnapshot(_ time: Double, five: Double?, weekly: Double?) -> QuotaSnapshot {
    let windows = [(300, five), (10_080, weekly)].compactMap { duration, remaining -> QuotaWindow? in
      guard let remaining else { return nil }
      return QuotaWindow(id: String(duration), usedPercentage: 100 - remaining,
        resetDate: Date(timeIntervalSince1970: 2_000_000_000), windowDurationMinutes: duration)
    }
    return QuotaSnapshot(windows: windows, resetCredits: nil, lastUpdated: Date(timeIntervalSince1970: time))
  }

  func testQuotaColorUsesTwentyAndSixtyPercentBoundaries() {
    XCTAssertEqual(GaugePalette.quotaColor(for: 0), GaugePalette.red)
    XCTAssertEqual(GaugePalette.quotaColor(for: 19.99), GaugePalette.red)
    XCTAssertEqual(GaugePalette.quotaColor(for: 20), GaugePalette.orange)
    XCTAssertEqual(GaugePalette.quotaColor(for: 59.99), GaugePalette.orange)
    XCTAssertEqual(GaugePalette.quotaColor(for: 60), GaugePalette.green)
    XCTAssertEqual(GaugePalette.quotaColor(for: 100), GaugePalette.green)
  }

  @MainActor
  func testReferencePanelVariants() async throws {
    let now = Date()
    for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
      for (name, state) in [
        ("weekly", QuotaProviderState.available(QuotaSnapshot(
          windows: [QuotaWindow(id: "weekly", usedPercentage: 28,
            resetDate: now.addingTimeInterval(86_400), windowDurationMinutes: 10_080)],
          resetCredits: QuotaResetCredits(availableCount: 1, credits: [
            QuotaResetCredit(expirationDate: now.addingTimeInterval(172_800))
          ]), lastUpdated: now))),
        ("low", QuotaProviderState.available(recoverySnapshot(now.timeIntervalSince1970, five: nil, weekly: 35))),
        ("double", QuotaProviderState.available(.preview())),
        ("denied", QuotaProviderState.available(.preview())),
        ("empty", QuotaProviderState.failed(issue: .timeout, previous: nil)),
        ("stale", QuotaProviderState.failed(issue: .timeout, previous: .preview())),
        ("missing-cli", QuotaProviderState.unsupported(issue: .executableNotFound, previous: .preview())),
        ("launch-failed", QuotaProviderState.unsupported(issue: .launchFailed, previous: .preview())),
        ("paused", QuotaProviderState.failed(issue: .automaticRefreshPaused, previous: .preview())),
      ] {
        let notifier = RecoveryTestNotifier()
        if name == "denied" { notifier.status = .denied }
        let model = GaugeViewModel(provider: MockQuotaProvider(initialState: state), notifier: notifier)
        await model.refreshNotificationAuthorization()
        let host = NSHostingView(rootView: GaugePopoverView(viewModel: model).environment(\.locale, locale))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.frame.width, 326, accuracy: 1)
        XCTAssertLessThan(host.frame.height, 620)
        if ProcessInfo.processInfo.environment["CODEX_GAUGE_RENDER_PREVIEW"] == "1" {
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
          try data.write(to: URL(fileURLWithPath: "/tmp/gauge-reference-\(name)-\(locale.identifier).png"))
        }
        window.close()
      }
    }
  }

  func testLocalizesStaticAndDynamicStringsInEnglishAndSimplifiedChinese() {
    let english = Locale(identifier: "en")
    let chinese = Locale(identifier: "zh-Hans")

    XCTAssertEqual(L10n.text("action.retry", locale: english), "Try Again")
    XCTAssertEqual(L10n.text("action.retry", locale: chinese), "重新读取")
    XCTAssertEqual(
      L10n.localizationIdentifier(for: Locale(identifier: "zh-Hant")).lowercased(),
      "zh-hans"
    )
    XCTAssertEqual(
      L10n.text("action.retry", locale: Locale(identifier: "zh-Hant")),
      "重新读取"
    )
    XCTAssertEqual(
      L10n.text("action.retry", locale: Locale(identifier: "fr")),
      "Try Again"
    )
    XCTAssertEqual(L10n.availableResetCount(1, locale: Locale(identifier: "fr")), "1 reset")
    XCTAssertEqual(L10n.availableResetCount(1, locale: english), "1 reset")
    XCTAssertEqual(L10n.availableResetCount(2, locale: english), "2 resets")
    XCTAssertEqual(L10n.availableResetCount(2, locale: chinese), "2 次")
    XCTAssertEqual(L10n.hoursUntilReset(1, locale: english), "1 hour remaining")
    XCTAssertEqual(L10n.hoursUntilReset(2, locale: english), "2 hours remaining")
    XCTAssertEqual(L10n.hoursUntilReset(2, locale: chinese), "还有 2 小时")
    XCTAssertEqual(
      L10n.remainingQuotaTitle(for: .fiveHour, locale: english),
      "5-hour remaining"
    )
    XCTAssertEqual(
      L10n.remainingQuotaTitle(for: .weekly, locale: chinese),
      "一周剩余额度"
    )
  }

  @MainActor
  func testExecutableSelectionUsesSemanticIssueInsteadOfLocalizedText() {
    let selectable = GaugeViewModel(
      provider: MockQuotaProvider(
        initialState: .unsupported(issue: .executableNotFound, previous: nil)
      )
    )
    let unsupportedVersion = GaugeViewModel(
      provider: MockQuotaProvider(
        initialState: .unsupported(issue: .methodUnavailable, previous: nil)
      )
    )

    let launchFailure = GaugeViewModel(
      provider: MockQuotaProvider(
        initialState: .unsupported(issue: .launchFailed, previous: nil)
      )
    )
    XCTAssertTrue(launchFailure.canSelectCodexExecutable)
    XCTAssertTrue(selectable.canSelectCodexExecutable)
    XCTAssertFalse(unsupportedVersion.canSelectCodexExecutable)
    for issue in [QuotaProviderIssue.executableNotFound, .launchFailed] {
      let stale = GaugeViewModel(provider: MockQuotaProvider(
        initialState: .unsupported(issue: issue, previous: .preview())
      ))
      XCTAssertNotNil(stale.snapshot)
      XCTAssertTrue(stale.canSelectCodexExecutable)
    }
  }

  @MainActor
  func testMenuBarFallsBackToWeeklyWindowWhenFiveHourWindowIsUnavailable() {
    let now = Date(timeIntervalSince1970: 1_000)
    let weeklyWindow = QuotaWindow(
      id: "weekly",
      usedPercentage: 40,
      resetDate: now.addingTimeInterval(10_000),
      windowDurationMinutes: 10_080
    )
    let snapshot = QuotaSnapshot(
      windows: [weeklyWindow],
      resetCredits: nil,
      lastUpdated: now
    )
    let viewModel = GaugeViewModel(
      provider: MockQuotaProvider(initialState: .available(snapshot))
    )

    XCTAssertEqual(viewModel.displaySelection?.period, .weekly)
    XCTAssertEqual(viewModel.displaySelection?.window, weeklyWindow)
    XCTAssertEqual(
      viewModel.menuBarAccessibilityLabel,
      L10n.menuBarRemaining(60, period: .weekly)
    )
  }

  @MainActor
  func testOpenCodexReportsWhenApplicationIsNotInstalled() async {
    let opener = StubCodexApplicationOpener(applicationURL: nil)
    let viewModel = GaugeViewModel(
      provider: MockQuotaProvider(),
      applicationOpener: opener
    )

    await viewModel.openCodex()

    XCTAssertEqual(viewModel.actionMessage, L10n.text("error.codexAppNotFound"))
    XCTAssertTrue(opener.openedURLs.isEmpty)
  }

  @MainActor
  func testOpenCodexMapsLaunchFailureAndSuccessToActionMessage() async {
    let applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
    let opener = StubCodexApplicationOpener(
      applicationURL: applicationURL,
      shouldOpen: false
    )
    let viewModel = GaugeViewModel(
      provider: MockQuotaProvider(),
      applicationOpener: opener
    )

    await viewModel.openCodex()

    XCTAssertEqual(viewModel.actionMessage, L10n.text("error.codexAppOpenFailed"))
    XCTAssertEqual(opener.openedURLs, [applicationURL])

    opener.shouldOpen = true
    await viewModel.openCodex()

    XCTAssertNil(viewModel.actionMessage)
    XCTAssertEqual(opener.openedURLs, [applicationURL, applicationURL])
  }

  @MainActor
  func testMenuBarIconRendersNormalLoadingAndErrorStates() throws {
    let snapshot = QuotaSnapshot.preview()
    let templateImage = MenuBarPromptRingImage.make(progress: 0.62, showsError: false)
    XCTAssertTrue(templateImage.isTemplate)
    XCTAssertEqual(templateImage.size, NSSize(width: 18, height: 18))

    let cases = [
      MenuBarGaugeIcon(
        remainingPercentage: snapshot.displayWindow?.remainingPercentage,
        state: .available(snapshot)
      ),
      MenuBarGaugeIcon(
        remainingPercentage: nil,
        state: .loading(previous: nil)
      ),
      MenuBarGaugeIcon(
        remainingPercentage: nil,
        state: .failed(issue: .unknown, previous: nil)
      ),
      MenuBarGaugeIcon(
        remainingPercentage: snapshot.displayWindow?.remainingPercentage,
        state: .failed(issue: .unknown, previous: snapshot)
      ),
    ]

    for (index, view) in cases.enumerated() {
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2

      let image = try XCTUnwrap(renderer.nsImage)
      XCTAssertEqual(image.size.height, 18, accuracy: 0.5)
      XCTAssertGreaterThanOrEqual(image.size.width, 32)

      if ProcessInfo.processInfo.environment["CODEX_GAUGE_RENDER_PREVIEW"] == "1" {
        try writeMenuBarPreview(view, index: index, colorScheme: .light)
        try writeMenuBarPreview(view, index: index, colorScheme: .dark)
      }
    }
  }

  @MainActor
  func testPopoverRendersAtExpectedWidth() throws {
    let viewModel = GaugeViewModel(provider: MockQuotaProvider())
    let renderer = ImageRenderer(
      content: GaugePopoverView(viewModel: viewModel)
    )
    renderer.scale = 2

    guard let image = renderer.nsImage else {
      return XCTFail("SwiftUI popover did not render")
    }

    XCTAssertEqual(image.size.width, 326, accuracy: 0.5)
    XCTAssertGreaterThan(image.size.height, 360)

    for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
      let localizedRenderer = ImageRenderer(
        content: GaugePopoverView(viewModel: viewModel)
          .environment(\.locale, locale)
      )
      localizedRenderer.scale = 2
      let localizedImage = try XCTUnwrap(localizedRenderer.nsImage)
      XCTAssertEqual(localizedImage.size.width, 326, accuracy: 0.5)
      XCTAssertGreaterThan(localizedImage.size.height, 360)

      if ProcessInfo.processInfo.environment["CODEX_GAUGE_RENDER_PREVIEW"] == "1" {
        try writePNG(
          localizedImage,
          to: URL(
            fileURLWithPath: "/tmp/codex-gauge-preview-\(locale.identifier).png"
          )
        )
      }
    }

    guard ProcessInfo.processInfo.environment["CODEX_GAUGE_RENDER_PREVIEW"] == "1" else {
      return
    }

    try writePNG(
      image,
      to: URL(fileURLWithPath: "/tmp/codex-gauge-preview.png")
    )
  }

  private func writePNG(_ image: NSImage, to outputURL: URL) throws {
    let representation = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: representation))
    let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try pngData.write(to: outputURL, options: .atomic)
  }

  @MainActor
  private func writeMenuBarPreview(
    _ view: MenuBarGaugeIcon,
    index: Int,
    colorScheme: ColorScheme
  ) throws {
    let background = colorScheme == .light ? Color.white : Color.black
    let renderer = ImageRenderer(
      content:
        view
        .environment(\.colorScheme, colorScheme)
        .padding(12)
        .background(background)
    )
    renderer.scale = 4

    let image = try XCTUnwrap(renderer.nsImage)
    let suffix = colorScheme == .light ? "light" : "dark"
    try writePNG(
      image,
      to: URL(fileURLWithPath: "/tmp/codex-gauge-menu-icon-\(index)-\(suffix).png")
    )
  }
}

@MainActor
private final class StubCodexApplicationOpener: CodexApplicationOpening {
  let applicationURL: URL?
  var shouldOpen: Bool
  private(set) var openedURLs: [URL] = []

  init(applicationURL: URL?, shouldOpen: Bool = true) {
    self.applicationURL = applicationURL
    self.shouldOpen = shouldOpen
  }

  func installedApplicationURL() -> URL? {
    applicationURL
  }

  func openApplication(at url: URL) async -> Bool {
    openedURLs.append(url)
    return shouldOpen
  }
}

@MainActor
private final class RecoveryTestNotifier: RecoveryNotifying {
  var onOpen: (() -> Void)?
  var periods: [QuotaWindowPeriod] = []
  var status: RecoveryNotificationAuthorization = .authorized
  var grant = true
  var requests = 0
  var removals = 0
  var failPermission = false
  var failSend = false
  func authorization() async -> RecoveryNotificationAuthorization { status }
  func requestAuthorization() async throws -> Bool {
    requests += 1
    if failPermission { throw CocoaError(.fileReadUnknown) }
    status = grant ? .authorized : .denied
    return grant
  }
  func send(period: QuotaWindowPeriod) async throws {
    if failSend { throw CocoaError(.fileReadUnknown) }
    periods.append(period)
  }
  func removePending() { removals += 1 }
}

@MainActor
private final class RecoveryTestProvider: QuotaProvider {
  var currentState: QuotaProviderState = .idle
  var observer: (@MainActor (QuotaProviderState) -> Void)?
  func observeState(_ observer: @escaping @MainActor (QuotaProviderState) -> Void) {
    self.observer = observer
    observer(currentState)
  }
  func send(_ state: QuotaProviderState) {
    currentState = state
    observer?(state)
  }
  func refresh() async {}
  func selectCodexExecutable(at url: URL) async throws {}
  func shutdown() async {}
}
