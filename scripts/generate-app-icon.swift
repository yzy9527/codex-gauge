#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("用法：generate-app-icon.swift <AppIcon.appiconset>\n".utf8))
  exit(2)
}

let outputDirectory = URL(
  fileURLWithPath: CommandLine.arguments[1],
  isDirectory: true
)
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

try FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

for pixelSize in pixelSizes {
  let data = try renderIcon(pixelSize: pixelSize)
  try data.write(
    to: outputDirectory.appendingPathComponent("AppIcon-\(pixelSize).png"),
    options: .atomic
  )
}

func renderIcon(pixelSize: Int) throws -> Data {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw IconGenerationError.bitmapCreationFailed
  }

  bitmap.size = NSSize(width: pixelSize, height: pixelSize)
  guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw IconGenerationError.graphicsContextCreationFailed
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphicsContext
  defer { NSGraphicsContext.restoreGraphicsState() }

  let context = graphicsContext.cgContext
  context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)
  context.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)

  let tile = NSBezierPath(
    roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872),
    xRadius: 194,
    yRadius: 194
  )

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
  shadow.shadowBlurRadius = 46
  shadow.shadowOffset = NSSize(width: 0, height: -18)
  shadow.set()
  NSColor(srgbRed: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 1).setFill()
  tile.fill()
  NSGraphicsContext.restoreGraphicsState()

  let backgroundGradient = NSGradient(
    starting: NSColor(srgbRed: 36 / 255, green: 41 / 255, blue: 51 / 255, alpha: 1),
    ending: NSColor(srgbRed: 13 / 255, green: 15 / 255, blue: 20 / 255, alpha: 1)
  )
  backgroundGradient?.draw(in: tile, angle: -90)

  let ringBounds = NSRect(x: 230, y: 230, width: 564, height: 564)
  let track = NSBezierPath(ovalIn: ringBounds)
  track.lineWidth = 68
  NSColor.white.withAlphaComponent(0.14).setStroke()
  track.stroke()

  let progress = NSBezierPath()
  progress.appendArc(
    withCenter: NSPoint(x: 512, y: 512),
    radius: 282,
    startAngle: 90,
    endAngle: 90 - 0.72 * 360,
    clockwise: true
  )
  progress.lineWidth = 68
  progress.lineCapStyle = .round
  NSColor(srgbRed: 24 / 255, green: 166 / 255, blue: 106 / 255, alpha: 1).setStroke()
  progress.stroke()

  let prompt = NSBezierPath()
  prompt.move(to: NSPoint(x: 406, y: 608))
  prompt.line(to: NSPoint(x: 490, y: 512))
  prompt.line(to: NSPoint(x: 406, y: 416))
  prompt.move(to: NSPoint(x: 544, y: 416))
  prompt.line(to: NSPoint(x: 646, y: 416))
  prompt.lineWidth = 42
  prompt.lineCapStyle = .round
  prompt.lineJoinStyle = .round
  NSColor.white.setStroke()
  prompt.stroke()

  guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw IconGenerationError.pngEncodingFailed
  }
  return pngData
}

enum IconGenerationError: Error {
  case bitmapCreationFailed
  case graphicsContextCreationFailed
  case pngEncodingFailed
}
