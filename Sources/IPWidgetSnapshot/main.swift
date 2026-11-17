import AppKit
import Foundation
import IPWidgetCore
import IPWidgetUI
import SwiftUI
import WidgetKit

private enum SnapshotError: Error {
    case renderFailed
}

@MainActor
private func render(
    status: WidgetStatus,
    scheme: ColorScheme,
    renderingMode: WidgetRenderingMode = .fullColor,
    to url: URL
) throws {
    let wallpaper: [Color] = scheme == .dark
        ? [
            Color(red: 0.09, green: 0.13, blue: 0.21),
            Color(red: 0.24, green: 0.17, blue: 0.28),
        ]
        : [
            Color(red: 0.76, green: 0.85, blue: 0.96),
            Color(red: 0.95, green: 0.85, blue: 0.80),
        ]

    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    let content = ZStack {
        LinearGradient(colors: wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)

        WidgetCard(
            status: status,
            interfaceName: nil,
            lastUpdated: fixedDate,
            locale: Locale(identifier: "ru_RU")
        )
        .frame(width: 164, height: 164)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                if case .unavailable = status {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 9)
    }
    .frame(width: 220, height: 220)
    .environment(\.colorScheme, scheme)
    .environment(\.widgetRenderingMode, renderingMode)
    .environment(\.locale, Locale(identifier: "ru_RU"))

    let renderer = ImageRenderer(content: content)
    renderer.scale = 3
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw SnapshotError.renderFailed
    }
    try png.write(to: url)
}

@MainActor
private func renderSnapshots(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let ip = IPv4Address(rawValue: 0x2D9F_0C07) // 45.159.12.7
    let geo = GeoInfo(ip: ip, countryCode: "SE", countryName: "Sweden")

    try render(status: .online(geo), scheme: .dark, to: directory.appendingPathComponent("online-dark.png"))
    try render(status: .online(geo), scheme: .light, to: directory.appendingPathComponent("online-light.png"))
    try render(
        status: .online(geo),
        scheme: .light,
        renderingMode: .accented,
        to: directory.appendingPathComponent("online-muted-light.png")
    )
    try render(status: .unavailable(.noConnection), scheme: .light, to: directory.appendingPathComponent("offline-light.png"))
    try render(status: .loading, scheme: .dark, to: directory.appendingPathComponent("loading-dark.png"))

    print("Snapshots written to \(directory.path)")
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/snapshots",
    isDirectory: true
)
try await MainActor.run {
    try renderSnapshots(to: outputDirectory)
}
