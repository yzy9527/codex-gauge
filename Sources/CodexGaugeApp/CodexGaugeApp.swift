import AppKit
import CodexGaugeCore
import SwiftUI

@main
struct CodexGaugeApp: App {
  @StateObject private var viewModel: GaugeViewModel

  init() {
    let provider = CodexQuotaProvider()
    _viewModel = StateObject(
      wrappedValue: GaugeViewModel(provider: provider)
    )
  }

  var body: some Scene {
    MenuBarExtra {
      GaugePopoverView(viewModel: viewModel)
    } label: {
      MenuBarGaugeIcon(
        progress: viewModel.displayWindow?.remainingPercentage ?? 0,
        state: viewModel.state
      )
      .accessibilityLabel(viewModel.menuBarAccessibilityLabel)
    }
    .menuBarExtraStyle(.window)
  }
}
