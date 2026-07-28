import AppKit
import CodexGaugeCore
import SwiftUI

struct GaugePopoverView: View {
  @ObservedObject var viewModel: GaugeViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.locale) private var locale
  @State private var isRefreshHovered = false

  var body: some View {
    VStack(spacing: 0) {
      header

      if let snapshot = viewModel.snapshot,
        let displayWindow = snapshot.displayWindow
      {
        quotaContent(snapshot: snapshot, displayWindow: displayWindow)
      } else {
        emptyState
      }

      footer
    }
    .frame(width: 326)
    .background(GaugePalette.paper)
    .preferredColorScheme(.light)
    .task {
      viewModel.startIfNeeded()
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      HStack(spacing: 7) {
        Text("CODEX")
          .font(.system(size: 11, weight: .bold, design: .monospaced))
        Rectangle()
          .fill(GaugePalette.track)
          .frame(width: 18, height: 1)
        Text("GAUGE")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(GaugePalette.secondaryInk)
      }

      Spacer()

      Text(lastUpdatedDescription)
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
        .foregroundStyle(GaugePalette.secondaryInk)
        .lineLimit(1)

      Button {
        viewModel.refresh()
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
          .rotationEffect(.degrees(viewModel.state.isLoading ? 180 : 0))
          .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.35),
            value: viewModel.state.isLoading
          )
      }
      .buttonStyle(QuietIconButtonStyle(isHovered: isRefreshHovered))
      .focusEffectDisabled()
      .onHover { isRefreshHovered = $0 }
      .disabled(viewModel.state.isLoading)
      .help(L10n.text("action.refreshQuota", locale: locale))
      .accessibilityLabel(L10n.text("action.refreshQuota", locale: locale))
    }
    .foregroundStyle(GaugePalette.ink)
    .padding(.horizontal, 20)
    .padding(.top, 17)
  }

  private func quotaContent(
    snapshot: QuotaSnapshot,
    displayWindow: QuotaWindow
  ) -> some View {
    VStack(spacing: 0) {
      GaugeRing(
        remainingPercentage: displayWindow.remainingPercentage,
        isLoading: viewModel.state.isLoading
      )
      .padding(.top, 11)
      .padding(.bottom, 13)

      VStack(spacing: 0) {
        MetricRow(
          label: L10n.text("metric.resetTime", locale: locale),
          value: localDateTimeDescription(for: displayWindow.resetDate)
        )
        MetricRow(
          label: L10n.text("metric.timeUntilReset", locale: locale),
          value: relativeResetDescription(for: displayWindow.resetDate)
        )

        Divider()
          .overlay(GaugePalette.track)
          .padding(.vertical, 4)

        resetCreditsContent(snapshot.resetCredits)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 16)

      statusNotice
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
      Divider()
        .overlay(GaugePalette.track)

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
        .padding(.horizontal, 20)
        .padding(.top, 10)
      }

      HStack {
        Button(L10n.text("action.openCodex", locale: locale)) {
          viewModel.openCodex()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(GaugePalette.ink)

        Spacer()

        Button(L10n.text("action.quit", locale: locale)) {
          viewModel.quit()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(GaugePalette.secondaryInk)
        .keyboardShortcut("q", modifiers: .command)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 15)
    }
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
        label: L10n.text("metric.availableResets", locale: locale),
        value: L10n.availableResetCount(summary.availableCount, locale: locale)
      )

      ForEach(Array(summary.displayCredits.enumerated()), id: \.offset) { index, credit in
        MetricRow(
          label: L10n.resetExpirationLabel(index: index + 1, locale: locale),
          value: expirationDescription(for: credit.expirationDate)
        )
      }

      if summary.unavailableDetailCount > 0 {
        MetricRow(
          label: L10n.additionalResetCount(summary.unavailableDetailCount, locale: locale),
          value: L10n.text("reset.expirationUnavailable", locale: locale),
          valueColor: GaugePalette.secondaryInk
        )
      }
    } else {
      MetricRow(
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

private struct MetricRow: View {
  let label: String
  let value: String
  var valueColor: Color = GaugePalette.ink

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(GaugePalette.secondaryInk)
      Spacer()
      Text(value)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(valueColor)
    }
    .frame(minHeight: 30)
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
    .padding(.horizontal, 20)
    .padding(.bottom, 16)
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
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(GaugePalette.paper)
      .padding(.horizontal, 14)
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
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(GaugePalette.ink)
      .padding(.horizontal, 14)
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
