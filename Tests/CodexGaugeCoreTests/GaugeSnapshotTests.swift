import AppKit
import CodexGaugeCore
import SwiftUI
import XCTest

#if SWIFT_PACKAGE
  @testable import CodexGaugeApp
#endif

final class GaugeSnapshotTests: XCTestCase {
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
        state: .failed(message: "test failure", previous: nil)
      ),
      MenuBarGaugeIcon(
        remainingPercentage: snapshot.displayWindow?.remainingPercentage,
        state: .failed(message: "test failure", previous: snapshot)
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
      content: view
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
