import CodexGaugeCore
import Foundation
import UserNotifications

enum RecoveryNotificationAuthorization: Equatable, Sendable {
  case notDetermined, authorized, denied, unavailable
}

@MainActor
protocol RecoveryNotifying: AnyObject {
  var onOpen: (() -> Void)? { get set }
  func authorization() async -> RecoveryNotificationAuthorization
  func requestAuthorization() async throws -> Bool
  func send(period: QuotaWindowPeriod) async throws
  func removePending()
}

@MainActor
final class SystemRecoveryNotifier: NSObject, RecoveryNotifying, UNUserNotificationCenterDelegate {
  var onOpen: (() -> Void)?
  private let identifier = "quota-recovery"

  override init() {
    super.init()
    _ = center
  }

  // A bare SwiftPM executable has no notification application identity.
  private var center: UNUserNotificationCenter? {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    return center
  }

  func authorization() async -> RecoveryNotificationAuthorization {
    guard let center else { return .unavailable }
    return await withCheckedContinuation { continuation in
      // The SDK invokes this callback on its own queue. Do not inherit MainActor.
      center.getNotificationSettings { @Sendable settings in
        let authorization: RecoveryNotificationAuthorization
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorization = .authorized
        case .denied: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .unavailable
        }
        continuation.resume(returning: authorization)
      }
    }
  }

  func requestAuthorization() async throws -> Bool {
    guard let center else { return false }
    return try await withCheckedThrowingContinuation { continuation in
      center.requestAuthorization(
        options: [.alert, .sound], completionHandler: Self.permissionCompletion(continuation)
      )
    }
  }

  static func content(for period: QuotaWindowPeriod) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = L10n.text(period == .weekly ? "recovery.weekly" : "recovery.fiveHour")
    content.body = L10n.text("recovery.body")
    content.sound = UNNotificationSound.default
    return content
  }

  func send(period: QuotaWindowPeriod) async throws {
    guard let center else { return }
    try Task.checkCancellation()
    let request = UNNotificationRequest(
      identifier: identifier, content: Self.content(for: period), trigger: nil
    )
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      center.add(request, withCompletionHandler: Self.deliveryCompletion(continuation))
    }
    if Task.isCancelled { removePending() }
  }

  // Explicitly nonisolated and Sendable: system callbacks can run off the main queue.
  nonisolated static func permissionCompletion(
    _ continuation: CheckedContinuation<Bool, Error>
  ) -> @Sendable (Bool, Error?) -> Void {
    { granted, error in
      if let error { continuation.resume(throwing: error) }
      else { continuation.resume(returning: granted) }
    }
  }

  nonisolated static func deliveryCompletion(
    _ continuation: CheckedContinuation<Void, Error>
  ) -> @Sendable (Error?) -> Void {
    { error in
      if let error { continuation.resume(throwing: error) }
      else { continuation.resume() }
    }
  }

  func removePending() {
    center?.removePendingNotificationRequests(withIdentifiers: [identifier])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      Task { @MainActor [weak self] in self?.onOpen?() }
    }
    completionHandler()
  }
}
