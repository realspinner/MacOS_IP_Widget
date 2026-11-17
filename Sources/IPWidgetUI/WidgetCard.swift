import AppKit
import SwiftUI
import os
#if canImport(IPWidgetCore)
import IPWidgetCore
#endif

/// Size-independent widget content. The real WidgetKit widget gives it the
/// standard 164×164 small-widget area; the snapshot tool renders the same view
/// at other sizes. Everything scales from the smaller side, so it always looks
/// like a standard macOS widget instead of a shrunken full-screen card.
public struct WidgetCard: View {
    private static let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "widget")

    private let rating: IPRating?
    private let status: WidgetStatus
    private let interfaceName: String?
    private let lastUpdated: Date?
    private let locale: Locale

    public init(
        status: WidgetStatus,
        interfaceName: String? = nil,
        lastUpdated: Date? = nil,
        rating: IPRating? = nil,
        locale: Locale = .current
    ) {
        self.status = status
        self.rating = rating
        self.interfaceName = interfaceName
        self.lastUpdated = lastUpdated
        self.locale = locale
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            VStack(spacing: 0) {
                if !status.isOnline { Spacer(minLength: 0) }
                stage(side: side)
                Spacer(minLength: 0)
                if case .online(let geo) = status {
                    ratingRow(for: geo, side: side)
                        .padding(.top, side * 0.045)
                        .padding(.bottom, side * 0.060)
                }
                footer(side: side)
            }
            .padding(.horizontal, side * 0.040)
            .padding(.vertical, side * 0.030)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                Self.logger.debug(
                    "card side \(Double(side), privacy: .public) pt, frame \(Double(proxy.size.width), privacy: .public)×\(Double(proxy.size.height), privacy: .public)"
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stage(side: CGFloat) -> some View {
        switch status {
        case .updating:
            updating(side: side)
        case .loading:
            loading(side: side)
        case .online(let geo):
            online(geo, side: side)
        case .unavailable(let reason):
            unavailable(reason, side: side)
        }
    }

    private func online(_ geo: GeoInfo, side: CGFloat) -> some View {
        VStack(spacing: side * 0.005) {
            FlagView(
                countryCode: geo.countryCode,
                fallback: geo.flag,
                height: side * 0.470
            )
            .accessibilityLabel(countryName(for: geo))

            Text(countryName(for: geo))
                .font(.system(size: side * 0.083, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)

            Text(geo.ip.description)
                .font(.system(size: side * 0.078, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private func ratingRow(for geo: GeoInfo, side: CGFloat) -> some View {
        if let rating, rating.ip == geo.ip {
            HStack(spacing: side * 0.035) {
                RatingScaleView(percent: rating.percent, side: side)
                    .frame(height: side * 0.075)
                Text("\(rating.percent)%")
                    .font(.system(size: side * 0.070, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                if rating.isVPNOrProxy {
                    RatingVPNIcon()
                        .font(.system(size: side * 0.075, weight: .semibold))
                        .accessibilityLabel("VPN / Proxy")
                }
            }
            .padding(.horizontal, side * 0.055)
            .help("Synthetic IP reputation: \(rating.percent)%. Not a guarantee of Claude access.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("IP rating \(rating.percent) percent\(rating.isVPNOrProxy ? ", VPN or proxy detected" : "")")
        } else {
            Text("rating check...")
                .font(.system(size: side * 0.065, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(height: side * 0.070)
        }
    }

    private func updating(side: CGFloat) -> some View {
        VStack(spacing: side * 0.005) {
            Text("?")
                .font(.system(size: side * 0.60, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(height: side * 0.65)
            Text(t(.updatingData))
                .font(.system(size: side * 0.083, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func loading(side: CGFloat) -> some View {
        VStack(spacing: side * 0.040) {
            ProgressView()
                .controlSize(.regular)
            Text(t(.checking))
                .font(.system(size: side * 0.060, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func unavailable(_ reason: UnavailableReason, side: CGFloat) -> some View {
        VStack(spacing: side * 0.008) {
            Image(systemName: reason == .appNotRunning ? "arrow.up.forward.app.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: side * 0.450, weight: .regular))
                .foregroundStyle(reason == .appNotRunning ? .orange : .red)
                .frame(height: side * 0.510)
                .accessibilityLabel(t(reason == .appNotRunning ? .openApp : .noConnection))

            Text(t(reason == .appNotRunning ? .openApp : (reason == .noConnection ? .noConnection : .noResponse)))
                .font(.system(size: side * 0.090, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(t(reason == .appNotRunning ? .startApp : (reason == .noConnection ? .checkNetwork : .serviceUnavailable)))
                .font(.system(size: side * 0.055, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func footer(side: CGFloat) -> some View {
        HStack(spacing: side * 0.024) {
            Image(systemName: "circle.fill")
                .widgetAccentedRenderingMode(.fullColor)
                .font(.system(size: side * 0.045))
                .foregroundStyle(statusColor)
                .frame(width: side * 0.045, height: side * 0.045)
            Text(footerText)
                .font(.system(size: side * 0.072, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: side * 0.084)
        .accessibilityHidden(true)
    }

    private var dotAsset: String? {
        switch status {
        case .online: return "dot_green"
        case .unavailable: return "dot_red"
        case .loading, .updating: return "dot_gray"
        }
    }

    private var statusColor: Color {
        switch status {
        case .online: return .green
        case .unavailable(.appNotRunning): return .orange
        case .unavailable: return .red
        case .loading, .updating: return .secondary
        }
    }

    private var footerText: String {
        switch status {
        case .updating:
            return "IPv4"
        case .loading:
            return t(.checking)
        case .unavailable(.appNotRunning):
            return t(.dataExpired)
        case .unavailable:
            return "IPv4"
        case .online:
            let interface = interfaceName ?? "IPv4"
            guard let lastUpdated else { return interface }
            let time = lastUpdated.formatted(.dateTime.hour().minute().locale(locale))
            return "\(interface) · \(time)"
        }
    }

    private func countryName(for geo: GeoInfo) -> String {
        if geo.countryCode == nil && geo.countryName == nil {
            return t(.unknownCountry)
        }
        return geo.localizedCountryName(locale: locale)
    }

    private func t(_ key: L10n.Key) -> String {
        L10n.t(key, languageCode: locale.language.languageCode?.identifier)
    }
}
