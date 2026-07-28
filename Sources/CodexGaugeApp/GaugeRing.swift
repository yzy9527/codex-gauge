import CodexGaugeCore
import SwiftUI

struct GaugeRing: View {
  let remainingPercentage: Double
  let isLoading: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var progress: Double {
    min(max(remainingPercentage / 100, 0), 1)
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(GaugePalette.track, lineWidth: 8)
        .padding(14)

      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          GaugePalette.quotaColor(for: remainingPercentage),
          style: StrokeStyle(lineWidth: 8, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .padding(14)
        .animation(
          reduceMotion ? nil : .snappy(duration: 0.55, extraBounce: 0),
          value: progress
        )

      VStack(spacing: -2) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(Int(remainingPercentage.rounded()))")
            .font(.system(size: 48, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text("%")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(GaugePalette.ink)

        Text(isLoading ? "正在校准" : "剩余额度")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(GaugePalette.secondaryInk)
      }
    }
    .frame(width: 166, height: 166)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("剩余额度 \(Int(remainingPercentage.rounded()))%")
  }
}

struct MenuBarGaugeIcon: View {
  let progress: Double
  let state: QuotaProviderState

  private var percentageText: String {
    guard state.snapshot != nil else { return "--" }
    return "\(Int(progress.rounded()))%"
  }

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: "gauge.with.dots.needle.50percent")
        .font(.system(size: 12, weight: .semibold))

      Text(percentageText)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
    .foregroundStyle(.primary)
  }
}
