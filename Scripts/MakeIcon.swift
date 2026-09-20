#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: MakeIcon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 220, yRadius: 220)
NSColor(red: 0.09, green: 0.12, blue: 0.16, alpha: 1).setFill()
background.fill()

let colors = [
    NSColor(red: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1),
    NSColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255, alpha: 1),
    NSColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255, alpha: 1),
]
let heights: [CGFloat] = [360, 540, 720]
for index in 0..<3 {
    let rect = NSRect(x: 205 + CGFloat(index) * 220, y: 150, width: 150, height: heights[index])
    colors[index].setFill()
    NSBezierPath(roundedRect: rect, xRadius: 75, yRadius: 75).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:])
else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
