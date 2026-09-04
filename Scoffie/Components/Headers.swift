import SwiftUI

struct Headers: View {
    let title: String
    let subtitle: String
    
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
    
    init<T: HeaderModel>(_ configurationType: T.Type) {
        self.title = configurationType.title
        self.subtitle = configurationType.subtitle
    }
    
    var body: some View {
        VStack() {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .default))
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
//                TODO: Dodac akcje ikony
//                Spacer()
//                Image(systemName: "plus.circle.fill")
//                    .font(Font.system(size: 30, weight: .bold, design: .default))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

#Preview("Custom") {
    Headers(title: "Custom Title", subtitle: "Custom Subtitle")
}

