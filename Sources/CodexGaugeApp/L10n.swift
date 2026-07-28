import CodexGaugeCore
import Foundation

private final class L10nBundleToken: NSObject {}

enum L10n {
  private static var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
      Bundle.module
    #else
      Bundle(for: L10nBundleToken.self)
    #endif
  }

  static func localizationIdentifier(for locale: Locale) -> String {
    let availableLocalizations = resourceBundle.localizations
    let preferredLocalization = Bundle.preferredLocalizations(
      from: availableLocalizations,
      forPreferences: [locale.identifier]
    ).first

    if locale.identifier.lowercased().hasPrefix("zh"),
      let simplifiedChinese = availableLocalizations.first(where: {
        $0.lowercased() == "zh-hans"
      })
    {
      return simplifiedChinese
    }
    return preferredLocalization ?? "en"
  }

  static func text(
    _ key: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    bundle(for: locale).localizedString(
      forKey: key,
      value: nil,
      table: nil
    )
  }

  static func emptyStateTitle(
    for state: QuotaProviderState,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let key =
      switch state {
      case .loading: "empty.loading.title"
      case .signedOut: "empty.signedOut.title"
      case .unsupported: "empty.unsupported.title"
      case .unavailable: "empty.unavailable.title"
      case .failed: "empty.failed.title"
      case .idle, .available: "empty.idle.title"
      }
    return text(key, locale: locale)
  }

  static func emptyStateMessage(
    for state: QuotaProviderState,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let key: String
    switch state {
    case .loading:
      key = "empty.loading.message"
    case .signedOut:
      key = "empty.signedOut.message"
    case .unsupported(let issue, _),
      .unavailable(let issue, _),
      .failed(let issue, _):
      key = issue.localizationKey
    case .idle, .available:
      key = "empty.idle.message"
    }
    return text(key, locale: locale)
  }

  static func issueMessage(
    _ issue: QuotaProviderIssue,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    text(issue.localizationKey, locale: locale)
  }

  private static func localized(
    _ key: StaticString,
    defaultValue: String.LocalizationValue,
    locale: Locale
  ) -> String {
    String(
      localized: key,
      defaultValue: defaultValue,
      bundle: bundle(for: locale),
      locale: localizationLocale(for: locale)
    )
  }

  static func updatedAt(
    _ relativeDescription: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "status.updatedAt",
      defaultValue: "Updated \(relativeDescription)",
      locale: locale
    )
  }

  static func availableResetCount(
    _ count: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized("reset.availableCount", defaultValue: "\(count) resets", locale: locale)
  }

  static func resetExpirationLabel(
    index: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "reset.expirationLabel",
      defaultValue: "Reset \(index) expires",
      locale: locale
    )
  }

  static func additionalResetCount(
    _ count: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized("reset.additionalCount", defaultValue: "\(count) more", locale: locale)
  }

  static func daysUntilReset(
    _ count: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "reset.daysRemaining",
      defaultValue: "\(count) days remaining",
      locale: locale
    )
  }

  static func hoursUntilReset(
    _ count: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "reset.hoursRemaining",
      defaultValue: "\(count) hours remaining",
      locale: locale
    )
  }

  static func remainingQuotaAccessibility(
    _ percentage: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "accessibility.remainingQuota",
      defaultValue: "Remaining quota: \(percentage)%",
      locale: locale
    )
  }

  static func menuBarRemaining(
    _ percentage: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    localized(
      "accessibility.menuBarRemaining",
      defaultValue: "Codex Gauge, \(percentage)% remaining",
      locale: locale
    )
  }

  private static func bundle(for locale: Locale) -> Bundle {
    let localization = localizationIdentifier(for: locale)
    guard
      let path = resourceBundle.path(forResource: localization, ofType: "lproj"),
      let localizedBundle = Bundle(path: path)
    else {
      return resourceBundle
    }
    return localizedBundle
  }

  private static func localizationLocale(for locale: Locale) -> Locale {
    Locale(identifier: localizationIdentifier(for: locale))
  }
}

extension QuotaProviderIssue {
  fileprivate var localizationKey: String {
    switch self {
    case .executableNotFound: "error.executableNotFound"
    case .methodUnavailable: "error.methodUnavailable"
    case .quotaUnavailable: "error.quotaUnavailable"
    case .timeout: "error.timeout"
    case .launchFailed: "error.launchFailed"
    case .connectionInterrupted: "error.connectionInterrupted"
    case .incompatibleResponse: "error.incompatibleResponse"
    case .remoteFailure: "error.remoteFailure"
    case .unknown: "error.unknown"
    }
  }
}
