import SwiftUI

struct NutritionCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(unit)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DashboardPalette.surface(colorScheme, level: .secondary))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DashboardPalette.neutralBorder(colorScheme, opacity: 0.08), lineWidth: 1)
        )
    }
}


#Preview {
    NutritionCard(title: "Kalorie", value: "250", unit: "kcal", icon: "flame.fill", color: .orange)
}
