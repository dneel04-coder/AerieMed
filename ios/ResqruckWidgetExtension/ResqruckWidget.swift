import WidgetKit
import SwiftUI

private let appGroupId = "group.com.peninsulathreat.resqruck"

struct ResqruckWidgetEntry: TimelineEntry {
    let date: Date
    let coords: String
    let mapImage: UIImage?
}

struct ResqruckWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResqruckWidgetEntry {
        ResqruckWidgetEntry(date: Date(), coords: "Locating…", mapImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ResqruckWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ResqruckWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Ask iOS to check back in 30 minutes -- WidgetKit's own timeline
        // budget still applies; the Flutter app also pushes a fresh entry
        // whenever it's foregrounded (see HomeWidgetService.refreshNow).
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> ResqruckWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let coords = defaults?.string(forKey: "coords") ?? "Locating…"
        var image: UIImage? = nil
        if let path = defaults?.string(forKey: "map_snapshot") {
            image = UIImage(contentsOfFile: path)
        }
        return ResqruckWidgetEntry(date: Date(), coords: coords, mapImage: image)
    }
}

struct ResqruckWidgetView: View {
    var entry: ResqruckWidgetEntry

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = entry.mapImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0.05, green: 0.07, blue: 0.09)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(entry.coords)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(6)
                Spacer()
            }

            HStack(spacing: 4) {
                Link(destination: URL(string: "resqruck://protocols")!) {
                    Text("Protocols")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.8, green: 0.13, blue: 0.13))
                }
                Link(destination: URL(string: "resqruck://8line")!) {
                    Text("8-Line/206WF")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.72, green: 0.11, blue: 0.11))
                }
            }
        }
        .widgetURL(URL(string: "resqruck://map"))
    }
}

struct ResqruckWidget: Widget {
    let kind: String = "ResqruckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ResqruckWidgetProvider()) { entry in
            ResqruckWidgetView(entry: entry)
        }
        .configurationDisplayName("Res-Q-Ruck")
        .description("Your current location, plus quick access to Protocols and the 8-Line/206WF form.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
