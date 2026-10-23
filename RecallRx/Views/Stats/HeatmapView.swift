import SwiftUI

struct HeatmapView: View {
    let data: [Date: Int]
    @State private var monthOffset = 0
    @State private var selectedDate = Date.now
    @ScaledMetric(relativeTo: .body) private var dayWidth: CGFloat = 44
    @Environment(\.calendar) private var calendar

    private var displayedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var earliestDate: Date {
        calendar.date(byAdding: .day, value: -365, to: calendar.startOfDay(for: .now)) ?? .now
    }

    private var normalizedData: [Date: Int] {
        data.reduce(into: [:]) { result, item in
            result[calendar.startOfDay(for: item.key), default: 0] += item.value
        }
    }

    var body: some View {
        let counts = normalizedData
        let leadingDays = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0
        VStack(alignment: .leading, spacing: 16) {
            Text("\(data.values.reduce(0, +).formatted()) reviews in the past year")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Previous month", systemImage: "chevron.left", action: previousMonth)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(monthOffset <= -12)
                Spacer(minLength: 0)
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Next month", systemImage: "chevron.right", action: nextMonth)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(monthOffset == 0)
            }

            ScrollView(.horizontal) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(dayWidth)), count: 7), spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let dayIndex = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[dayIndex])
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: dayWidth)
                            .accessibilityHidden(true)
                    }
                    ForEach(0..<(leadingDays + dayCount), id: \.self) { index in
                        if index < leadingDays {
                            Color.clear
                                .frame(width: dayWidth, height: dayWidth)
                                .accessibilityHidden(true)
                        } else if let date = calendar.date(byAdding: .day, value: index - leadingDays, to: monthStart) {
                            let count = counts[calendar.startOfDay(for: date)] ?? 0
                            let isAvailable = date >= earliestDate && date <= Date.now
                            HeatmapDayButton(date: date, count: count, isSelected: calendar.isDate(date, inSameDayAs: selectedDate), isAvailable: isAvailable) {
                                selectedDate = date
                            }
                        }
                    }
                }
                .padding(2)
            }
            .defaultScrollAnchor(.leading)

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(counts[calendar.startOfDay(for: selectedDate)] ?? 0) reviews")
                    .font(.headline)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            Text("Select a day to see its review count. Darker tiles indicate more reviews; only the past year is available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }

    private func previousMonth() {
        monthOffset = max(-12, monthOffset - 1)
        let previous = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        selectedDate = max(earliestDate, previous)
    }

    private func nextMonth() {
        monthOffset = min(0, monthOffset + 1)
        let next = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        selectedDate = min(.now, next)
    }
}
