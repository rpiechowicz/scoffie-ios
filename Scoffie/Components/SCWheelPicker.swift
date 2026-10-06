import SwiftUI
import UIKit

/// Kolumna systemowego koła (`SCWheelPicker`).
struct SCWheelColumn {
    let titles: [String]
    /// Indeks wybranego wiersza. `nil` = kolumna stała (jednostka „kg” obok
    /// liczb) — kręci się w miejscu, niczego nie wybiera.
    let selection: Binding<Int>?
    /// Szerokość kolumny. Koło stawia kolumny obok siebie na środku, więc
    /// szerokości decydują, czy „61”, „,5” i „kg” czytają się jak jedna liczba.
    let width: CGFloat
    var alignment: NSTextAlignment = .center
    let accessibilityLabel: String
}

/// Systemowe koło z kilkoma kolumnami obok siebie — jak waga w Zdrowiu:
/// kilogramy, dziesiąte i „kg” (Ustawienia → „Twoje dane”, 6.10.2026).
///
/// Własne opakowanie `UIPickerView`, a nie `Picker(.wheel)`, z jednego powodu:
/// SwiftUI daje kołu jedną kolumnę, a dwa takie koła postawione w `HStack`
/// nakładają na siebie obszary dotyku — UIKit liczy je z naturalnej szerokości
/// koła (~320 pt), nie z przyciętej ramki, więc prawe koło kręciło lewym.
/// Jedno koło z kolumnami tego problemu nie ma, a wygląda i działa tak samo jak
/// każde koło systemu (pasek wyboru, dźwięk, VoiceOver).
///
/// Wartość zapisuje się, gdy koło stanie (`didSelectRow`), jak w `DatePicker`.
struct SCWheelPicker: UIViewRepresentable {
    let columns: [SCWheelColumn]
    var textColor: UIColor = .label

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        // Rozmiar daje SwiftUI (`sizeThatFits`) — koło ma się ścisnąć do ramki
        // arkusza na 1/3 ekranu, a nie rozpychać do naturalnych 216 pt.
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let coordinator = context.coordinator
        let titles = columns.map(\.titles)
        let needsReload = coordinator.titles != titles || coordinator.textColor != textColor
        coordinator.columns = columns
        coordinator.titles = titles
        coordinator.textColor = textColor
        if needsReload {
            picker.reloadAllComponents()
        }

        // Wartość zmieniona z zewnątrz (np. 250 kg zeruje dziesiąte) — koło
        // dojeżdża do niej. Przy pierwszym ułożeniu staje od razu, bez jazdy.
        for (component, column) in columns.enumerated() {
            guard let selection = column.selection else { continue }
            let row = selection.wrappedValue
            guard column.titles.indices.contains(row),
                  picker.selectedRow(inComponent: component) != row
            else { continue }
            picker.selectRow(row, inComponent: component, animated: !needsReload)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: min(proposal.height ?? 216, 216))
    }

    /// Delegat dostępności (`UIPickerViewAccessibilityDelegate` rozszerza zwykły
    /// delegat) — bez niego UIKit nie zapyta o nazwy kolumn dla VoiceOver.
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
        var columns: [SCWheelColumn] = []
        var titles: [[String]] = []
        var textColor: UIColor = .label

        /// Krój koła systemu (~22 pt) rosnący z „Większym tekstem” — z sufitem,
        /// żeby trzy kolumny wagi mieściły się w szerokości telefonu.
        private var font: UIFont {
            UIFontMetrics(forTextStyle: .title3).scaledFont(
                for: .systemFont(ofSize: 22, weight: .regular),
                maximumPointSize: 30
            )
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            columns.count
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            columns.indices.contains(component) ? columns[component].titles.count : 0
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            columns.indices.contains(component) ? columns[component].width : 0
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            ceil(font.lineHeight) + 14
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            let column = columns[component]
            label.text = column.titles.indices.contains(row) ? column.titles[row] : ""
            label.font = font
            label.textColor = textColor
            label.textAlignment = column.alignment
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard columns.indices.contains(component),
                  let selection = columns[component].selection
            else { return }
            selection.wrappedValue = row
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            columns.indices.contains(component) ? columns[component].accessibilityLabel : nil
        }
    }
}
