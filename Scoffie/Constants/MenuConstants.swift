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
        /// Paragon — sylwetka spoza rodziny „kartka z liniami".
        ///
        /// Pasek ma trzy sąsiadujące zakładki o treści prostokąta:
        /// `book.pages` (Przepisy) i `calendar` (Kalendarz). Przy 24 pt
        /// zostaje z nich sama sylwetka, więc kolejna kartka tylko przesuwa
        /// kolizję o jedną zakładkę dalej. Paragon ma postrzępiony dół —
        /// to jedyny szczegół, który przy tym rozmiarze przeżywa i od razu
        /// odróżnia go od książki i od siatki kalendarza.
        static let icon: String = "receipt"
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
