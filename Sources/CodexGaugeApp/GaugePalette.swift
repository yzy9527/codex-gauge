import SwiftUI

enum GaugePalette {
  static let paper = Color(red: 1, green: 1, blue: 1)
  static let ink = Color(red: 17 / 255, green: 19 / 255, blue: 24 / 255)
  static let secondaryInk = Color(red: 112 / 255, green: 117 / 255, blue: 125 / 255)
  static let track = Color(red: 232 / 255, green: 235 / 255, blue: 239 / 255)
  static let green = Color(red: 24 / 255, green: 166 / 255, blue: 106 / 255)
  static let orange = Color(red: 231 / 255, green: 154 / 255, blue: 24 / 255)
  static let red = Color(red: 223 / 255, green: 76 / 255, blue: 76 / 255)

  static func quotaColor(for remainingPercentage: Double) -> Color {
    switch remainingPercentage {
    case 50...:
      green
    case 20..<50:
      orange
    default:
      red
    }
  }
}
