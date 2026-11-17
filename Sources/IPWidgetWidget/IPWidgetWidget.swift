import AppKit
import SwiftUI
import WidgetKit

struct IPWidgetEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus
}

struct IPWidgetProvider: TimelineProvider {
    private static let service = MultiIPClient()
    private static let sampleGeo = GeoInfo(
        ip: IPv4Address(rawValue: 0x2D9F_0C07), // 45.159.12.7
        countryCode: "SE",
        countryName: "Sweden"
    )

    func placeholder(in context: Context) -> IPWidgetEntry {
        IPWidgetEntry(date: Date(), status: .online(Self.sampleGeo))
    }

    func getSnapshot(in context: Context, completion: @escaping (IPWidgetEntry) -> Void) {
        if context.isPreview {
            completion(IPWidgetEntry(date: Date(), status: .online(Self.sampleGeo)))
        } else {
            completion(IPWidgetEntry(date: Date(), status: .loading))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IPWidgetEntry>) -> Void) {
        Task {
            let status = await WidgetSnapshotLoader.status(using: Self.service)
            let entry = IPWidgetEntry(date: Date(), status: status)
            let next = Date().addingTimeInterval(IPWidgetConstants.refreshInterval + Double.random(in: -30...30))
            completion(Timeline(entries: [entry], policy: .after(next)))
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
            interfaceName: nil,
            lastUpdated: entry.date
        )
        .widgetURL(URL(string: "https://2ip.io/"))
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
