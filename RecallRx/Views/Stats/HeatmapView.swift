import SwiftUI

struct HeatmapView: View {
    let data: [Date: Int]

    @State private var selectedDate: Date?
    @State private var selectedCount: Int?

    private let calendar = Calendar.current
    private let weeksCount = 53
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Info / Selected Day Info
            HStack {
                if let date = selectedDate, let count = selectedCount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count) \(count == 1 ? "review" : "reviews")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text(date.formatted(date: .complete, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(totalYearReviews) reviews in the past year")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("Tap any square to view details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            // Heatmap Grid with Scroll
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        // Day Labels on Left (Mon, Wed, Fri)
                        dayLabelsColumn
                            .padding(.top, 18) // Offset for month labels

                        // Columns of Weeks
                        VStack(alignment: .leading, spacing: cellSpacing) {
                            // Month Labels
                            monthLabelsRow

                            // Grid of Cells
                            HStack(spacing: cellSpacing) {
                                ForEach(0..<weeksCount, id: \.self) { weekIndex in
                                    weekColumn(weekIndex: weekIndex)
                                        .id(weekIndex)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    // Auto-scroll to the most recent week
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(weeksCount - 1, anchor: .trailing)
                    }
                }
            }

            // Legend at Bottom
            HStack(spacing: 6) {
                Spacer()

                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                colorSample(color: Color(uiColor: .systemGray5))
                colorSample(color: Color.green.opacity(0.35))
                colorSample(color: Color.green.opacity(0.60))
                colorSample(color: Color.green.opacity(0.85))
                colorSample(color: Color.green)

                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Day Labels (Left)

    private var dayLabelsColumn: some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            Text("Mon")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(height: cellSize)

            Color.clear
                .frame(width: 20, height: cellSize)

            Text("Wed")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(height: cellSize)

            Color.clear
                .frame(width: 20, height: cellSize)

            Text("Fri")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(height: cellSize)

            Color.clear
                .frame(width: 20, height: cellSize)

            Color.clear
                .frame(width: 20, height: cellSize)
        }
    }

    // MARK: - Month Labels (Top)

    private var monthLabelsRow: some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<weeksCount, id: \.self) { weekIndex in
                let monthName = monthLabel(for: weekIndex)
                Text(monthName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: cellSize, alignment: .leading)
            }
        }
        .frame(height: 14)
    }

    private func monthLabel(for weekIndex: Int) -> String {
        guard let date = dateFor(week: weekIndex, dayOfWeek: 0) else { return "" }
        let dayOfMonth = calendar.component(.day, from: date)
        if dayOfMonth <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
        return ""
    }

    // MARK: - Week Column

    private func weekColumn(weekIndex: Int) -> some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { dayOfWeek in
                if let cellDate = dateFor(week: weekIndex, dayOfWeek: dayOfWeek) {
                    if cellDate <= Date.now {
                        let count = countFor(date: cellDate)
                        let isSelected = selectedDate != nil && calendar.isDate(selectedDate!, inSameDayAs: cellDate)

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(intensityColor(for: count))
                            .frame(width: cellSize, height: cellSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2.5)
                                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                selectedDate = cellDate
                                selectedCount = count
                            }
                    } else {
                        // Future day in the final week
                        Color.clear
                            .frame(width: cellSize, height: cellSize)
                    }
                } else {
                    Color.clear
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
    }

    // MARK: - Date Math & Lookup

    private var startMonday: Date {
        let today = calendar.startOfDay(for: .now)
        let totalDaysBack = (weeksCount - 1) * 7
        let estimatedStart = calendar.date(byAdding: .day, value: -totalDaysBack, to: today) ?? today
        let weekday = calendar.component(.weekday, from: estimatedStart) // 1=Sun, 2=Mon...
        let daysToMonday = (weekday == 1 ? -6 : 2 - weekday)
        return calendar.date(byAdding: .day, value: daysToMonday, to: estimatedStart) ?? estimatedStart
    }

    private func dateFor(week: Int, dayOfWeek: Int) -> Date? {
        let totalDays = (week * 7) + dayOfWeek
        return calendar.date(byAdding: .day, value: totalDays, to: startMonday)
    }

    private var normalizedData: [Date: Int] {
        var map = [Date: Int]()
        for (date, count) in data {
            let normalized = calendar.startOfDay(for: date)
            map[normalized, default: 0] += count
        }
        return map
    }

    private func countFor(date: Date) -> Int {
        let normalized = calendar.startOfDay(for: date)
        return normalizedData[normalized] ?? 0
    }

    private var totalYearReviews: Int {
        data.values.reduce(0, +)
    }

    // MARK: - Color Scale

    private func intensityColor(for count: Int) -> Color {
        switch count {
        case 0:
            return Color(uiColor: .systemGray5)
        case 1...4:
            return Color.green.opacity(0.35)
        case 5...9:
            return Color.green.opacity(0.60)
        case 10...19:
            return Color.green.opacity(0.85)
        default:
            return Color.green
        }
    }

    private func colorSample(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 10, height: 10)
    }
}
