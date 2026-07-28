import AppKit
import CodexGaugeCore
import SwiftUI
import XCTest

#if SWIFT_PACKAGE
  @testable import CodexGaugeApp
#endif

final class GaugeSnapshotTests: XCTestCase {
  func testLocalizesStaticAndDynamicStringsInEnglishAndSimplifiedChinese() {
    let english = Locale(identifier: "en")
    let chinese = Locale(identifier: "zh-Hans")

    XCTAssertEqual(L10n.text("action.retry", locale: english), "Try Again")
    XCTAssertEqual(L10n.text("action.retry", locale: chinese), "重新读取")
    XCTAssertEqual(
      L10n.localizationIdentifier(for: Locale(identifier: "zh-Hant")).lowercased(),
      "zh-hans"
    )
    XCTAssertEqual(
      L10n.text("action.retry", locale: Locale(identifier: "zh-Hant")),
      "重新读取"
    )
    XCTAssertEqual(
      L10n.text("action.retry", locale: Locale(identifier: "fr")),
      "Try Again"
    )
    XCTAssertEqual(L10n.availableResetCount(1, locale: Locale(identifier: "fr")), "1 reset")
    XCTAssertEqual(L10n.availableResetCount(1, locale: english), "1 reset")
    XCTAssertEqual(L10n.availableResetCount(2, locale: english), "2 resets")
    XCTAssertEqual(L10n.availableResetCount(2, locale: chinese), "2 次")
    XCTAssertEqual(L10n.hoursUntilReset(1, locale: english), "1 hour remaining")
    XCTAssertEqual(L10n.hoursUntilReset(2, locale: english), "2 hours remaining")
    XCTAssertEqual(L10n.hoursUntilReset(2, locale: chinese), "还有 2 小时")
  }

  @MainActor
  func testExecutableSelectionUsesSemanticIssueInsteadOfLocalizedText() {
    let selectable = GaugeViewModel(
      provider: MockQuotaProvider(
        initialState: .unsupported(issue: .executableNotFound, previous: nil)
      )
    )
    let unsupportedVersion = GaugeViewModel(
      provider: MockQuotaProvider(
        initialState: .unsupported(issue: .methodUnavailable, previous: nil)
      )
    )

    XCTAssertTrue(selectable.canSelectCodexExecutable)
    XCTAssertFalse(unsupportedVersion.canSelectCodexExecutable)
  }

  @MainActor
  func testOpenCodexReportsWhenApplicationIsNotInstalled() async {
    let opener = StubCodexApplicationOpener(applicationURL: nil)
    let viewModel = GaugeViewModel(
      provider: MockQuotaProvider(),
      applicationOpener: opener
    )

    await viewModel.openCodex()

    XCTAssertEqual(viewModel.actionMessage, L10n.text("error.codexAppNotFound"))
    XCTAssertTrue(opener.openedURLs.isEmpty)
  }

  @MainActor
  func testOpenCodexMapsLaunchFailureAndSuccessToActionMessage() async {
    let applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
    let opener = StubCodexApplicationOpener(
      applicationURL: applicationURL,
      shouldOpen: false
    )
    let viewModel = GaugeViewModel(
      provider: MockQuotaProvider(),
      applicationOpener: opener
    )

    await viewModel.openCodex()

    XCTAssertEqual(viewModel.actionMessage, L10n.text("error.codexAppOpenFailed"))
    XCTAssertEqual(opener.openedURLs, [applicationURL])

    opener.shouldOpen = true
    await viewModel.openCodex()

    XCTAssertNil(viewModel.actionMessage)
    XCTAssertEqual(opener.openedURLs, [applicationURL, applicationURL])
  }

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
        state: .failed(issue: .unknown, previous: nil)
      ),
      MenuBarGaugeIcon(
        remainingPercentage: snapshot.displayWindow?.remainingPercentage,
        state: .failed(issue: .unknown, previous: snapshot)
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

    for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
      let localizedRenderer = ImageRenderer(
        content: GaugePopoverView(viewModel: viewModel)
          .environment(\.locale, locale)
      )
      localizedRenderer.scale = 2
      let localizedImage = try XCTUnwrap(localizedRenderer.nsImage)
      XCTAssertEqual(localizedImage.size.width, 326, accuracy: 0.5)
      XCTAssertGreaterThan(localizedImage.size.height, 360)

      if ProcessInfo.processInfo.environment["CODEX_GAUGE_RENDER_PREVIEW"] == "1" {
        try writePNG(
          localizedImage,
          to: URL(
            fileURLWithPath: "/tmp/codex-gauge-preview-\(locale.identifier).png"
          )
        )
      }
    }

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
      content:
        view
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

@MainActor
private final class StubCodexApplicationOpener: CodexApplicationOpening {
  let applicationURL: URL?
  var shouldOpen: Bool
  private(set) var openedURLs: [URL] = []

  init(applicationURL: URL?, shouldOpen: Bool = true) {
    self.applicationURL = applicationURL
    self.shouldOpen = shouldOpen
  }

  func installedApplicationURL() -> URL? {
    applicationURL
  }

  func openApplication(at url: URL) async -> Bool {
    openedURLs.append(url)
    return shouldOpen
  }
}
