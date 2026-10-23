import AppKit
import CodexGaugeCore
import Foundation
import SwiftUI

@MainActor
final class GaugeViewModel: ObservableObject {
  @Published private(set) var state: QuotaProviderState
  @Published private(set) var actionMessage: String?

  @Published private(set) var recoveryNotificationsEnabled: Bool
  @Published private(set) var notificationAuthorization: RecoveryNotificationAuthorization = .notDetermined
  @Published private(set) var isChangingNotificationPermission = false
  @Published private(set) var notificationError: String?

  private let preferences: UserDefaults
  private let notifier: any RecoveryNotifying
  private(set) var notificationTask: Task<Void, Never>?
  private var lastSuccessfulSnapshot: QuotaSnapshot?
  private let quotaPanelController = QuotaPanelController()

  private let provider: any QuotaProvider
  private let applicationOpener: any CodexApplicationOpening
  private var hasStarted = false
  private var launchObserver: NSObjectProtocol?

  init(
    provider: any QuotaProvider,
    applicationOpener: any CodexApplicationOpening = WorkspaceCodexApplicationOpener(),
    notifier: any RecoveryNotifying = SystemRecoveryNotifier(),
    preferences: UserDefaults = .standard
  ) {
    self.preferences = preferences
    self.notifier = notifier
    recoveryNotificationsEnabled = preferences.bool(forKey: "recoveryNotificationsEnabled")
    self.provider = provider
    self.applicationOpener = applicationOpener
    state = provider.currentState

    notifier.onOpen = { [weak self] in
      guard let self else { return }
      self.quotaPanelController.show(viewModel: self)
    }

    provider.observeState { [weak self] state in
      self?.receive(state)
    }
  }

  var snapshot: QuotaSnapshot? {
    state.snapshot
  }

  var displaySelection: QuotaDisplaySelection? {
    snapshot?.displaySelection
  }

  var canSelectCodexExecutable: Bool {
    guard case .unsupported(let issue, _) = state else { return false }
    return issue == .executableNotFound || issue == .launchFailed
  }

  var menuBarAccessibilityLabel: String {
    guard let displaySelection else {
      return L10n.text("accessibility.menuBarUnavailable")
    }
    return L10n.menuBarRemaining(
      Int(displaySelection.window.remainingPercentage.rounded()),
      period: displaySelection.period
    )
  }

  var recoveryNotificationsActive: Bool {
    recoveryNotificationsEnabled && notificationAuthorization == .authorized
  }

  func refreshNotificationAuthorization() async {
    notificationAuthorization = await notifier.authorization()
  }

  func setRecoveryNotificationsEnabled(
    _ enabled: Bool, beforeRequest: () -> Void = {}
  ) async {
    guard !isChangingNotificationPermission else { return }
    notificationError = nil
    if !enabled {
      recoveryNotificationsEnabled = false
      preferences.set(false, forKey: "recoveryNotificationsEnabled")
      notificationTask?.cancel()
      notifier.removePending()
      return
    }
    isChangingNotificationPermission = true
    defer { isChangingNotificationPermission = false }
    await refreshNotificationAuthorization()
    if notificationAuthorization == .notDetermined {
      do {
        beforeRequest()
        _ = try await notifier.requestAuthorization()
        await refreshNotificationAuthorization()
      } catch {
        notificationError = L10n.text("recovery.permissionError")
        return
      }
    }
    recoveryNotificationsEnabled = notificationAuthorization == .authorized
    preferences.set(recoveryNotificationsEnabled, forKey: "recoveryNotificationsEnabled")
  }

  func openNotificationSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
      NSWorkspace.shared.open(url)
    else {
      notificationError = L10n.text("recovery.settingsError")
      return
    }
  }

  private func notifyRecovery(_ period: QuotaWindowPeriod) {
    guard recoveryNotificationsEnabled else { return }
    notificationTask?.cancel()
    notificationTask = Task { [weak self] in
      guard let self else { return }
      await refreshNotificationAuthorization()
      guard !Task.isCancelled, recoveryNotificationsEnabled,
        notificationAuthorization == .authorized else { return }
      do {
        try await notifier.send(period: period)
        if !Task.isCancelled { notificationError = nil }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        notificationError = L10n.text("recovery.sendError")
      }
    }
  }

  private func receive(_ newState: QuotaProviderState) {
    state = newState
    switch newState {
    case .signedOut, .idle:
      lastSuccessfulSnapshot = nil
      notificationTask?.cancel()
      notifier.removePending()
    case .available(let snapshot):
      let previous = lastSuccessfulSnapshot
      // Reject duplicate or out-of-order success events for recovery detection.
      if let previous, snapshot.lastUpdated <= previous.lastUpdated { return }
      lastSuccessfulSnapshot = snapshot
      guard let previous else { return }
      let pairs: [(QuotaWindow?, QuotaWindow?)] = [
        (previous.fiveHourWindow, snapshot.fiveHourWindow),
        (previous.weeklyWindow, snapshot.weeklyWindow),
      ]
      let restored = pairs.compactMap { old, new -> QuotaWindowPeriod? in
        guard let old, let new,
          old.remainingPercentage < 100, new.remainingPercentage == 100
        else { return nil }
        return new.period
      }
      if restored.contains(.weekly) {
        notifyRecovery(.weekly)
      } else if restored.contains(.fiveHour) {
        notifyRecovery(.fiveHour)
      }
    case .loading, .unsupported, .unavailable, .failed:
      break
    }
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    Task { await refreshNotificationAuthorization() }
    refresh()
  }

  func startWhenApplicationFinishesLaunching() {
    guard launchObserver == nil else { return }
    if NSApplication.shared.isRunning {
      startIfNeeded()
      return
    }

    launchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: NSApplication.shared,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.removeLaunchObserver()
        self?.startIfNeeded()
      }
    }
  }


  func refresh() {
    Task {
      await provider.refresh()
    }
  }

  func selectCodexExecutable() {
    let panel = NSOpenPanel()
    panel.title = L10n.text("action.selectCodexCLI")
    panel.message = L10n.text("cliPicker.message")
    panel.prompt = L10n.text("action.choose")
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let executableURL = panel.url else { return }
    Task {
      do {
        try await provider.selectCodexExecutable(at: executableURL)
        actionMessage = nil
      } catch {
        actionMessage = L10n.text("error.invalidExecutable")
      }
    }
  }

  func openCodex() async {
    guard let applicationURL = applicationOpener.installedApplicationURL() else {
      actionMessage = L10n.text("error.codexAppNotFound")
      return
    }

    let didOpen = await applicationOpener.openApplication(at: applicationURL)
    actionMessage = didOpen ? nil : L10n.text("error.codexAppOpenFailed")
  }

  func quit() {
    Task {
      await provider.shutdown()
      NSApplication.shared.terminate(nil)
    }
  }

  func dismissActionMessage() {
    actionMessage = nil
  }

  private func removeLaunchObserver() {
    guard let launchObserver else { return }
    NotificationCenter.default.removeObserver(launchObserver)
    self.launchObserver = nil
  }
}
