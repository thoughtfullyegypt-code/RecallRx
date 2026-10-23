import SwiftUI
import Charts

struct StatsCardDistributionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let distribution: (new: Int, learning: Int, young: Int, mature: Int)

    private var total: Int {
        distribution.new + distribution.learning + distribution.young + distribution.mature
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your card collection")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("\(total.formatted()) cards · current state")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if total == 0 {
                ContentUnavailableView("No cards in this selection", systemImage: "rectangle.stack", description: Text("Choose another deck or add cards to start your collection."))
            } else {
                let rows = [
                    (name: "New", count: distribution.new, color: Color.blue),
                    (name: "Learning", count: distribution.learning, color: Color.orange),
                    (name: "Young", count: distribution.young, color: AppTheme.accent),
                    (name: "Mature", count: distribution.mature, color: Color.indigo)
                ]
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
                layout {
                    Chart(rows, id: \.name) { item in
                        SectorMark(angle: .value("Cards", item.count), innerRadius: .ratio(0.7), angularInset: 2)
                            .foregroundStyle(item.color)
                    }
                    .frame(width: 130, height: 130)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows, id: \.name) { item in
                            LabeledContent {
                                Text(item.count, format: .number)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text(item.name)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(item.color)
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Young cards have intervals under 21 days; mature cards have intervals of 21 days or more.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }
}
