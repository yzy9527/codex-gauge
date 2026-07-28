import AppKit
import CodexGaugeCore
import SwiftUI
import XCTest

#if SWIFT_PACKAGE
  @testable import CodexGaugeApp
#endif

final class GaugeSnapshotTests: XCTestCase {
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

    let outputURL = URL(fileURLWithPath: "/tmp/codex-gauge-preview.png")
    let representation = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: representation))
    let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try pngData.write(to: outputURL, options: .atomic)
  }
}
