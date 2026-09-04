import SwiftUI

struct DatesView: View {
    @Bindable var datesViewModal: DatesViewModel

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private var weekRangeText: String {
        guard let first = datesViewModal.dates.first,
              let last = datesViewModal.dates.last else {
            return "Bieżący tydzień"
        }
        return "\(Self.weekRangeFormatter.string(from: first)) - \(Self.weekRangeFormatter.string(from: last))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                weekControlButton(systemName: "chevron.left") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        datesViewModal.goToPreviousWeek()
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Tydzień")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(weekRangeText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !datesViewModal.isCurrentWeek {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            datesViewModal.goToCurrentWeek()
                        }
                    } label: {
                        Text("Dziś")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                weekControlButton(systemName: "chevron.right") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        datesViewModal.goToNextWeek()
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(datesViewModal.dates, id: \.self) { date in
                            DateView(
                                isSelected: datesViewModal.isSelected(date),
                                isToday: datesViewModal.isToday(date),
                                isEditable: datesViewModal.isEditable(date),
                                dayName: datesViewModal.dayName(for: date),
                                dayNumber: datesViewModal.dayNumber(for: date)
                            )
                            .id(date)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    datesViewModal.selectDate(date)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
                .onAppear {
                    scrollTo(date: datesViewModal.selectedDate, with: proxy, animated: false)
                }
                .onChange(of: datesViewModal.selectedDate) { _, newValue in
                    scrollTo(date: newValue, with: proxy, animated: true)
                }
            }
        }
        .padding(16)
    }

    private func weekControlButton(systemName: String, action: @escaping () -> Void) -> some View {
        DashboardActionButton(
            title: nil,
            systemImage: systemName,
            controlSize: 34,
            action: action
        )
    }

    private func scrollTo(date: Date, with proxy: ScrollViewProxy, animated: Bool) {
        let targetDate = datesViewModal.dates.first { Calendar.current.isDate($0, inSameDayAs: date) }
            ?? datesViewModal.dates.first

        guard let targetDate else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(targetDate, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetDate, anchor: .center)
        }
    }
}

#Preview {
    DatesView(datesViewModal: DatesViewModel())
        .padding()
}
