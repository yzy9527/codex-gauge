import AppKit
import CodexGaugeCore
import SwiftUI

struct GaugePopoverView: View {
  @ObservedObject var viewModel: GaugeViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
      .onHover { isRefreshHovered = $0 }
      .disabled(viewModel.state.isLoading)
      .help("刷新额度")
      .accessibilityLabel("刷新额度")
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
          label: "重置时间",
          value: localDateTimeDescription(for: displayWindow.resetDate)
        )
        MetricRow(
          label: "距离重置",
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
      InlineNotice(text: "请先在 Codex 中登录，然后重试。")
    case .unsupported(let message, _),
      .unavailable(let message, _),
      .failed(let message, _):
      InlineNotice(text: message)
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
        Text(emptyStateTitle)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(GaugePalette.ink)
        Text(emptyStateMessage)
          .font(.system(size: 12))
          .foregroundStyle(GaugePalette.secondaryInk)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button("重新读取") {
        viewModel.refresh()
      }
      .buttonStyle(PrimaryInstrumentButtonStyle())
      .disabled(viewModel.state.isLoading)
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
          Button("关闭") {
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
        Text(lastUpdatedDescription)
          .font(.system(size: 10.5, weight: .regular, design: .monospaced))
          .foregroundStyle(GaugePalette.secondaryInk)

        Spacer()

        Button("打开 Codex") {
          viewModel.openCodex()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(GaugePalette.ink)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 15)
    }
  }

  private var emptyStateTitle: String {
    switch viewModel.state {
    case .loading:
      "正在读取额度"
    case .signedOut:
      "Codex 尚未登录"
    case .unsupported:
      "当前环境不支持"
    case .unavailable:
      "暂时没有额度数据"
    case .failed:
      "读取额度失败"
    case .idle, .available:
      "额度尚未读取"
    }
  }

  private var emptyStateMessage: String {
    switch viewModel.state {
    case .loading:
      "正在与本机 Codex 建立连接。"
    case .signedOut:
      "请在 Codex 中完成登录后重新读取。"
    case .unsupported(let message, _),
      .unavailable(let message, _),
      .failed(let message, _):
      message
    case .idle, .available:
      "点击重新读取获取当前额度。"
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
    guard let date = viewModel.snapshot?.lastUpdated else {
      return "尚未更新"
    }
    return "更新于 "
      + date.formatted(
        .relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "zh_CN")))
  }

  @ViewBuilder
  private func resetCreditsContent(_ summary: QuotaResetCredits?) -> some View {
    if let summary {
      MetricRow(
        label: "可用重置",
        value: "\(summary.availableCount) 次"
      )

      ForEach(Array(summary.displayCredits.enumerated()), id: \.offset) { index, credit in
        MetricRow(
          label: "第 \(index + 1) 次到期",
          value: expirationDescription(for: credit.expirationDate)
        )
      }

      if summary.unavailableDetailCount > 0 {
        MetricRow(
          label: "另有 \(summary.unavailableDetailCount) 次",
          value: "到期时间暂不可用",
          valueColor: GaugePalette.secondaryInk
        )
      }
    } else {
      MetricRow(
        label: "可用重置",
        value: "暂不可用",
        valueColor: GaugePalette.secondaryInk
      )
    }
  }

  private func localDateTimeDescription(for date: Date) -> String {
    date.formatted(
      Date.FormatStyle(
        locale: Locale(identifier: "zh_CN"),
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
      return "长期有效"
    }
    return localDateTimeDescription(for: date)
  }

  private func relativeResetDescription(for date: Date) -> String {
    let interval = max(date.timeIntervalSinceNow, 0)
    let hours = Int(interval / 3_600)
    if hours >= 24 {
      return "还有 \(max(hours / 24, 1)) 天"
    }
    if hours >= 1 {
      return "还有 \(hours) 小时"
    }
    return "不到 1 小时"
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
