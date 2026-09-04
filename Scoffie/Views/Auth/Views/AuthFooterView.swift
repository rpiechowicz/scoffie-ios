import SwiftUI

struct AuthFooterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    var body: some View {
        // Kropka wkleja się w nazwę drugiego przycisku, żeby nie pływała
        // samotnie po gapie HStack-a.
        VStack(spacing: 6) {
            Text("Kontynuując, akceptujesz")
                .font(.system(size: 12))
                .foregroundStyle(Color.scMuted(colorScheme))

            HStack(spacing: 4) {
                Button("Warunki") { showTermsOfService = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.scLabel(colorScheme))

                Text("oraz")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scMuted(colorScheme))

                Button("Politykę prywatności.") { showPrivacyPolicy = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.scLabel(colorScheme))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(title: "Polityka prywatności") {
                PrivacyPolicyContent()
            }
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentSheet(title: "Warunki korzystania") {
                TermsOfServiceContent()
            }
        }
    }
}

// MARK: - Wspólne stałe dokumentów

/// Jedno źródło wersji dokumentów w aplikacji. `documentVersionISO` idzie do
/// dziennika zgód i MUSI zgadzać się z `LEGAL_DOCUMENT_VERSIONS` na serwerze
/// (`src/common/legal-documents.ts`) — wersja z przyszłości jest odrzucana,
/// a starsza niż minimalna nie otwiera bramki asystenta.
enum LegalDocMeta {
    static let version = "1.0"
    static let effectiveDate = "15 września 2026"
    static let documentVersionISO = "2026-09-15"
    static let contactEmail = "support@scoffie.app"
}

// MARK: - Reużywalny kontener sheeta (styl Cozy Kitchen jak w Ustawieniach)

