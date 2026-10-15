import WidgetKit
import SwiftUI

struct DueEntry: TimelineEntry {
    let date: Date
    let due: Int
    let streak: Int
}

struct DueProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        DueEntry(date: Date(), due: 0, streak: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> DueEntry {
        let defaults = UserDefaults(suiteName: "group.com.recallrx.app")
        guard
            let data = defaults?.data(forKey: "recallrx_widget_data"),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return DueEntry(date: Date(), due: 0, streak: 0)
        }
        return DueEntry(
            date: Date(),
            due: obj["totalDue"] as? Int ?? 0,
            streak: obj["streakDays"] as? Int ?? 0
        )
    }
}

struct DueWidgetView: View {
    var entry: DueEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RecallRx")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(entry.due)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(entry.due == 1 ? "card due" : "cards due")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.streak > 0 {
                Text("\(entry.streak) day streak")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

struct DueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecallRxDue", provider: DueProvider()) { entry in
            DueWidgetView(entry: entry)
        }
        .configurationDisplayName("Cards Due")
        .description("How many RecallRx cards are waiting today.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

@main
struct RecallRxWidgetBundle: WidgetBundle {
    var body: some Widget {
        DueWidget()
    }
}
