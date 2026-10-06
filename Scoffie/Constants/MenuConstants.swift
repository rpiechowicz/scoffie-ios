struct MenuConstans {
    /// Zakładka „Pulpit” (6.10.2026 wieczór, Rafał; wcześniej tego dnia „Mój
    /// dzień” i „Dziś”, dawniej „Kalendarz”): to, co JA jem wczoraj, dziś i jutro — w odróżnieniu od
    /// Planu, który jest całego domu. Typ zostaje `Calendar`, bo tak zakładkę
    /// nazywa `DashboardTab.calendar`. Nagłówek ekranu dalej mówi „Dziś” /
    /// „Wczoraj” / „Jutro”.
    ///
    /// Ikoną w pasku jest ZNAK SCOFFIE (dysk z kęsem, Rafał 6.10.2026) —
    /// wektor `image` z katalogu zasobów, rysowany jako szablon jak symbole
    /// systemu. `icon` (talerz ze sztućcami) zostaje dla miejsc, które biorą
    /// symbol systemowy.
    struct Calendar: MenuModel {
        static let name: String = "Pulpit"
        static let icon: String = "fork.knife.circle"
        /// `Assets.xcassets/ScoffieTabMark` — geometria z `SCScoffieMark.markPath`.
        static let image: String = "ScoffieTabMark"
    }
    
    struct Recipes: MenuModel {
        static let name: String = "Przepisy"
        static let icon: String = "book.pages"
    }

    struct Plan: MenuModel {
        static let name: String = "Plan"
        /// Paragon — sylwetka spoza rodziny „kartka z liniami".
        ///
        /// Pasek miał trzy sąsiadujące zakładki o treści prostokąta:
        /// `book.pages` (Przepisy) i `calendar` (dawny Kalendarz). Przy 24 pt
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