struct LegalDocumentSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.scCanvas(colorScheme))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.scCanvas(colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(SCPalette.terracotta)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Wspólne bloki

/// Nagłówek dokumentu — mini logo + metadane wersji, w karcie jak
/// hero-cardy w Ustawieniach.
private struct LegalHeaderCard: View {
    let intro: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SCSteamingBowlLogo(size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scoffie")
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("Wersja \(LegalDocMeta.version) · Obowiązuje od: \(LegalDocMeta.effectiveDate)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }

            Text(intro)
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}

/// Sekcja dokumentu jako karta w stylu Ustawień: kafelek ikony
/// (`EditorialSettingsTileIcon`) + numerowany tytuł + treść.
private struct LegalSection<Content: View>: View {
    let number: Int
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var scheme

    // Akcenty rotują jak wiersze w Ustawieniach — deterministycznie po
    // numerze sekcji, żeby kolory nie skakały między otwarciami.
    private static var accents: [Color] {
        [SCPalette.terracotta, SCPalette.sage, SCPalette.indigo, SCPalette.butter]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                EditorialSettingsTileIcon(
                    icon: icon,
                    color: Self.accents[(number - 1) % Self.accents.count]
                )

                Text("\(number). \(title)")
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(Color.scMuted(scheme))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}

/// Akapit w sekcji — wymusza pełną wysokość tekstu.
private struct LegalParagraph: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Punktor w stylu list z Ustawień — kropka w kolorze akcentu zamiast "•".
private struct LegalBullet: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(SCPalette.terracotta)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Polityka prywatności
//
// Treść 1:1 z `docs/privacy/index.html` (wersja 1.0, 15 września 2026).
// Zmiana tutaj = zmiana na stronie i podbicie wersji w
// `src/common/legal-documents.ts` na serwerze — inaczej nikt nie zostanie
// poproszony o ponowną akceptację.

struct PrivacyPolicyContent: View {
    var body: some View {
        LegalHeaderCard(
            intro: "Dokument opisuje, jakie dane są przetwarzane w związku z korzystaniem z aplikacji mobilnej Scoffie, skąd pochodzą, komu są przekazywane, jak długo są przechowywane oraz jakie prawa przysługują użytkownikom."
        )

        LegalSection(number: 1, title: "Administrator danych", icon: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Administratorem danych osobowych użytkowników aplikacji Scoffie („Aplikacja”) jest Rafał Piechowicz („Administrator”).")
                LegalParagraph("Kontakt w sprawach dotyczących danych osobowych: \(LegalDocMeta.contactEmail)")
                    .fontWeight(.medium)
            }
        }

        LegalSection(number: 2, title: "Jakie dane przetwarzamy i skąd pochodzą", icon: "tray.full.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Konto (od Apple, przy logowaniu):").fontWeight(.medium)
                LegalBullet("stabilny identyfikator użytkownika Apple (tzw. sub),")
                LegalBullet("adres e-mail, w tym adres relay Apple, jeśli użytkownik wybierze opcję „Ukryj mój e-mail”,")
                LegalBullet("imię i nazwisko, wyłącznie jeśli użytkownik udostępni je przy pierwszym logowaniu.")
                LegalParagraph("Profil (podawane przez użytkownika w kreatorze i Ustawieniach):").fontWeight(.medium)
                LegalBullet("imię wyświetlane i kolor awatara,")
                LegalBullet("sylwetka: płeć, wzrost, waga, rok urodzenia — używane wyłącznie do wyliczenia zapotrzebowania kalorycznego i makroskładników,")
                LegalBullet("cel (np. redukcja, utrzymanie), poziom aktywności, cele kaloryczne i makro,")
                LegalBullet("dieta, alergeny i wykluczone składniki — są to dane dotyczące zdrowia w rozumieniu art. 9 RODO (patrz sekcja 3),")
                LegalBullet("maksymalny czas gotowania, liczba i pory posiłków.")
                LegalParagraph("Gospodarstwo domowe i planowanie:").fontWeight(.medium)
                LegalBullet("nazwa gospodarstwa, lista domowników i ich role, zaproszenia,")
                LegalBullet("plany posiłków, uczestnicy posiłków, oznaczenia zjedzonych posiłków, listy zakupów wraz z historią, własne przepisy i ulubione.")
                LegalParagraph("Asystent AI (jeśli użytkownik z niego korzysta):").fontWeight(.medium)
                LegalBullet("treść wiadomości użytkownika i odpowiedzi asystenta,")
                LegalBullet("propozycje planu i decyzje użytkownika (zatwierdzenie, cofnięcie),")
                LegalBullet("notatki pamięci gospodarstwa — krótkie fakty zapisane przez asystenta na prośbę użytkownika (np. „nie jemy pieczarek”),")
                LegalBullet("zgłoszenia niewłaściwych odpowiedzi — treść zgłoszonej odpowiedzi, powód i komentarz,")
                LegalBullet("dane o użyciu: liczba wiadomości i zapisanych planów, zużyte tokeny i koszt każdej odpowiedzi (do rozliczeń i limitów).")
                LegalParagraph("Zdrowie (Apple Health / HealthKit), jeśli użytkownik włączy tę integrację:").fontWeight(.medium)
                LegalBullet("dzienna liczba kroków z ostatnich 14 dni oraz cel kroków.")
                LegalParagraph("Cookidoo (Thermomix), jeśli użytkownik połączy konto:").fontWeight(.medium)
                LegalBullet("adres e-mail i hasło do konta Cookidoo użytkownika, przechowywane w postaci zaszyfrowanej (patrz sekcja 8).")
                LegalParagraph("Techniczne:").fontWeight(.medium)
                LegalBullet("token urządzenia do powiadomień push (za zgodą na powiadomienia),")
                LegalBullet("logi żądań: identyfikator użytkownika, adres IP, wersja aplikacji, czas i status żądania — bez treści wiadomości do asystenta,")
                LegalBullet("dziennik zgód: rodzaj zgody, wersja dokumentu, data, źródło.")
            }
        }

        LegalSection(number: 3, title: "Cele i podstawy prawne", icon: "target") {
            VStack(alignment: .leading, spacing: 6) {
                LegalBullet("założenie i utrzymanie konta, gospodarstwo, planowanie posiłków, listy zakupów, powiadomienia o zmianach — wykonanie umowy, art. 6 ust. 1 lit. b RODO,")
                LegalBullet("wyliczanie zapotrzebowania i personalizacja propozycji na podstawie profilu i preferencji — wykonanie umowy, art. 6 ust. 1 lit. b RODO,")
                LegalBullet("dieta, alergeny i wykluczone składniki (dane dotyczące zdrowia): przetwarzanie w Aplikacji — na podstawie wyraźnej zgody użytkownika wyrażonej przy ich podaniu (art. 9 ust. 2 lit. a RODO); przekazanie ich do asystenta AI — na podstawie odrębnej, wyraźnej zgody każdej osoby, której dotyczą (sekcja 6),")
                LegalBullet("dane ze Zdrowia (kroki) — zgoda udzielona w systemie iOS przy włączaniu integracji (art. 9 ust. 2 lit. a RODO),")
                LegalBullet("poświadczenia Cookidoo — zgoda wyrażona przy łączeniu konta (art. 6 ust. 1 lit. a RODO),")
                LegalBullet("bezpieczeństwo, wykrywanie nadużyć, limity użycia i ochrona sesji — prawnie uzasadniony interes, art. 6 ust. 1 lit. f RODO,")
                LegalBullet("obsługa zgłoszeń i realizacja praw — art. 6 ust. 1 lit. b i f RODO,")
                LegalBullet("wykazanie udzielonych zgód i akceptacji dokumentów — obowiązek prawny, art. 6 ust. 1 lit. c w zw. z art. 7 ust. 1 RODO.")
                LegalParagraph("Zgody można cofnąć w każdej chwili w Aplikacji (zgoda na asystenta: menu asystenta → „Prywatność i zgoda”; integracje: Ustawienia) lub pisząc do Administratora; cofnięcie nie wpływa na zgodność z prawem przetwarzania sprzed cofnięcia.")
            }
        }

        LegalSection(number: 4, title: "Sign in with Apple i minimalny wiek", icon: "apple.logo") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Logowanie odbywa się wyłącznie przy użyciu Sign in with Apple. Administrator nie otrzymuje hasła do konta Apple. Jeśli użytkownik wybierze opcję „Ukryj mój e-mail”, Apple przekazuje adres relay kierujący wiadomości na prawdziwy adres użytkownika.")
                LegalParagraph("Aplikacja jest przeznaczona dla osób, które ukończyły 16 lat. Osoby młodsze nie powinny zakładać konta ani podawać danych o zdrowiu; użytkownik potwierdza ukończenie 16 lat przy pierwszym uruchomieniu asystenta AI.")
            }
        }

        LegalSection(number: 5, title: "Gospodarstwo domowe — dane o domownikach", icon: "house.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Dołączenie do gospodarstwa jest dobrowolne. Członkowie gospodarstwa współdzielą plan tygodnia, listy zakupów, własne przepisy i ustawienia gospodarstwa i mogą je modyfikować.")
                LegalParagraph("Co widzą o Tobie pozostali domownicy: imię i awatar, dietę, alergeny, wykluczone składniki, cel kaloryczny i makro oraz Twój udział w posiłkach. Te dane są potrzebne, żeby wspólny plan uwzględniał każdego. Sylwetka (wzrost, waga, płeć, rok urodzenia) nie jest udostępniana domownikom ani asystentowi.")
                LegalParagraph("Skąd mamy dane o innych osobach: każdy domownik podaje swoje dane sam, w swoim koncie. Zapraszając kogoś do gospodarstwa, poinformuj tę osobę, jakie dane będą współdzielone. Gospodarstwo można w każdej chwili opuścić w Ustawieniach.")
            }
        }

        LegalSection(number: 6, title: "Asystent AI", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Asystent planowania posiłków działa na modelu językowym Claude dostarczanym przez Anthropic, PBC z siedzibą w Stanach Zjednoczonych, który przetwarza dane na zlecenie Administratora (podmiot przetwarzający). Asystent to program, nie człowiek; jego odpowiedzi mogą zawierać błędy i nie są poradą lekarską ani dietetyczną.")
                LegalParagraph("Co jest wysyłane do Anthropic przy każdej wiadomości:").fontWeight(.medium)
                LegalBullet("treść Twojej wiadomości i dotychczasowej rozmowy,")
                LegalBullet("Twoje imię, dieta, alergeny, wykluczone składniki, cel, wyliczone zapotrzebowanie kaloryczne i makro, maksymalny czas gotowania,")
                LegalBullet("te same dane pozostałych domowników — wyłącznie tych, którzy sami wyrazili zgodę na asystenta; ograniczenia pozostałych (alergeny, wykluczenia) egzekwuje serwer przy zapisie planu bez przekazywania ich danych,")
                LegalBullet("nazwa gospodarstwa, aktualny plan tygodnia i notatki pamięci,")
                LegalBullet("wspólny katalog przepisów.")
                LegalParagraph("Nie jest wysyłane: wzrost, waga, płeć, rok urodzenia, kroki ze Zdrowia, adres e-mail, poświadczenia Cookidoo.")
                LegalParagraph("Podstawa: odrębna, wyraźna zgoda każdej osoby, której dane są przekazywane (art. 9 ust. 2 lit. a RODO), wyrażana przed pierwszą wiadomością i możliwa do cofnięcia w menu asystenta. Po cofnięciu asystent przestaje dla tej osoby działać, a jej dane nie są już wysyłane; zapisane rozmowy pozostają do czasu usunięcia przez użytkownika lub upływu okresu z sekcji 10.")
                LegalParagraph("Przekazanie poza EOG: Anthropic przetwarza dane w Stanach Zjednoczonych. Przekazanie odbywa się na podstawie umowy powierzenia zawierającej standardowe klauzule umowne przyjęte przez Komisję Europejską (art. 46 ust. 2 lit. c RODO). Zgodnie z warunkami usługi API Anthropic nie wykorzystuje przekazywanych danych do trenowania swoich modeli.")
                LegalParagraph("Limity i rozliczenia: liczba wiadomości i zapisanych planów jest liczona na gospodarstwo w okresie rozliczeniowym subskrypcji; koszt każdej odpowiedzi jest zapisywany do rozliczeń i pozostaje po usunięciu rozmowy (bez jej treści).")
            }
        }

        LegalSection(number: 7, title: "Dane ze Zdrowia (Apple Health)", icon: "figure.walk") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Jeśli włączysz integrację, Aplikacja odczytuje z Apple Health wyłącznie dzienną liczbę kroków i przesyła sumy z ostatnich 14 dni na serwer, aby pokazać je w kalendarzu obok posiłków. Aplikacja nie zapisuje niczego do Apple Health.")
                LegalParagraph("Dane ze Zdrowia nie są używane do reklamy ani marketingu, nie są sprzedawane ani udostępniane osobom trzecim, nie są przekazywane do asystenta AI i nie są przechowywane w iCloud Administratora. Integrację wyłączysz w Ustawieniach Aplikacji lub w Ustawieniach iOS → Prywatność i bezpieczeństwo → Zdrowie; wyłączenie w Aplikacji usuwa kopię kroków z serwera, a kroki są też usuwane razem z kontem.")
            }
        }

        LegalSection(number: 8, title: "Integracja z Cookidoo (opcjonalna)", icon: "app.connected.to.app.below.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Funkcja „Gotuj w Thermomixie” pozwala wysłać wybrany przepis do kalendarza „Mój tydzień” w Cookidoo. Wymaga podania adresu e-mail i hasła do konta Cookidoo, które są przechowywane na serwerze Administratora w postaci zaszyfrowanej (AES-256-GCM) i używane wyłącznie do logowania do Cookidoo w imieniu użytkownika. Hasło nigdy nie jest pokazywane ani przekazywane innym domownikom; pozostali domownicy mogą korzystać z połączonego konta i widzą jego adres e-mail.")
                LegalParagraph("Integracja korzysta z nieoficjalnego interfejsu Cookidoo i może przestać działać bez uprzedzenia. Cookidoo i Thermomix są znakami towarowymi Vorwerk; Administrator nie jest powiązany z Vorwerk.")
                LegalParagraph("Połączenie można rozłączyć w Ustawieniach — poświadczenia są wtedy natychmiast usuwane; są też usuwane, gdy osoba, która je podała, opuści gospodarstwo lub usunie konto. Administrator może czasowo wyłączyć integrację.")
            }
        }

        LegalSection(number: 9, title: "Odbiorcy danych", icon: "building.2.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalBullet("Railway Corp. — hosting serwera i bazy danych (infrastruktura Aplikacji),")
                LegalBullet("Cloudflare, Inc. — przechowywanie i serwowanie zdjęć przepisów z katalogu oraz przechowywanie zaszyfrowanych kopii zapasowych bazy danych (kopie zawierają dane osobowe; 30 dni),")
                LegalBullet("GitHub, Inc. (Microsoft) — wykonanie nocnej kopii zapasowej bazy: zrzut przechodzi przez środowisko GitHub Actions i jest usuwane zaraz po wysłaniu do Cloudflare,")
                LegalBullet("Functional Software, Inc. (Sentry) — zbieranie błędów aplikacji i serwera: identyfikator żądania, kod i ścieżka błędu, wersja, identyfikator użytkownika; bez treści wiadomości i danych profilu; serwery w Unii Europejskiej,")
                LegalBullet("Apple Inc. — Sign in with Apple, powiadomienia push, App Store,")
                LegalBullet("Anthropic, PBC — model językowy asystenta AI, w zakresie z sekcji 6, wyłącznie dla osób, które wyraziły zgodę,")
                LegalBullet("Vorwerk (Cookidoo) — wyłącznie jeśli użytkownik połączy konto Cookidoo, w zakresie z sekcji 8,")
                LegalBullet("członkowie gospodarstwa domowego użytkownika, w zakresie z sekcji 5,")
                LegalBullet("podmioty uprawnione na podstawie przepisów prawa.")
            }
        }

        LegalSection(number: 10, title: "Okresy przechowywania", icon: "clock.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalBullet("dane konta, profilu i gospodarstwa — przez czas korzystania z Aplikacji,")
                LegalBullet("rozmowy z asystentem (wraz z propozycjami) — 90 dni od ostatniej wiadomości, potem usuwane automatycznie; wcześniej użytkownik może usunąć każdą rozmowę lub wszystkie naraz,")
                LegalBullet("notatki pamięci gospodarstwa — do usunięcia przez domownika w Ustawieniach lub do usunięcia gospodarstwa (najwyżej 30 notatek),")
                LegalBullet("dane o użyciu asystenta (liczba wiadomości, tokeny, koszt) — 12 miesięcy, bez treści rozmów,")
                LegalBullet("zgłoszenia odpowiedzi asystenta — 12 miesięcy,")
                LegalBullet("kroki ze Zdrowia — przez czas korzystania z integracji, usuwane przy jej wyłączeniu i z kontem,")
                LegalBullet("poświadczenia Cookidoo — do rozłączenia lub usunięcia konta,")
                LegalBullet("historia list zakupów — przez czas korzystania z Aplikacji,")
                LegalBullet("dziennik zgód — przez czas korzystania z Aplikacji, usuwany z kontem,")
                LegalBullet("kopie zapasowe bazy — 30 dni, potem nadpisywane,")
                LegalBullet("logi techniczne — nie dłużej niż 90 dni,")
                LegalBullet("ślad tożsamości zakupowej (pseudonim wyliczony z identyfikatora logowania, bez możliwości odtworzenia go z powrotem) wraz z licznikiem wykorzystanej bezpłatnej próby i zapisem opłaconej subskrypcji — BEZTERMINOWO, także po usunięciu konta. To jedyny ślad, który zostaje. Bez niego bezpłatna próba odnawiałaby się przy każdym nowym koncie, a opłacona subskrypcja nie wróciłaby po ponownym zalogowaniu tym samym Apple ID. Podstawa: prawnie uzasadniony interes (art. 6 ust. 1 lit. f RODO) — zapobieganie nadużyciu bezpłatnej próby i odtworzenie opłaconego świadczenia.")
                LegalBullet("po usunięciu konta dane są usuwane niezwłocznie, nie później niż w ciągu 30 dni (w tym z kopii zapasowych po ich rotacji), z zastrzeżeniem obowiązków prawnych i ochrony roszczeń oraz opisanego wyżej śladu tożsamości zakupowej. Własne przepisy dodane do wspólnego gospodarstwa pozostają w nim (bez powiązania z usuniętym kontem), bo korzystają z nich pozostali domownicy.")
            }
        }

        LegalSection(number: 11, title: "Prawa użytkownika", icon: "checkmark.shield.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Użytkownik ma prawo do:")
                LegalBullet("dostępu do danych i otrzymania ich kopii (Ustawienia → Informacje → „Pobierz moje dane”),")
                LegalBullet("sprostowania danych,")
                LegalBullet("usunięcia danych,")
                LegalBullet("ograniczenia przetwarzania,")
                LegalBullet("przenoszenia danych,")
                LegalBullet("sprzeciwu wobec przetwarzania opartego na uzasadnionym interesie,")
                LegalBullet("cofnięcia każdej zgody w dowolnym momencie,")
                LegalBullet("wniesienia skargi do Prezesa Urzędu Ochrony Danych Osobowych (ul. Stawki 2, 00-193 Warszawa).")
                LegalParagraph("Żądania prosimy kierować na \(LegalDocMeta.contactEmail) z adresu e-mail przypisanego do konta. Odpowiadamy w ciągu 30 dni.")
            }
        }

        LegalSection(number: 12, title: "Usunięcie konta", icon: "trash.fill") {
            LegalParagraph("Konto można usunąć bezpośrednio w Aplikacji: Ustawienia → profil użytkownika → „Usuń konto”. Operacja usuwa konto wraz z profilem, preferencjami, rozmowami z asystentem, krokami, poświadczeniami Cookidoo, tokenami i dziennikiem zgód; przy kontach Apple unieważniane są także tokeny Sign in with Apple. Żądanie usunięcia można też przesłać e-mailem z adresu przypisanego do konta.")
        }

        LegalSection(number: 13, title: "Personalizacja i zautomatyzowane decyzje", icon: "cpu.fill") {
            LegalParagraph("Aplikacja i asystent dopasowują propozycje posiłków do podanych preferencji, celów i ograniczeń (profilowanie w rozumieniu art. 4 pkt 4 RODO). Propozycje nie wywołują wobec użytkownika skutków prawnych ani nie wpływają na niego w podobnie istotny sposób — art. 22 RODO nie ma zastosowania. Każdą propozycję użytkownik zatwierdza lub odrzuca sam.")
        }

        LegalSection(number: 14, title: "Bezpieczeństwo", icon: "lock.fill") {
            LegalParagraph("Administrator stosuje odpowiednie środki techniczne i organizacyjne: szyfrowanie transmisji (HTTPS/TLS), szyfrowanie poświadczeń Cookidoo w bazie, bezpieczne przechowywanie tokenów sesji na urządzeniu, uwierzytelnianie każdego żądania i połączenia, limity żądań oraz ograniczenie danych przekazywanych do asystenta do niezbędnego minimum.")
        }

        LegalSection(number: 15, title: "Zmiany polityki", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Polityka może być aktualizowana w związku ze zmianami prawa lub funkcji Aplikacji. Istotne zmiany (nowy odbiorca danych, nowy cel) wymagają ponownego potwierdzenia w Aplikacji; o pozostałych informujemy w Aplikacji z wyprzedzeniem. Aktualna wersja jest publikowana na stronie scoffie.app.")
                LegalParagraph("W razie pytań napisz na \(LegalDocMeta.contactEmail).")
            }
        }
    }
}

