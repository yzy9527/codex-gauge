import AppKit
import CodexGaugeCore
import SwiftUI

struct GaugePopoverView: View {
  @ObservedObject var viewModel: GaugeViewModel
  @Environment(\.locale) private var locale
  @State private var isRefreshHovered = false
  @State private var windowReference = PopoverWindowReference()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      header

      if let snapshot = viewModel.snapshot,
        let displaySelection = snapshot.displaySelection
      {
        quotaContent(snapshot: snapshot, displaySelection: displaySelection)
      } else {
        emptyState
      }

      footer
    }
    .frame(width: GaugePalette.panelWidth)
    .background(LinearGradient(colors: [GaugePalette.paper, GaugePalette.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
    .background(PopoverWindowReader(reference: windowReference).frame(width: 0, height: 0))
    .preferredColorScheme(.light)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await viewModel.refreshNotificationAuthorization() }
    }
    .task {
      viewModel.startIfNeeded()
      await viewModel.refreshNotificationAuthorization()
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      HStack(spacing: 9) {
        Image(systemName: "waveform")
          .font(.system(size: 18, weight: .semibold))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text("CODEX–GAUGE")
            .font(.system(size: 12, weight: .bold))
          Text(L10n.text("app.subtitle", locale: locale))
            .font(.system(size: 10))
            .foregroundStyle(GaugePalette.secondaryInk)
        }
      }
      Spacer(minLength: 8)

      HStack(spacing: 4) {
        Text(lastUpdatedDescription)
          .font(.system(size: 10))
          .foregroundStyle(GaugePalette.secondaryInk)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          viewModel.refresh()
        } label: {
          RefreshIcon(isLoading: viewModel.state.isLoading)
            .frame(width: 24, height: 28)
        }
        .buttonStyle(QuietIconButtonStyle(isHovered: isRefreshHovered))
        .focusEffectDisabled()
        .onHover { isRefreshHovered = $0 }
        .disabled(viewModel.state.isLoading)
        .help(L10n.text("action.refreshQuota", locale: locale))
        .accessibilityLabel(L10n.text("action.refreshQuota", locale: locale))
      }

    }
    .foregroundStyle(GaugePalette.ink)
    .padding(.horizontal, 12)
    .padding(.top, 12)
  }

  private func quotaContent(
    snapshot: QuotaSnapshot,
    displaySelection: QuotaDisplaySelection
  ) -> some View {
    let displayWindow = displaySelection.window
    let hasWeekly = displaySelection.period == .fiveHour && snapshot.weeklyWindow != nil
    let creditRows = (snapshot.resetCredits?.displayCredits.count ?? 0)
      + ((snapshot.resetCredits?.unavailableDetailCount ?? 0) > 0 ? 1 : 0)
    let detailsHeight = CGFloat(3 + creditRows + (hasWeekly ? 3 : 0)) * 33
      + (hasWeekly ? 42 : 18)
    // Keep recovery messages and actions visible by shrinking the scrollable details.
    let recoveryHeight: CGFloat = switch viewModel.state {
    case .signedOut, .unsupported, .unavailable, .failed:
      viewModel.canSelectCodexExecutable ? 80 : 48
    case .idle, .loading, .available:
      0
    }
    let maximumDetailsHeight = max(100, min(
      220 - recoveryHeight,
      (NSScreen.main?.visibleFrame.height ?? 800) - 400 - recoveryHeight
    ))

    return VStack(spacing: 0) {
      GaugeRing(
        remainingPercentage: displayWindow.remainingPercentage,
        period: displaySelection.period,
        isLoading: viewModel.state.isLoading
      )
      .padding(.top, 8)
      .padding(.bottom, 8)

      ScrollView {
        VStack(spacing: 0) {
          MetricRow(
            icon: "clock", tint: GaugePalette.blue,
            label: L10n.text("metric.resetTime", locale: locale),
            value: localDateTimeDescription(for: displayWindow.resetDate)
          )
          Divider().overlay(GaugePalette.track)
          MetricRow(
            icon: "calendar", tint: GaugePalette.secondaryInk,
            label: L10n.text("metric.timeUntilReset", locale: locale),
            value: relativeResetDescription(for: displayWindow.resetDate)
          )

          if displaySelection.period == .fiveHour,
            let weeklyWindow = snapshot.weeklyWindow
          {
            Divider()
              .overlay(GaugePalette.track)
              .padding(.vertical, 4)

            weeklyQuotaContent(weeklyWindow)
          }

          Divider()
            .overlay(GaugePalette.track)
            .padding(.vertical, 4)

          resetCreditsContent(snapshot.resetCredits)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(height: min(detailsHeight, maximumDetailsHeight))
      .background(GaugePalette.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: GaugePalette.cardRadius))
      .padding(.horizontal, 10)
      .padding(.bottom, 8)

      statusNotice
    }
  }

  private func weeklyQuotaContent(_ window: QuotaWindow) -> some View {
    VStack(spacing: 0) {
      MetricRow(
        icon: "chart.bar", tint: GaugePalette.secondaryInk,
        label: L10n.text("metric.weeklyQuota", locale: locale),
        value: "\(Int(window.remainingPercentage.rounded()))%",
        valueColor: GaugePalette.quotaColor(for: window.remainingPercentage)
      )

      QuotaProgressBar(remainingPercentage: window.remainingPercentage)
        .padding(.vertical, 5)

      MetricRow(
        icon: "clock", tint: GaugePalette.blue,
        label: L10n.text("metric.resetTime", locale: locale),
        value: localDateTimeDescription(for: window.resetDate)
      )
      MetricRow(
        icon: "calendar", tint: GaugePalette.secondaryInk,
        label: L10n.text("metric.timeUntilReset", locale: locale),
        value: relativeResetDescription(for: window.resetDate)
      )
    }
  }

  @ViewBuilder
  private var statusNotice: some View {
    switch viewModel.state {
    case .idle, .available, .loading:
      EmptyView()
    case .signedOut:
      InlineNotice(text: L10n.text("notice.signedOut", locale: locale))
    case .unsupported(let issue, _),
      .unavailable(let issue, _),
      .failed(let issue, _):
      InlineNotice(text: L10n.issueMessage(issue, locale: locale))
    }
  }

  private var emptyState: some View {
    VStack(spacing: 13) {
      ZStack {
        Circle()
          .stroke(GaugePalette.track, lineWidth: 7)
        Image(systemName: emptyStateIcon)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(GaugePalette.secondaryInk)
      }
      .frame(width: 92, height: 92)

      VStack(spacing: 5) {
        Text(verbatim: L10n.emptyStateTitle(for: viewModel.state, locale: locale))
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(GaugePalette.ink)
        Text(verbatim: L10n.emptyStateMessage(for: viewModel.state, locale: locale))
          .font(.system(size: 12))
          .foregroundStyle(GaugePalette.secondaryInk)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        if viewModel.canSelectCodexExecutable {
          Button(L10n.text("action.selectCodexCLI", locale: locale)) {
            viewModel.selectCodexExecutable()
          }
          .buttonStyle(SecondaryInstrumentButtonStyle())
        }

        Button(L10n.text("action.retry", locale: locale)) {
          viewModel.refresh()
        }
        .buttonStyle(PrimaryInstrumentButtonStyle())
        .disabled(viewModel.state.isLoading)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 30)
    .padding(.vertical, 30)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      if viewModel.canSelectCodexExecutable, viewModel.snapshot != nil {
        Button(L10n.text("action.selectCodexCLI", locale: locale)) {
          viewModel.selectCodexExecutable()
        }
        .buttonStyle(SecondaryInstrumentButtonStyle())
        .padding(.bottom, 8)
      }
      if let actionMessage = viewModel.actionMessage {
        HStack(spacing: 7) {
          Image(systemName: "exclamationmark.circle")
          Text(actionMessage)
          Spacer()
          Button(L10n.text("action.close", locale: locale)) {
            viewModel.dismissActionMessage()
          }
          .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(GaugePalette.red)
        .padding(.horizontal, 12)
        .padding(.top, 10)
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 7) {
          MetricIcon(symbol: "bell", tint: GaugePalette.secondaryInk)
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("recovery.notifications", locale: locale))
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(GaugePalette.ink)
            if viewModel.notificationAuthorization == .denied {
              HStack(spacing: 4) {
                Text(L10n.text("recovery.denied", locale: locale))
                Text("·").accessibilityHidden(true)
                Button {
                  openNotificationSettings()
                } label: {
                  Text(L10n.text("recovery.settings", locale: locale) + " →")
                }
                .buttonStyle(.plain)
                .foregroundStyle(GaugePalette.blue)
                .accessibilityLabel(L10n.text("recovery.settingsAccessibility", locale: locale))
              }
              .font(.system(size: 10))
              .lineLimit(1)
            } else if viewModel.notificationAuthorization == .unavailable {
              Text(L10n.text("recovery.unavailable", locale: locale))
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            } else {
              Text(L10n.text("recovery.subtitle", locale: locale))
                .font(.system(size: 10))
            }
          }
          Spacer(minLength: 4)
          Toggle(L10n.text("recovery.notifications", locale: locale), isOn: Binding(
            get: { viewModel.recoveryNotificationsActive },
            set: { enabled in
              Task {
                await viewModel.refreshNotificationAuthorization()
                if enabled && viewModel.notificationAuthorization == .denied {
                  openNotificationSettings()
                  return
                }
                await viewModel.setRecoveryNotificationsEnabled(enabled) {
                  // Hide our window before macOS presents its authorization UI.
                  windowReference.window?.orderOut(nil)
                  dismiss()
                }
              }
            }
          ))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .tint(GaugePalette.blue)
          .disabled(viewModel.isChangingNotificationPermission)
        }

        if let error = viewModel.notificationError {
          Text(error)
            .foregroundStyle(GaugePalette.red)
            .padding(.leading, 32)
        }
      }
      .font(.system(size: 11))
      .foregroundStyle(GaugePalette.secondaryInk)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(GaugePalette.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: GaugePalette.cardRadius))
      .overlay(RoundedRectangle(cornerRadius: GaugePalette.cardRadius).stroke(GaugePalette.track.opacity(0.7)))
      .padding(.horizontal, 10)

      HStack {
        Button {
          Task { await viewModel.openCodex() }
        } label: {
          Label(L10n.text("action.openCodex", locale: locale), systemImage: "arrow.up.forward.square")
            .frame(width: 155, height: 31)
            .background(GaugePalette.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(GaugePalette.blue)

        Spacer()

        Button(L10n.text("action.quit", locale: locale)) {
          viewModel.quit()
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(GaugePalette.red)
        .keyboardShortcut("q", modifiers: .command)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
  }

  private func openNotificationSettings() {
    windowReference.window?.orderOut(nil)
    dismiss()
    viewModel.openNotificationSettings()
  }

  private var emptyStateIcon: String {
    switch viewModel.state {
    case .loading:
      "arrow.trianglehead.2.clockwise.rotate.90"
    case .signedOut:
      "person.crop.circle.badge.exclamationmark"
    case .unsupported:
      "terminal"
    case .unavailable, .failed:
      "exclamationmark"
    case .idle, .available:
      "gauge.open.with.lines.needle.33percent"
    }
  }

  private var lastUpdatedDescription: String {
    if viewModel.state.isLoading {
      return viewModel.snapshot == nil
        ? L10n.text("status.connecting", locale: locale)
        : L10n.text("status.updating", locale: locale)
    }
    guard let date = viewModel.snapshot?.lastUpdated else {
      return L10n.text("status.neverUpdated", locale: locale)
    }
    let relativeDescription = date.formatted(
      .relative(presentation: .named, unitsStyle: .wide).locale(locale)
    )
    return L10n.updatedAt(relativeDescription, locale: locale)
  }

  @ViewBuilder
  private func resetCreditsContent(_ summary: QuotaResetCredits?) -> some View {
    if let summary {
      MetricRow(
        icon: "cylinder", tint: GaugePalette.secondaryInk,
        label: L10n.text("metric.availableResets", locale: locale),
        value: L10n.availableResetCount(summary.availableCount, locale: locale)
      )

      ForEach(Array(summary.displayCredits.enumerated()), id: \.offset) { index, credit in
        MetricRow(
          icon: "hourglass", tint: GaugePalette.secondaryInk,
          label: L10n.resetExpirationLabel(index: index + 1, locale: locale),
          value: expirationDescription(for: credit.expirationDate)
        )
      }

      if summary.unavailableDetailCount > 0 {
        MetricRow(
          icon: "hourglass", tint: GaugePalette.secondaryInk,
          label: L10n.additionalResetCount(summary.unavailableDetailCount, locale: locale),
          value: L10n.text("reset.expirationUnavailable", locale: locale),
          valueColor: GaugePalette.secondaryInk
        )
      }
    } else {
      MetricRow(
        icon: "cylinder", tint: GaugePalette.secondaryInk,
        label: L10n.text("metric.availableResets", locale: locale),
        value: L10n.text("status.unavailable", locale: locale),
        valueColor: GaugePalette.secondaryInk
      )
    }
  }

  private func localDateTimeDescription(for date: Date) -> String {
    date.formatted(
      Date.FormatStyle(
        locale: locale,
        timeZone: .autoupdatingCurrent
      )
      .month()
      .day()
      .hour()
      .minute()
    )
  }

  private func expirationDescription(for date: Date?) -> String {
    guard let date else {
      return L10n.text("reset.neverExpires", locale: locale)
    }
    return localDateTimeDescription(for: date)
  }

  private func relativeResetDescription(for date: Date) -> String {
    let interval = max(date.timeIntervalSinceNow, 0)
    let hours = Int(interval / 3_600)
    if hours >= 24 {
      return L10n.daysUntilReset(max(hours / 24, 1), locale: locale)
    }
    if hours >= 1 {
      return L10n.hoursUntilReset(hours, locale: locale)
    }
    return L10n.text("reset.lessThanOneHour", locale: locale)
  }
}

private struct MetricIcon: View {
  let symbol: String
  let tint: Color

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(tint)
      .frame(width: 25, height: 25)
      .accessibilityHidden(true)
  }
}

private struct MetricRow: View {
  let icon: String
  let tint: Color
  let label: String
  let value: String
  var valueColor: Color = GaugePalette.ink

  var body: some View {
    HStack(spacing: 7) {
      MetricIcon(symbol: icon, tint: tint)
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(GaugePalette.secondaryInk)
      Spacer(minLength: 6)
      Text(value)
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(valueColor)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(minHeight: 33)
  }
}

private struct QuotaProgressBar: View {
  let remainingPercentage: Double

  private var progress: Double {
    min(max(remainingPercentage / 100, 0), 1)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(GaugePalette.track)
        Capsule()
          .fill(GaugePalette.quotaColor(for: remainingPercentage))
          .frame(width: geometry.size.width * progress)
      }
    }
    .frame(height: 5)
    .accessibilityHidden(true)
  }
}

