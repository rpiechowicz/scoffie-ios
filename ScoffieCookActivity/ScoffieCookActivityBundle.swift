import SwiftUI
import WidgetKit

/// Rozszerzenie ma JEDNĄ rzecz: Live Activity trybu Gotuj. Szablony Xcode
/// (widżet ekranu głównego, Control, intencja konfiguracji) usunięte —
/// pokazałyby się w galerii widżetów jako „This is an example widget”.
@main
struct ScoffieCookActivityBundle: WidgetBundle {
    var body: some Widget {
        ScoffieCookActivityLiveActivity()
    }
}
