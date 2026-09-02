import AppKit
import CodexGaugeCore
import SwiftUI

@main
struct CodexGaugeApp: App {
  @StateObject private var viewModel: GaugeViewModel

  @MainActor
  init() {
    let provider = CodexQuotaProvider()
    let viewModel = GaugeViewModel(provider: provider)
    _viewModel = StateObject(
      wrappedValue: viewModel
    )
    viewModel.startWhenApplicationFinishesLaunching()
  }

  var body: some Scene {
    MenuBarExtra {
      GaugePopoverView(viewModel: viewModel)
    } label: {
      MenuBarGaugeIcon(
        remainingPercentage: viewModel.displaySelection?.window.remainingPercentage,
        state: viewModel.state
      )
      .accessibilityLabel(viewModel.menuBarAccessibilityLabel)
    }
    .menuBarExtraStyle(.window)
  }
}