private struct InlineNotice: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(GaugePalette.orange)
      Text(text)
        .foregroundStyle(GaugePalette.ink)
      Spacer(minLength: 0)
    }
    .font(.system(size: 11.5))
    .padding(11)
    .background(GaugePalette.orange.opacity(0.09))
    .padding(.horizontal, 12)
    .padding(.bottom, 16)
  }
}

private struct RefreshIcon: View {
  let isLoading: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var rotationStartedAt = Date()

  var body: some View {
    TimelineView(.animation(paused: !isLoading || reduceMotion)) { context in
      let elapsed = max(0, context.date.timeIntervalSince(rotationStartedAt))
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 11, weight: .semibold))
        .rotationEffect(.degrees(
          isLoading && !reduceMotion
            ? elapsed.truncatingRemainder(dividingBy: 1) * 360
            : 0
        ))
    }
    .onChange(of: isLoading, initial: true) { _, loading in
      if loading {
        rotationStartedAt = Date()
      }
    }
  }
}

private struct QuietIconButtonStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isHovered ? GaugePalette.ink : GaugePalette.secondaryInk)
      .background(
        Circle()
          .fill(
            configuration.isPressed
              ? GaugePalette.track
              : GaugePalette.track.opacity(isHovered ? 0.55 : 0)
          )
      )
      .contentShape(Circle())
  }
}

private struct PrimaryInstrumentButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(GaugePalette.paper)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Capsule()
          .fill(configuration.isPressed ? GaugePalette.ink.opacity(0.8) : GaugePalette.ink)
      )
  }
}

private struct SecondaryInstrumentButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(GaugePalette.ink)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Capsule()
          .fill(configuration.isPressed ? GaugePalette.track : GaugePalette.paper)
      )
      .overlay(
        Capsule()
          .stroke(GaugePalette.track, lineWidth: 1)
      )
  }
}

// Capture only this popover's host, never another application window.
@MainActor
private final class PopoverWindowReference {
  weak var window: NSWindow?
}

private struct PopoverWindowReader: NSViewRepresentable {
  let reference: PopoverWindowReference

  func makeNSView(context: Context) -> WindowReaderView {
    WindowReaderView(reference: reference)
  }

  func updateNSView(_ nsView: WindowReaderView, context: Context) {}

  final class WindowReaderView: NSView {
    let reference: PopoverWindowReference

    init(reference: PopoverWindowReference) {
      self.reference = reference
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      reference.window = window
    }
  }
}
