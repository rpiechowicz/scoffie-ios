import Foundation

// Parser linków (`Scoffie/Models/Session/DeepLink.swift`) — adresy z kontraktu
// udostępniania (29.09.2026), bez Xcode GUI i bez targetu testów.
// Uruchomienie: `sh Scripts/deep-link-check.sh`.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

func link(_ raw: String) -> DeepLink? {
    URL(string: raw).flatMap { DeepLink(url: $0) }
}

// 22 znaki base64url. Składany, nie wpisany: skaner sekretów w CI bierze
// losowo wyglądający literał za klucz.
let token = String(repeating: "a", count: 10) + "_-" + String(repeating: "Z", count: 10)
let uuid = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

// MARK: - Zaproszenia (bez zmian wobec parsera sprzed DeepLink)

check(link("https://scoffie.app/zaproszenie/#abc") == .invitation(token: "abc"), "zaproszenie: token we fragmencie")
check(link("https://www.scoffie.app/zaproszenie#abc") == .invitation(token: "abc"), "zaproszenie: www i bez końcowego /")
check(link("https://scoffie.app/zaproszenie/?t=abc") == .invitation(token: "abc"), "zaproszenie: awaryjne ?t=")
check(link("https://scoffie.app/zaproszenie/") == nil, "zaproszenie: bez tokenu → nic")
check(link("scoffie://invite?token=abc") == .invitation(token: "abc"), "zaproszenie: schemat")
check(link("scoffie://invite") == nil, "zaproszenie: schemat bez tokenu → nic")

// MARK: - Live Activity gotowania

check(link("scoffie://gotuj") == .cooking, "gotowanie: schemat")
check(DeepLink.cooking.url?.absoluteString == "scoffie://gotuj", "gotowanie: adres")

// MARK: - Przepisy

check(link("https://scoffie.app/przepis/bigos-staropolski") == .recipe(.catalog(slug: "bigos-staropolski")), "przepis: slug")
check(link("https://scoffie.app/przepis/bigos-staropolski/") == .recipe(.catalog(slug: "bigos-staropolski")), "przepis: końcowy / opcjonalny")
check(link("https://www.scoffie.app/przepis/bigos") == .recipe(.catalog(slug: "bigos")), "przepis: www")
check(link("https://scoffie.app/przepis/\(uuid)") == .recipe(.catalog(slug: uuid.lowercased())), "przepis: UUID (małymi literami)")
check(link("https://scoffie.app/przepis/Bigos") == nil, "przepis: wielka litera w slugu → nic")
check(link("https://scoffie.app/przepis/bigos--x") == nil, "przepis: podwójny myślnik → nic")
check(link("https://scoffie.app/przepis/" + String(repeating: "a", count: 81)) == nil, "przepis: slug dłuższy niż 80 → nic")
check(link("https://scoffie.app/przepis/u/\(token)") == .recipe(.shared(token: token)), "przepis domu: token")
check(link("https://scoffie.app/przepis/u/\(token)/") == .recipe(.shared(token: token)), "przepis domu: końcowy /")
check(link("https://scoffie.app/przepis/u/abc") == nil, "przepis domu: za krótki token → nic")
check(link("https://scoffie.app/przepis/a/b") == nil, "przepis: obca ścieżka → nic")
check(link("https://example.com/przepis/bigos") == nil, "obcy host → nic")
check(link("http://scoffie.app/przepis/bigos") == nil, "http zamiast https → nic")
check(link("https://scoffie.app/") == nil, "strona główna → nic")
check(link("scoffie://recipe?slug=bigos") == .recipe(.catalog(slug: "bigos")), "schemat: slug")
check(link("scoffie://recipe?token=\(token)") == .recipe(.shared(token: token)), "schemat: token")
check(link("scoffie://recipe?token=\(token)&slug=bigos") == .recipe(.shared(token: token)), "schemat: oba → token")
check(link("scoffie://recipe") == nil, "schemat: bez niczego → nic")

// MARK: - Adres kanoniczny (odkładanie linku przed zalogowaniem)

for original in [
    DeepLink.invitation(token: "abc"),
    .recipe(.catalog(slug: "bigos-staropolski")),
    .recipe(.shared(token: token)),
] {
    let roundTrip = original.url.flatMap { DeepLink(url: $0) }
    check(roundTrip == original, "adres kanoniczny wraca tym samym linkiem: \(original.url?.absoluteString ?? "nil")")
}
check(DeepLink.invitation(token: "abc").url?.absoluteString == "https://scoffie.app/zaproszenie/#abc",
      "zaproszenie: ten sam adres co dawny createInvitationLink")

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
