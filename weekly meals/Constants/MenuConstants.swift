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
        /// Sztućce — jedyna ikona w tym pasku, która nie jest prostokątem.
        ///
        /// Pasek ma trzy sąsiadujące zakładki o treści „kartka z liniami":
        /// `book.pages` (Przepisy), `menucard` (jadłospis) i `calendar`
        /// (Kalendarz). Przy 24 pt zostaje z nich sama sylwetka, a wszystkie
        /// trzy mają tę samą — więc każda kolejna „kartka" tylko przesuwa
        /// kolizję o jedną zakładkę dalej, zamiast ją usunąć. Sztućce łamią
        /// tę rodzinę kształtów i czytają się z odległości ręki.
        static let icon: String = "fork.knife"
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
