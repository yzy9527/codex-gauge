import AppKit
import SwiftUI

@MainActor
final class QuotaPanelController {
  private var quotaPanel: NSPanel?

  func show(viewModel: GaugeViewModel) {
    if quotaPanel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: GaugePalette.panelWidth, height: 520),
        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false
      )
      panel.title = "Codex Gauge"
      panel.isReleasedWhenClosed = false
      let content = NSHostingView(rootView: GaugePopoverView(viewModel: viewModel))
      panel.contentView = content
      panel.setContentSize(content.fittingSize)
      panel.center()
      quotaPanel = panel
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
    quotaPanel?.makeKeyAndOrderFront(nil)
  }

}