// MARK: - Warunki korzystania
//
// Treść 1:1 z `docs/terms/index.html` (wersja 1.0, 15 września 2026).

struct TermsOfServiceContent: View {
    var body: some View {
        LegalHeaderCard(
            intro: "Niniejsze Warunki korzystania („Warunki”) określają zasady świadczenia usług drogą elektroniczną w aplikacji mobilnej Scoffie („Aplikacja”) oraz prawa i obowiązki użytkowników. Warunki stanowią regulamin w rozumieniu art. 8 ustawy z dnia 18 lipca 2002 r. o świadczeniu usług drogą elektroniczną."
        )

        LegalSection(number: 1, title: "Postanowienia ogólne", icon: "doc.text.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Usługodawcą jest Rafał Piechowicz („Usługodawca”), kontakt: \(LegalDocMeta.contactEmail).")
                LegalParagraph("Użytkownikiem może być osoba fizyczna, która ukończyła 16 lat. Warunkiem korzystania z pełnej funkcjonalności Aplikacji jest zalogowanie się za pomocą Sign in with Apple.")
                LegalParagraph("Umowa o świadczenie usług zostaje zawarta z chwilą pierwszego zalogowania. Akceptacja Warunków i Polityki prywatności jest potwierdzana w Aplikacji i zapisywana wraz z datą i wersją dokumentu.")
            }
        }

        LegalSection(number: 2, title: "Wymagania techniczne", icon: "iphone") {
            VStack(alignment: .leading, spacing: 6) {
                LegalBullet("urządzenie z systemem iOS w wersji obsługiwanej przez aktualne wydanie Aplikacji,")
                LegalBullet("aktywne konto Apple ID z włączonym uwierzytelnianiem dwuskładnikowym,")
                LegalBullet("dostęp do sieci Internet.")
            }
        }

        LegalSection(number: 3, title: "Konto użytkownika", icon: "person.crop.circle.fill") {
            LegalParagraph("Konto zakładane jest automatycznie przy pierwszym logowaniu za pomocą Sign in with Apple. Użytkownik jest zobowiązany do zachowania w poufności dostępu do swojego urządzenia i konta Apple. Z jednego konta Apple może korzystać wyłącznie jeden użytkownik.")
        }

        LegalSection(number: 4, title: "Zakres i charakter usługi", icon: "calendar") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Aplikacja umożliwia w szczególności:")
                LegalBullet("planowanie posiłków w kalendarzu tygodnia — dla siebie i wspólnego gospodarstwa domowego,")
                LegalBullet("korzystanie z bazy przepisów wraz z wartościami odżywczymi (kalorie i makroskładniki),")
                LegalBullet("automatyczne tworzenie list zakupów na podstawie zaplanowanych posiłków,")
                LegalBullet("zarządzanie preferencjami żywieniowymi (dieta, alergeny, wykluczone składniki, liczba i pory posiłków),")
                LegalBullet("przypomnienia o posiłkach oraz powiadomienia o zmianach w planie gospodarstwa,")
                LegalBullet("asystenta AI planującego posiłki (sekcja 5),")
                LegalBullet("opcjonalne integracje: Apple Health (kroki) i Cookidoo (sekcja 7).")
                LegalParagraph("Wartości odżywcze przepisów są wyliczane automatycznie ze składników i mają charakter szacunkowy. Informacje o alergenach pochodzą z oznaczeń składników katalogu i mogą być niepełne — w przypadku alergii użytkownik zawsze weryfikuje skład samodzielnie.")
                LegalParagraph("Propozycje posiłków oraz sugestie żywieniowe mają charakter wyłącznie informacyjny i nie zastępują porady lekarza, dietetyka ani specjalisty. Użytkownik samodzielnie ocenia, czy dany plan jest dla niego odpowiedni, w szczególności biorąc pod uwagę alergie, nietolerancje pokarmowe i indywidualny stan zdrowia.")
            }
        }

        LegalSection(number: 5, title: "Asystent AI", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Asystent to funkcja oparta na modelu językowym dostarczanym przez Anthropic, PBC. Użytkownik rozmawia z programem, nie z człowiekiem. Odpowiedzi są generowane automatycznie i mogą być niepełne lub błędne; Usługodawca nie gwarantuje ich poprawności. Propozycje planu użytkownik zatwierdza lub odrzuca sam — asystent nie zmienia planu bez zatwierdzenia, chyba że użytkownik świadomie włączy tryb zapisu bezpośredniego.")
                LegalParagraph("Korzystanie z asystenta wymaga odrębnej zgody na przekazanie danych o diecie i alergiach do Anthropic (Polityka prywatności, sekcja 6). Dane innych domowników są przekazywane wyłącznie za ich własną zgodą.")
                LegalParagraph("Limity. Liczba wiadomości i zapisanych planów jest ograniczona na gospodarstwo w każdym okresie rozliczeniowym. Pula odnawia się w dniu odnowienia subskrypcji — kupiona 15 września wraca 15 października, a nie pierwszego. Na bezpłatnej próbie pula jest jednorazowa i nie odnawia się wcale. Aktualny stan i datę odnowienia pokazuje Aplikacja. Usługodawca może czasowo ograniczyć lub wstrzymać asystenta (np. z powodu kosztów lub awarii dostawcy) — pozostałe funkcje Aplikacji działają wtedy bez zmian.")
                LegalParagraph("Treści. Zabronione jest używanie asystenta do celów niezgodnych z prawem, do obchodzenia zabezpieczeń Aplikacji lub do generowania treści niezwiązanych z planowaniem posiłków. Niewłaściwą odpowiedź asystenta można zgłosić Usługodawcy („Zgłoś odpowiedź” w Aplikacji lub e-mailem).")
                LegalParagraph("Odpłatność. Asystent działa w dwóch trybach: bezpłatna próba i płatny plan. Próba to jednorazowa, niewielka pula wiadomości i zapisów planu, przypisana do osoby (nie do gospodarstwa) i nieodnawialna. Dalsze korzystanie wymaga wykupienia planu.")
                LegalParagraph("Plany. Solo (29,99 zł/mies.), We dwoje (39,99 zł/mies.) i Rodzina (49,99 zł/mies.). Różnią się wyłącznie wielkością puli wiadomości i zapisanych planów na okres rozliczeniowy — nie liczbą osób w gospodarstwie i nie zakresem funkcji. Aktualne limity każdego planu pokazuje Aplikacja przed zakupem oraz App Store w opisie produktu.")
                LegalParagraph("Pula jest wspólna dla całego gospodarstwa. Wykupienie planu przez jednego domownika daje asystenta wszystkim pozostałym, bez dokupywania miejsc i bez żadnej dodatkowej czynności; wszyscy korzystają z tej samej puli. Opuszczenie gospodarstwa przez płatnika kończy dostęp pozostałych z tego samego dnia.")
                LegalParagraph("Odnowienie i rezygnacja. Subskrypcja odnawia się automatycznie co miesiąc, dopóki nie zostanie anulowana co najmniej 24 godziny przed końcem bieżącego okresu. Opłata jest pobierana przez Apple w ciągu 24 godzin przed początkiem nowego okresu. Subskrypcją zarządza się w Ustawieniach iOS (Apple ID → Subskrypcje) albo przyciskiem „Zarządzaj subskrypcją” w Aplikacji; usunięcie Aplikacji ani konta w Aplikacji NIE anuluje subskrypcji.")
                LegalParagraph("Zakup i zwroty realizuje wyłącznie Apple; Usługodawca nie otrzymuje danych karty ani adresu rozliczeniowego. Reklamacje dotyczące płatności rozpatruje Apple zgodnie ze swoim regulaminem, a jeżeli Apple zwróci opłatę, dostęp do płatnych limitów wygasa.")
                LegalParagraph("Zmiana warunków. Usługodawca może podnieść limity planu w każdej chwili — ze skutkiem natychmiastowym i dla wszystkich, którzy już płacą. Obniżenie limitu albo podwyżka ceny NIE dotyczy trwającego okresu rozliczeniowego; obowiązuje najwcześniej od kolejnego odnowienia i wymaga wcześniejszej informacji, którą można odrzucić rezygnując z subskrypcji.")
                LegalParagraph("Prawo odstąpienia. Zakup jest treścią cyfrową dostarczaną natychmiast. Rozpoczynając korzystanie z płatnych limitów przed upływem 14 dni, konsument żąda rozpoczęcia świadczenia przed terminem odstąpienia i przyjmuje do wiadomości, że traci prawo odstąpienia od umowy (art. 38 pkt 13 ustawy o prawach konsumenta). Nie wyłącza to zwrotów realizowanych dobrowolnie przez Apple.")
            }
        }

        LegalSection(number: 6, title: "Gospodarstwa domowe", icon: "house.fill") {
            LegalParagraph("Użytkownik może utworzyć wspólne gospodarstwo domowe i zapraszać do niego innych użytkowników. Członkowie gospodarstwa współdzielą plan tygodnia, listy zakupów, własne przepisy i ustawienia gospodarstwa i mogą je modyfikować. Zapraszając kogoś, użytkownik przyjmuje do wiadomości, że zaproszeni będą widzieć wspólne dane, w tym jego dietę i alergeny, i zobowiązuje się poinformować o tym zapraszaną osobę. Opuszczenie gospodarstwa przez ostatniego członka usuwa gospodarstwo wraz z planami i listami. Zakres współdzielonych danych opisuje Polityka prywatności.")
        }

        LegalSection(number: 7, title: "Integracje zewnętrzne", icon: "app.connected.to.app.below.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Apple Health. Za zgodą udzieloną w iOS Aplikacja odczytuje liczbę kroków. Integrację można wyłączyć w każdej chwili.")
                LegalParagraph("Cookidoo (Thermomix). Funkcja jest opcjonalna i korzysta z nieoficjalnego interfejsu Cookidoo. Łącząc konto, użytkownik przekazuje Usługodawcy swoje dane logowania do Cookidoo (przechowywane w postaci zaszyfrowanej) i sam odpowiada za zgodność takiego użycia z regulaminem Cookidoo. Funkcja może przestać działać bez uprzedzenia lub zostać wyłączona przez Usługodawcę; nie stanowi to nienależytego wykonania umowy. Cookidoo i Thermomix są znakami towarowymi Vorwerk; Usługodawca nie jest powiązany z Vorwerk.")
            }
        }

        LegalSection(number: 8, title: "Zasady korzystania", icon: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Zabronione jest w szczególności:")
                LegalBullet("dostarczanie treści o charakterze bezprawnym, w tym naruszających dobra osobiste lub prawa własności intelektualnej osób trzecich,")
                LegalBullet("zakłócanie funkcjonowania Aplikacji, próby nieautoryzowanego dostępu, inżynieria wsteczna chronionych części systemu,")
                LegalBullet("tworzenie wielu kont lub gospodarstw w celu obejścia limitów,")
                LegalBullet("używanie Aplikacji do działalności komercyjnej bez odrębnej zgody Usługodawcy.")
            }
        }

        LegalSection(number: 9, title: "Własność intelektualna", icon: "c.circle.fill") {
            LegalParagraph("Prawa do Aplikacji, w tym kodu, grafik, logotypów i katalogu przepisów, przysługują Usługodawcy lub licencjodawcom. Użytkownik otrzymuje niewyłączną, nieprzenoszalną, odwołalną licencję na korzystanie z Aplikacji na własnym urządzeniu. Treści utworzone przez użytkownika (plany, listy, własne przepisy, notatki) pozostają jego własnością; własne przepisy dodane do wspólnego gospodarstwa pozostają w nim po usunięciu konta autora.")
        }

        LegalSection(number: 10, title: "Odpowiedzialność", icon: "exclamationmark.shield.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Usługodawca dokłada należytej staranności, aby Aplikacja działała prawidłowo, nie gwarantuje jednak nieprzerwanej, wolnej od błędów dostępności, w szczególności w przypadku siły wyższej, awarii sieci, usług Apple lub dostawcy modelu AI.")
                LegalParagraph("Usługodawca nie odpowiada za szkody wynikłe z nieprawidłowego korzystania z Aplikacji, z decyzji żywieniowych podjętych na podstawie propozycji Aplikacji lub asystenta, z działań członków gospodarstwa zaproszonych przez użytkownika, z działania integracji zewnętrznych ani z utraty danych spowodowanej działaniem użytkownika lub osób trzecich. Odpowiedzialność wobec konsumentów nie jest wyłączona ani ograniczona w zakresie, w jakim bezwzględnie obowiązujące przepisy na to nie pozwalają.")
            }
        }

        LegalSection(number: 11, title: "Reklamacje", icon: "envelope.fill") {
            LegalParagraph("Reklamacje można składać na adres \(LegalDocMeta.contactEmail). Reklamacja powinna zawierać imię, adres e-mail, opis problemu oraz oczekiwany sposób rozpatrzenia. Usługodawca rozpatruje reklamacje w terminie 14 dni, informując o wyniku drogą elektroniczną.")
        }

        LegalSection(number: 12, title: "Rozwiązanie umowy i usunięcie konta", icon: "trash.fill") {
            LegalParagraph("Użytkownik może w każdej chwili zakończyć korzystanie z Aplikacji i usunąć konto w Aplikacji (Ustawienia → profil użytkownika → „Usuń konto”) albo zgodnie z procedurą z Polityki prywatności. Usługodawca może zablokować lub usunąć konto w przypadku rażącego naruszenia Warunków, po uprzednim bezskutecznym wezwaniu do zaprzestania naruszeń, z wyjątkiem przypadków wymagających natychmiastowej reakcji ze względu na bezpieczeństwo.")
        }

        LegalSection(number: 13, title: "Odstąpienie od umowy", icon: "arrow.uturn.backward.circle.fill") {
            LegalParagraph("Konsumentowi przysługuje prawo odstąpienia od umowy o świadczenie usług drogą elektroniczną w terminie 14 dni od dnia jej zawarcia, bez podania przyczyny — oświadczenie można złożyć w dowolnej formie, w szczególności e-mailem. Rozpoczęcie korzystania z Aplikacji przed upływem tego terminu następuje na wyraźne żądanie konsumenta; prawo odstąpienia nie przysługuje, jeżeli usługa została w pełni wykonana za wyraźną zgodą konsumenta poinformowanego o utracie tego prawa.")
        }

        LegalSection(number: 14, title: "Zmiany Warunków", icon: "arrow.triangle.2.circlepath") {
            LegalParagraph("Usługodawca może zmienić Warunki z ważnych powodów (zmiana prawa, zakresu lub charakteru usługi, względy bezpieczeństwa). O zmianach użytkownicy zostaną poinformowani w Aplikacji z co najmniej 14-dniowym wyprzedzeniem; istotne zmiany wymagają ponownej akceptacji. Brak akceptacji uprawnia użytkownika do rozwiązania umowy i usunięcia konta.")
        }

        LegalSection(number: 15, title: "Prawo właściwe i spory", icon: "building.columns.fill") {
            LegalParagraph("W sprawach nieuregulowanych Warunkami stosuje się prawo polskie. Sądem właściwym jest sąd właściwy miejscowo dla Usługodawcy, z zastrzeżeniem bezwzględnie obowiązujących przepisów dotyczących konsumentów. Konsument może skorzystać z pozasądowych sposobów rozpatrywania reklamacji, w szczególności z platformy ODR: ec.europa.eu/consumers/odr.")
        }
    }
}

#Preview("Stopka logowania") {
    AuthFooterView()
        .padding()
}
