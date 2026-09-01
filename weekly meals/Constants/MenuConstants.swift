struct MenuConstans {
    struct Calendar: MenuModel {
        static let name: String = "Kalendarz"
        static let icon: String = "calendar"
    }
    
    struct Recipes: MenuModel {
        static let name: String = "Przepisy"
        static let icon: String = "book.pages"
    }

    struct Plan: MenuModel {
        static let name: String = "Plan"
        /// Karta z jadłospisem, nie kalendarz.
        ///
        /// `calendar.badge.clock` stał obok `calendar` Kalendarza i przy 24 pt
        /// obie ikony miały tę samą sylwetkę — plakietka zegara schodziła do
        /// plamki. Przy tym rozmiarze przeżywa wyłącznie kształt, więc dwie
        /// sąsiednie zakładki nie mogą go dzielić.
        static let icon: String = "menucard"
    }
    
    /// Produkty NIE są już zakładką — wpis zostaje, bo z tej samej nazwy
    /// i ikony korzysta przycisk w nagłówku Planu tygodnia.
    struct Products: MenuModel {
        static let name: String = "Produkty"
        static let icon: String = "basket.fill"
    }

    struct Assistant: MenuModel {
        static let name: String = "Asystent"
        static let icon: String = "sparkles"
    }
    
    struct Settings: MenuModel {
        static let name: String = "Ustawienia"
        static let icon: String = "gearshape"
    }
}
