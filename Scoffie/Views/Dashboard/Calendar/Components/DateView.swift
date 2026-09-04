import SwiftUI

struct DateView: View {
    let isSelected: Bool
    let isToday: Bool
    let isEditable: Bool
    let dayName: String
    let dayNumber: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text(dayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)

            Text(dayNumber)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                .monospacedDigit()

            HStack(spacing: 5) {
                if isToday {
                    Circle()
                        .fill(.blue)
                        .frame(width: 5, height: 5)
                }

                if !isEditable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 12)
        .frame(width: 66, height: 94)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        }
        .opacity(isEditable ? 1 : 0.62)
    }

    private var cardFill: Color {
        if isSelected {
            return colorScheme == .dark
                ? Color.blue.opacity(0.26)
                : Color.blue.opacity(0.22)
        }

        return DashboardPalette.surface(colorScheme, level: .secondary)
    }

    private var cardStroke: Color {
        if isSelected {
            return colorScheme == .dark
                ? Color.cyan.opacity(0.5)
                : Color.blue.opacity(0.5)
        }

        return DashboardPalette.neutralBorder(colorScheme, opacity: 0.16)
    }
}
