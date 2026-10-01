import Foundation

/// Przepis wskazany linkiem.
///
/// Dwa rodzaje, bo to dwa różne klucze po stronie serwera: przepis katalogu
/// ma stały, publiczny `slug` (albo — w starych i awaryjnych linkach — swoje
/// UUID), a przepis własny gospodarstwa wychodzi z domu wyłącznie przez
/// token, który domownik może w każdej chwili wyłączyć. Oba otwiera jedno
/// zdarzenie (`recipes:openShared`), różni je tylko pole w ładunku.
enum RecipeLinkTarget: Hashable {
    /// `slug` katalogu albo UUID przepisu katalogu (serwer przyjmuje oba).
    case catalog(slug: String)
    /// Token linku przepisu własnego (`/przepis/u/<token>`).
    case shared(token: String)

    /// Klucz do `.task(id:)` — zmienia się z każdym innym linkiem.
    var key: String {
        switch self {
        case .catalog(let slug): return "slug:\(slug)"
        case .shared(let token): return "token:\(token)"
        }
    }

    /// Token, gdy link go niesie.
    var shareToken: String? {
        if case .shared(let token) = self { return token }
        return nil
    }
}

/// Każdy link, który otwiera aplikację — Universal Link z `scoffie.app`
/// albo schemat `scoffie://`, którym strona otwiera aplikację przyciskiem
/// („Otwórz w Scoffie”): Universal Link nie uruchamia aplikacji z tej samej
/// domeny, na której właśnie stoi przeglądarka.
///
/// JEDEN parser dla wszystkich wejść. Zaproszenia miały dotąd własny
/// (`SessionStore.invitationToken(from:)`), a przepisy dostałyby drugi —
/// i dwa miejsca, które muszą zgadzać się co do hostów, końcowych ukośników
/// i schematu, rozjechałyby się przy pierwszej zmianie. Kształty adresów
/// są w kontrakcie udostępniania (backend, strona, Android — te same).
enum DeepLink: Equatable {
    case invitation(token: String)
    case recipe(RecipeLinkTarget)
    /// `scoffie://gotuj` — stuknięcie w Live Activity trybu Gotuj: powrót do
    /// trwającej sesji. Tylko schemat, bez adresu strony (nie wychodzi poza
    /// telefon i nie czeka na zalogowanie).
    case cooking

    /// Host strony — ten sam, na który wskazuje karta OG i plik
    /// `apple-app-site-association`. Uprawnienia mają TYLKO ten host:
    /// `www` to przekierowanie na apex, a Apple nie pobiera pliku skojarzenia
    /// zza przekierowania. Parser i tak przyjmuje oba — adres z `www` może
    /// trafić tu inną drogą (wklejony, ze starej wiadomości).
    static let host = "scoffie.app"
    private static let hosts: Set<String> = [host, "www.\(host)"]

    /// `^[a-z0-9]+(?:-[a-z0-9]+)*$`, 1–80 znaków — slug nadaje baza.
    private static let slugPattern = "^[a-z0-9]+(?:-[a-z0-9]+)*$"
    /// 16 losowych bajtów w base64url.
    private static let shareTokenPattern = "^[A-Za-z0-9_-]{22}$"

    /// Link rozpoznany albo `nil` — obcy adres, obca ścieżka, zły token.
    /// Nieznany link nie robi nic: aplikacja otwiera się tam, gdzie była.
    init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func query(_ name: String) -> String? {
            guard let value = components?.queryItems?.first(where: { $0.name == name })?.value,
                  !value.isEmpty else { return nil }
            return value
        }

        if scheme == "scoffie" {
            switch host ?? "" {
            case "gotuj":
                self = .cooking
            case "invite":
                guard let token = query("token") else { return nil }
                self = .invitation(token: token)
            case "recipe":
                // Dokładnie jedno z dwóch — a gdyby przyszły oba, token jest
                // węższy (wskazuje konkretny link, nie tylko przepis).
                if let token = query("token"), Self.isShareToken(token) {
                    self = .recipe(.shared(token: token))
                } else if let slug = query("slug"), let normalized = Self.normalizedSlug(slug) {
                    self = .recipe(.catalog(slug: normalized))
                } else {
                    return nil
                }
            default:
                return nil
            }
            return
        }

        guard scheme == "https", let host, Self.hosts.contains(host) else { return nil }
        // `pathComponents` gubi końcowy ukośnik — `/przepis/abc` i
        // `/przepis/abc/` to ten sam adres, jak chce kontrakt.
        let parts = url.pathComponents.filter { $0 != "/" }
        switch parts.first ?? "" {
        case "zaproszenie":
            guard parts.count == 1 else { return nil }
            // Token we FRAGMENCIE (patrz `SessionStore.createInvitationLink`),
            // awaryjnie `?t=`.
            let fragment = components?.fragment ?? ""
            guard let token = fragment.isEmpty ? query("t") : fragment else { return nil }
            self = .invitation(token: token)
        case "przepis":
            if parts.count == 3, parts[1] == "u", Self.isShareToken(parts[2]) {
                self = .recipe(.shared(token: parts[2]))
            } else if parts.count == 2, let slug = Self.normalizedSlug(parts[1]) {
                self = .recipe(.catalog(slug: slug))
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    /// Adres kanoniczny — ten sam, który wysyła się dalej. Na nim stoi też
    /// odkładanie linku do czasu zalogowania (`SessionStore.storedDeepLink`):
    /// w `UserDefaults` leży adres, a nie własny format, więc stary i nowy
    /// build czytają go tym samym parserem.
    var url: URL? {
        if case .cooking = self { return URL(string: "scoffie://gotuj") }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        switch self {
        case .invitation(let token):
            components.path = "/zaproszenie/"
            components.fragment = token
        case .recipe(.catalog(let slug)):
            components.path = "/przepis/\(slug)"
        case .recipe(.shared(let token)):
            components.path = "/przepis/u/\(token)"
        case .cooking:
            return nil
        }
        return components.url
    }

    /// Slug albo UUID (w dowolnej wielkości liter — UUID małymi, jak w bazie).
    private static func normalizedSlug(_ raw: String) -> String? {
        if let uuid = UUID(uuidString: raw) { return uuid.uuidString.lowercased() }
        guard (1...80).contains(raw.count),
              raw.range(of: slugPattern, options: .regularExpression) != nil else { return nil }
        return raw
    }

    private static func isShareToken(_ raw: String) -> Bool {
        raw.range(of: shareTokenPattern, options: .regularExpression) != nil
    }
}
