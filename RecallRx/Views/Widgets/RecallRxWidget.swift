import SwiftUI

/// Widget View for RecallRx
/// Can be embedded into a WidgetKit Extension or previewed directly inside RecallRx Settings.
struct RecallRxWidgetView: View {
    let data: WidgetSnapshotData
    var family: WidgetFamilyType = .systemSmall
    
    enum WidgetFamilyType {
        case systemSmall
        case systemMedium
        case accessoryCircular
        case accessoryRectangular
    }
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .accessoryCircular:
            circularLockScreenWidget
        case .accessoryRectangular:
            rectangularLockScreenWidget
        }
    }
    
    // MARK: - System Small Widget
    
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cross.case.fill")
                    .foregroundColor(.blue)
                    .font(.caption.bold())
                Text("RecallRx")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Spacer()
                if data.streakDays > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                        Text("\(data.streakDays)d")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(data.totalDue)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(data.totalDue > 0 ? .primary : .green)
                
                Text(data.totalDue > 0 ? "Cards Due" : "All Done!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Due Breakdown pill
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("\(data.newCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("\(data.learnCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                }
                
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(data.reviewCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.green)
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    // MARK: - System Medium Widget
    
    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Left column: big due count
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "cross.case.fill")
                        .foregroundColor(.blue)
                    Text("RecallRx")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(data.totalDue)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(data.totalDue > 0 ? .primary : .green)
                
                Text(data.totalDue > 0 ? "Total Due Today" : "Deck Caught Up!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if data.streakDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("\(data.streakDays) Day Streak")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Right column: deck and category breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text(data.topDeckName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                VStack(spacing: 6) {
                    breakdownRow(label: "New Cards", count: data.newCount, color: .blue)
                    breakdownRow(label: "Learning", count: data.learnCount, color: .orange)
                    breakdownRow(label: "Review", count: data.reviewCount, color: .green)
                }
                
                Spacer()
                
                Text("Updated \(data.lastUpdated, style: .time)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private func breakdownRow(label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption.bold())
                .foregroundColor(color)
        }
    }
    
    // MARK: - Lock Screen Widgets
    
    private var circularLockScreenWidget: some View {
        VStack(spacing: 2) {
            Image(systemName: "cross.case.fill")
                .font(.caption2)
            Text("\(data.totalDue)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("DUE")
                .font(.system(size: 8, weight: .bold))
        }
    }
    
    private var rectangularLockScreenWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "cross.case.fill")
                Text("RecallRx")
                    .font(.caption.bold())
                Spacer()
                Text("\(data.streakDays)d streak")
                    .font(.caption2)
            }
            Text("\(data.totalDue) cards due for review")
                .font(.subheadline.bold())
            Text(data.topDeckName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

/// In-App Settings & Preview View for Widgets
struct WidgetPreviewSection: View {
    let data = WidgetDataManager.shared.getWidgetData()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("iOS 17 Home & Lock Screen Widgets")
                .font(.headline)
            
            Text("Keep your medical review streak active with live due count widgets and automatic app icon badges.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                RecallRxWidgetView(data: data, family: .systemSmall)
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Small Due Counter", systemImage: "square.grid.2x2.fill")
                        .font(.caption.bold())
                    Label("Lock Screen Gauge", systemImage: "gauge.with.needle.fill")
                        .font(.caption.bold())
                    Label("App Icon Due Badge", systemImage: "app.badge.fill")
                        .font(.caption.bold())
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
