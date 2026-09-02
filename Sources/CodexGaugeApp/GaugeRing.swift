import AppKit
import CodexGaugeCore
import SwiftUI

struct GaugeRing: View {
  let remainingPercentage: Double
  let period: QuotaWindowPeriod
  let isLoading: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.locale) private var locale

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

        Text(
          verbatim: isLoading
            ? L10n.text("gauge.calibrating", locale: locale)
            : L10n.remainingQuotaTitle(for: period, locale: locale)
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(GaugePalette.secondaryInk)
      }
    }
    .frame(width: 166, height: 166)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      L10n.remainingQuotaAccessibility(
        Int(remainingPercentage.rounded()),
        period: period,
        locale: locale
      )
    )
  }
}

struct MenuBarGaugeIcon: View {
  let remainingPercentage: Double?
  let state: QuotaProviderState

  private var percentageText: String {
    guard let remainingPercentage else { return "--" }
    return "\(Int(remainingPercentage.rounded()))%"
  }

  private var progress: Double? {
    remainingPercentage.map { min(max($0 / 100, 0), 1) }
  }

  private var showsError: Bool {
    guard remainingPercentage == nil else { return false }

    return switch state {
    case .signedOut, .unsupported, .unavailable, .failed:
      true
    case .idle, .loading, .available:
      false
    }
  }

  var body: some View {
    HStack(spacing: 3) {
      Image(
        nsImage: MenuBarPromptRingImage.make(
          progress: progress,
          showsError: showsError
        )
      )
      .renderingMode(.template)
      .frame(width: 18, height: 18)
      .accessibilityHidden(true)

      Text(percentageText)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
    .foregroundStyle(.primary)
  }
}

enum MenuBarPromptRingImage {
  private static let size = NSSize(width: 18, height: 18)

  static func make(progress: Double?, showsError: Bool) -> NSImage {
    let normalizedProgress = progress.map { min(max($0, 0), 1) }
    let image = NSImage(size: size, flipped: false) { bounds in
      NSGraphicsContext.current?.shouldAntialias = true

      drawTrack(in: bounds, hasProgress: normalizedProgress != nil)

      if let normalizedProgress {
        drawProgress(normalizedProgress, in: bounds)
      }

      if showsError {
        drawErrorMark(in: bounds)
      } else {
        drawPromptMark(in: bounds, hasProgress: normalizedProgress != nil)
      }

      return true
    }
    image.isTemplate = true
    return image
  }

  private static func drawTrack(in bounds: NSRect, hasProgress: Bool) {
    let track = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.35, dy: 1.35))
    track.lineWidth = 1.7
    NSColor.black.withAlphaComponent(hasProgress ? 0.2 : 0.42).setStroke()
    track.stroke()
  }

  private static func drawProgress(_ progress: Double, in bounds: NSRect) {
    guard progress > 0 else { return }

    let arc = NSBezierPath()
    arc.appendArc(
      withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
      radius: min(bounds.width, bounds.height) / 2 - 1.35,
      startAngle: 90,
      endAngle: 90 - CGFloat(progress) * 360,
      clockwise: true
    )
    arc.lineWidth = 1.7
    arc.lineCapStyle = .round
    NSColor.black.setStroke()
    arc.stroke()
  }

  private static func drawPromptMark(in bounds: NSRect, hasProgress: Bool) {
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: bounds.midX - 3.4, y: bounds.midY + 3.5))
    prompt.line(to: NSPoint(x: bounds.midX - 0.5, y: bounds.midY))
    prompt.line(to: NSPoint(x: bounds.midX - 3.4, y: bounds.midY - 3.5))
    prompt.move(to: NSPoint(x: bounds.midX + 0.9, y: bounds.midY - 3.5))
    prompt.line(to: NSPoint(x: bounds.midX + 4.1, y: bounds.midY - 3.5))
    prompt.lineWidth = 1.45
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    NSColor.black.withAlphaComponent(hasProgress ? 1 : 0.72).setStroke()
    prompt.stroke()
  }

  private static func drawErrorMark(in bounds: NSRect) {
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: bounds.midX, y: bounds.midY + 3.8))
    stem.line(to: NSPoint(x: bounds.midX, y: bounds.midY - 1.1))
    stem.lineWidth = 1.65
    stem.lineCapStyle = .round
    NSColor.black.setStroke()
    stem.stroke()

    NSColor.black.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: bounds.midX - 0.8, y: bounds.midY - 4.2, width: 1.6, height: 1.6)
    ).fill()
  }
}
