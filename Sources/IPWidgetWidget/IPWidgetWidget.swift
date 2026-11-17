import AppKit
import SwiftUI
import WidgetKit
import os

struct IPWidgetEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus
    let lastUpdated: Date?
    let interfaceName: String?
    let rating: IPRating?

    init(date: Date, status: WidgetStatus, lastUpdated: Date? = nil, interfaceName: String? = nil, rating: IPRating? = nil) {
        self.date = date
        self.status = status
        self.lastUpdated = lastUpdated
        self.interfaceName = interfaceName
        self.rating = rating
    }
}

struct IPWidgetProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "widget-file")
    private static let sampleGeo = GeoInfo(
        ip: IPv4Address(rawValue: 0x2D9F_0C07), countryCode: "SE", countryName: "Sweden"
    )

    func placeholder(in context: Context) -> IPWidgetEntry {
        IPWidgetEntry(date: Date(), status: .online(Self.sampleGeo))
    }

    func getSnapshot(in context: Context, completion: @escaping (IPWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(now: Date())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IPWidgetEntry>) -> Void) {
        // Expiration is a precomputed entry, not a timer or network request.
        // The companion explicitly reloads this timeline after writing new data.
        completion(Timeline(entries: entries(now: Date()), policy: .never))
    }

    private func entries(now: Date) -> [IPWidgetEntry] {
        do {
            let snapshot = try SharedWidgetStore.standard().read()
            let status = snapshot.displayStatus(at: now)
            Self.logger.info("shared snapshot read; age=\(now.timeIntervalSince(snapshot.checkedAt), privacy: .public)s")
            let current = IPWidgetEntry(date: now, status: status,
                                        lastUpdated: snapshot.lastUpdated, interfaceName: snapshot.interfaceName, rating: snapshot.rating)
            guard status != .unavailable(.appNotRunning) else { return [current] }
            return [current, IPWidgetEntry(date: snapshot.expiresAt.addingTimeInterval(0.001),
                                          status: .unavailable(.appNotRunning))]
        } catch {
            Self.logger.error("could not read shared snapshot: \(String(describing: error), privacy: .public)")
            return [IPWidgetEntry(date: now, status: .unavailable(.appNotRunning))]
        }
    }
}

struct IPWidgetBackground: View {
    let status: WidgetStatus

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if case .unavailable = status {
                Color.red.opacity(0.10)
            }
        }
    }
}

struct IPWidgetEntryView: View {
    var entry: IPWidgetEntry

    var body: some View {
        WidgetCard(
            status: entry.status,
            interfaceName: entry.interfaceName,
            lastUpdated: entry.lastUpdated,
            rating: entry.rating
        )
        .widgetURL(URL(string: "ipwidget://refresh"))
        .containerBackground(for: .widget) {
            IPWidgetBackground(status: entry.status)
        }
    }
}

struct IPWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: IPWidgetConstants.kind, provider: IPWidgetProvider()) { entry in
            IPWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("IP Widget")
        .description("Country and external IPv4 of the default route")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct IPWidgetBundle: WidgetBundle {
    var body: some Widget {
        IPWidget()
    }
}
