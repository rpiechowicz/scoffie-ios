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
                .foregroundStyle(Color.wmMuted(colorScheme))

            HStack(spacing: 4) {
                Button("Warunki") { showTermsOfService = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.wmLabel(colorScheme))

                Text("oraz")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wmMuted(colorScheme))

                Button("Politykę prywatności.") { showPrivacyPolicy = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .underline()
                    .foregroundStyle(Color.wmLabel(colorScheme))
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

private enum LegalDocMeta {
    static let version = "1.1"
    static let effectiveDate = "1 sierpnia 2026"
    static let contactEmail = "support@weekly-meals.app"
}

// MARK: - Reużywalny kontener sheeta (styl Cozy Kitchen jak w Ustawieniach)

private struct LegalDocumentSheet<Content: View>: View {
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
            .background(Color.wmCanvas(colorScheme))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.wmCanvas(colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(WMPalette.terracotta)
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
                WMSteamingBowlLogo(size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Meals")
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text("Wersja \(LegalDocMeta.version) · Obowiązuje od: \(LegalDocMeta.effectiveDate)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }

            Text(intro)
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
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
        [WMPalette.terracotta, WMPalette.sage, WMPalette.indigo, WMPalette.butter]
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
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
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
                .fill(WMPalette.terracotta)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Polityka prywatności

private struct PrivacyPolicyContent: View {
    var body: some View {
        LegalHeaderCard(
            intro: "Niniejsza Polityka prywatności opisuje, jakie dane osobowe są przetwarzane w związku z korzystaniem z aplikacji mobilnej Weekly Meals („Aplikacja”), na jakich podstawach prawnych, w jakich celach oraz jakie prawa przysługują użytkownikom. Dokument został przygotowany w zgodzie z Rozporządzeniem Parlamentu Europejskiego i Rady (UE) 2016/679 z dnia 27 kwietnia 2016 r. („RODO”) oraz ustawą z dnia 10 maja 2018 r. o ochronie danych osobowych."
        )

        LegalSection(number: 1, title: "Administrator danych", icon: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Administratorem danych osobowych użytkowników Aplikacji jest Rafał Piechowicz („Administrator”).")
                LegalParagraph("Kontakt w sprawach dotyczących danych osobowych:")
                LegalParagraph("e-mail: \(LegalDocMeta.contactEmail)")
                    .fontWeight(.medium)
            }
        }

        LegalSection(number: 2, title: "Zakres przetwarzanych danych", icon: "tray.full.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Administrator przetwarza wyłącznie dane niezbędne do świadczenia usługi:")
                LegalBullet("stabilny identyfikator użytkownika Apple (tzw. sub) — otrzymywany od Apple po zalogowaniu;")
                LegalBullet("adres e-mail — prawdziwy albo prywatny adres przekazujący Apple w formacie *@privaterelay.appleid.com, jeżeli użytkownik wybrał opcję „Ukryj mój e-mail”;")
                LegalBullet("imię i nazwisko — wyłącznie jeśli użytkownik udostępni je przy pierwszym logowaniu przez Apple;")
                LegalBullet("dane tworzone w trakcie korzystania z Aplikacji — plany posiłków, listy zakupów i produkty, wybrane przepisy oraz preferencje żywieniowe (dieta, wykluczenia i alergeny, cel, liczba i pory posiłków);")
                LegalBullet("dane gospodarstwa domowego — nazwa gospodarstwa, skład (lista członków) i role, jeżeli użytkownik utworzy wspólne gospodarstwo lub do niego dołączy;")
                LegalBullet("token urządzenia (APNs) — techniczny identyfikator nadawany przez Apple, wykorzystywany wyłącznie do dostarczania powiadomień push;")
                LegalBullet("techniczne logi dostępu (znacznik czasu logowania, identyfikator tokenu sesji) — w celu bezpieczeństwa.")
            }
        }

        LegalSection(number: 3, title: "Cele i podstawy prawne przetwarzania", icon: "target") {
            VStack(alignment: .leading, spacing: 6) {
                LegalBullet("Założenie i utrzymanie konta, świadczenie funkcji Aplikacji (planowanie posiłków, listy zakupów, gospodarstwa, powiadomienia) — art. 6 ust. 1 lit. b RODO (wykonanie umowy);")
                LegalBullet("Zapewnienie bezpieczeństwa Aplikacji, wykrywanie nadużyć, logi techniczne — art. 6 ust. 1 lit. f RODO (prawnie uzasadniony interes Administratora);")
                LegalBullet("Obsługa zgłoszeń i reklamacji — art. 6 ust. 1 lit. b i f RODO;")
                LegalBullet("Wypełnienie obowiązków prawnych (np. odpowiedzi na żądania organów) — art. 6 ust. 1 lit. c RODO.")
            }
        }

        LegalSection(number: 4, title: "Sign in with Apple", icon: "apple.logo") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Logowanie odbywa się wyłącznie za pomocą Sign in with Apple. Administrator nie otrzymuje hasła do konta Apple użytkownika.")
                LegalParagraph("Jeżeli użytkownik wybiera opcję „Ukryj mój e-mail”, Apple udostępnia Administratorowi unikalny adres przekazujący. Wiadomości wysyłane na ten adres są przekierowywane na prawdziwy adres użytkownika przez Apple. Administrator nie zna i nie próbuje odszyfrować prawdziwego adresu.")
                LegalParagraph("Imię i nazwisko są udostępniane przez Apple wyłącznie przy pierwszym logowaniu na dane urządzenie. W przypadku rezygnacji z ich udostępnienia użytkownik jest identyfikowany przez nazwę zastępczą.")
            }
        }

        LegalSection(number: 5, title: "Gospodarstwo domowe — dane współdzielone", icon: "house.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Aplikacja umożliwia prowadzenie wspólnego gospodarstwa domowego. Dołączenie do gospodarstwa jest dobrowolne.")
                LegalParagraph("Jeżeli użytkownik należy do wspólnego gospodarstwa, plan tygodnia, listy zakupów i produkty oraz ustawienia gospodarstwa (np. liczba i pory posiłków) są widoczne dla pozostałych jego członków i mogą być przez nich modyfikowane.")
                LegalParagraph("Imię użytkownika (lub nazwa zastępcza) może być prezentowane pozostałym członkom gospodarstwa — m.in. w powiadomieniach o zmianach w planie („kto zmienił plan”).")
                LegalParagraph("Użytkownik samodzielnie decyduje, kogo zaprasza do gospodarstwa, i może je w każdej chwili opuścić w Ustawieniach Aplikacji.")
            }
        }

        LegalSection(number: 6, title: "Powiadomienia", icon: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Aplikacja może wysyłać powiadomienia push (za pośrednictwem usługi Apple Push Notification service) oraz powiadomienia lokalne — np. przypomnienia o posiłkach i informacje o zmianach w planie gospodarstwa.")
                LegalParagraph("Token urządzenia jest przetwarzany wyłącznie w celu dostarczania powiadomień i jest usuwany wraz z kontem.")
                LegalParagraph("Powiadomienia można w każdej chwili wyłączyć w Ustawieniach Aplikacji lub w ustawieniach systemowych iOS. Aplikacja domyślnie ogranicza wysyłkę powiadomień w porze nocnej.")
            }
        }

        LegalSection(number: 7, title: "Odbiorcy danych", icon: "building.2.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Dane mogą być udostępniane wyłącznie:")
                LegalBullet("Apple Inc. — w zakresie koniecznym do weryfikacji tożsamości przez Sign in with Apple oraz doręczania powiadomień push (Apple działa jako niezależny administrator swoich danych);")
                LegalBullet("członkom gospodarstwa domowego użytkownika — w zakresie opisanym w sekcji 5;")
                LegalBullet("dostawcom infrastruktury (hosting, baza danych) wyłącznie w zakresie koniecznym do utrzymania usługi, na podstawie umów powierzenia przetwarzania;")
                LegalBullet("uprawnionym organom państwowym, jeżeli obowiązek ich przekazania wynika z powszechnie obowiązujących przepisów prawa.")
                LegalParagraph("Dane nie są sprzedawane i nie są wykorzystywane w celach marketingowych podmiotów trzecich. Aplikacja nie zawiera zewnętrznych narzędzi analitycznych ani reklamowych.")
            }
        }

        LegalSection(number: 8, title: "Przekazywanie danych do państw trzecich", icon: "globe.europe.africa.fill") {
            LegalParagraph("Administrator nie przekazuje danych do państw trzecich (poza EOG) w sposób zamierzony. W przypadku, gdy wybrany dostawca infrastruktury lub Apple Inc. realizują przetwarzanie poza EOG, odbywa się to wyłącznie w oparciu o mechanizmy zapewniające odpowiedni poziom ochrony zgodny z rozdziałem V RODO (np. standardowe klauzule umowne).")
        }

        LegalSection(number: 9, title: "Okres przechowywania", icon: "clock.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Dane konta są przechowywane przez cały okres aktywnego korzystania z Aplikacji.")
                LegalParagraph("Po usunięciu konta dane osobowe są usuwane nie później niż w terminie 30 dni, z wyjątkiem tych, których przechowywanie jest wymagane przepisami prawa lub które są niezbędne do ustalenia, dochodzenia lub obrony roszczeń.")
                LegalParagraph("Logi techniczne są przechowywane nie dłużej niż 90 dni.")
            }
        }

        LegalSection(number: 10, title: "Prawa użytkownika", icon: "checkmark.shield.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Zgodnie z RODO użytkownikowi przysługują prawa:")
                LegalBullet("dostępu do danych (art. 15);")
                LegalBullet("sprostowania danych (art. 16);")
                LegalBullet("usunięcia danych — „prawo do bycia zapomnianym” (art. 17);")
                LegalBullet("ograniczenia przetwarzania (art. 18);")
                LegalBullet("przenoszenia danych (art. 20);")
                LegalBullet("sprzeciwu wobec przetwarzania opartego na prawnie uzasadnionym interesie (art. 21).")
                LegalParagraph("W celu realizacji powyższych praw prosimy o kontakt pod adresem: \(LegalDocMeta.contactEmail).")
                LegalParagraph("Użytkownik ma również prawo wniesienia skargi do Prezesa Urzędu Ochrony Danych Osobowych (ul. Stawki 2, 00-193 Warszawa).")
            }
        }

        LegalSection(number: 11, title: "Usunięcie konta", icon: "trash.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Konto można usunąć bezpośrednio w Aplikacji: Ustawienia → profil użytkownika → „Usuń konto”. Operacja usuwa konto wraz z powiązanymi danymi osobowymi.")
                LegalParagraph("Żądanie usunięcia można również przesłać na adres \(LegalDocMeta.contactEmail) z adresu e-mail powiązanego z kontem. Żądanie realizowane jest niezwłocznie, nie później niż w terminie 30 dni.")
            }
        }

        LegalSection(number: 12, title: "Zautomatyzowane podejmowanie decyzji", icon: "cpu.fill") {
            LegalParagraph("Dane osobowe nie są wykorzystywane do zautomatyzowanego podejmowania decyzji wywołujących skutki prawne, w tym do profilowania w rozumieniu art. 22 RODO. Propozycje posiłków opierają się wyłącznie na preferencjach zapisanych przez użytkownika.")
        }

        LegalSection(number: 13, title: "Bezpieczeństwo danych", icon: "lock.fill") {
            LegalParagraph("Administrator stosuje środki techniczne i organizacyjne odpowiednie do ryzyka — w szczególności szyfrowanie transmisji (HTTPS/TLS), przechowywanie tokenów sesji w Apple Keychain, stosowanie kryptograficznie bezpiecznych nonce'ów oraz weryfikację podpisu tokenów tożsamości Apple wobec oficjalnych kluczy publicznych Apple.")
        }

        LegalSection(number: 14, title: "Zmiany polityki", icon: "arrow.triangle.2.circlepath") {
            LegalParagraph("Administrator może zaktualizować niniejszą Politykę prywatności w związku ze zmianami prawa lub funkcjonalności Aplikacji. Istotne zmiany zostaną zakomunikowane w Aplikacji z odpowiednim wyprzedzeniem. Dalsze korzystanie z Aplikacji po wejściu w życie zmian oznacza zapoznanie się z nową wersją dokumentu.")
        }

        Text("W razie pytań dotyczących przetwarzania danych prosimy o kontakt: \(LegalDocMeta.contactEmail).")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.wmFaint(colorSchemeOf))
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
            .padding(.horizontal, 12)
    }

    @Environment(\.colorScheme) private var colorSchemeOf
}

// MARK: - Warunki korzystania

private struct TermsOfServiceContent: View {
    var body: some View {
        LegalHeaderCard(
            intro: "Niniejsze Warunki korzystania („Warunki”) określają zasady świadczenia usług drogą elektroniczną w aplikacji mobilnej Weekly Meals („Aplikacja”) oraz prawa i obowiązki użytkowników. Warunki stanowią regulamin w rozumieniu art. 8 ustawy z dnia 18 lipca 2002 r. o świadczeniu usług drogą elektroniczną."
        )

        LegalSection(number: 1, title: "Postanowienia ogólne", icon: "doc.text.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Usługodawcą jest Rafał Piechowicz („Usługodawca”), kontakt: \(LegalDocMeta.contactEmail).")
                LegalParagraph("Użytkownikiem jest osoba fizyczna korzystająca z Aplikacji. Warunkiem korzystania z pełnej funkcjonalności Aplikacji jest zalogowanie się za pomocą Sign in with Apple.")
                LegalParagraph("Korzystanie z Aplikacji jest równoznaczne z akceptacją Warunków.")
            }
        }

        LegalSection(number: 2, title: "Wymagania techniczne", icon: "iphone") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Do korzystania z Aplikacji wymagane jest:")
                LegalBullet("urządzenie z systemem iOS w wersji obsługiwanej przez aktualne wydanie Aplikacji;")
                LegalBullet("aktywne konto Apple ID z włączonym uwierzytelnianiem dwuskładnikowym;")
                LegalBullet("dostęp do sieci Internet.")
            }
        }

        LegalSection(number: 3, title: "Konto użytkownika", icon: "person.crop.circle.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Konto zakładane jest automatycznie przy pierwszym logowaniu za pomocą Sign in with Apple.")
                LegalParagraph("Użytkownik jest zobowiązany do zachowania w poufności dostępu do swojego urządzenia i konta Apple. Usługodawca nie odpowiada za skutki udostępnienia urządzenia osobom trzecim.")
                LegalParagraph("Z jednego konta Apple może korzystać wyłącznie jeden użytkownik (osoba fizyczna).")
            }
        }

        LegalSection(number: 4, title: "Zakres i charakter usługi", icon: "calendar") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Aplikacja umożliwia w szczególności:")
                LegalBullet("planowanie posiłków w kalendarzu tygodnia — dla siebie i wspólnego gospodarstwa domowego;")
                LegalBullet("korzystanie z bazy przepisów wraz z wartościami odżywczymi (kalorie i makroskładniki);")
                LegalBullet("automatyczne tworzenie list zakupów na podstawie zaplanowanych posiłków;")
                LegalBullet("zarządzanie preferencjami żywieniowymi (dieta, wykluczenia i alergeny, liczba i pory posiłków);")
                LegalBullet("przypomnienia o posiłkach oraz powiadomienia o zmianach w planie gospodarstwa.")
                LegalParagraph("Wartości odżywcze przepisów są wyliczane automatycznie ze składników i mają charakter szacunkowy.")
                LegalParagraph("Propozycje posiłków oraz sugestie żywieniowe mają charakter wyłącznie informacyjny i nie zastępują porady lekarza, dietetyka ani specjalisty. Użytkownik powinien samodzielnie ocenić, czy dany plan jest dla niego odpowiedni, w szczególności biorąc pod uwagę alergie, nietolerancje pokarmowe i indywidualny stan zdrowia.")
            }
        }

        LegalSection(number: 5, title: "Gospodarstwa domowe", icon: "house.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Użytkownik może utworzyć wspólne gospodarstwo domowe i zapraszać do niego innych użytkowników. Członkowie gospodarstwa współdzielą plan tygodnia, listy zakupów i produkty oraz ustawienia gospodarstwa i mogą je modyfikować.")
                LegalParagraph("Użytkownik samodzielnie decyduje, kogo zaprasza do gospodarstwa, i przyjmuje do wiadomości, że zaproszeni członkowie będą widzieć wspólne dane. Gospodarstwo można w każdej chwili opuścić w Ustawieniach Aplikacji.")
                LegalParagraph("Zakres danych współdzielonych w gospodarstwie opisuje Polityka prywatności.")
            }
        }

        LegalSection(number: 6, title: "Zasady korzystania", icon: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Użytkownik zobowiązuje się do korzystania z Aplikacji zgodnie z prawem, dobrymi obyczajami oraz niniejszymi Warunkami. Zabronione jest w szczególności:")
                LegalBullet("dostarczanie treści o charakterze bezprawnym, w tym naruszających dobra osobiste lub prawa własności intelektualnej osób trzecich;")
                LegalBullet("podejmowanie działań mających na celu zakłócenie funkcjonowania Aplikacji, w tym ataków DoS, prób uzyskania nieautoryzowanego dostępu, inżynierii wstecznej chronionych części systemu;")
                LegalBullet("tworzenie wielu kont w celu obejścia ograniczeń;")
                LegalBullet("używanie Aplikacji do działalności komercyjnej bez odrębnej zgody Usługodawcy.")
            }
        }

        LegalSection(number: 7, title: "Własność intelektualna", icon: "c.circle.fill") {
            LegalParagraph("Wszelkie prawa własności intelektualnej do Aplikacji, w tym kodu źródłowego, grafik, logotypów i treści, przysługują Usługodawcy lub podmiotom, z których licencji korzysta Usługodawca. Użytkownik otrzymuje niewyłączną, nieprzenoszalną, odwołalną licencję na korzystanie z Aplikacji na własnym urządzeniu w zakresie jej przeznaczenia. Treści utworzone przez użytkownika (plany, listy, preferencje) pozostają jego własnością.")
        }

        LegalSection(number: 8, title: "Odpowiedzialność", icon: "exclamationmark.shield.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Usługodawca dokłada należytej staranności, aby Aplikacja działała prawidłowo. Usługodawca nie gwarantuje jednak nieprzerwanej, wolnej od błędów dostępności Aplikacji, w szczególności w przypadku siły wyższej, awarii sieci operatorów telekomunikacyjnych lub usług Apple.")
                LegalParagraph("Usługodawca nie odpowiada za szkody wynikłe z nieprawidłowego korzystania z Aplikacji, decyzji żywieniowych podjętych przez użytkownika na podstawie propozycji Aplikacji, działań członków gospodarstwa zaproszonych przez użytkownika ani z utraty danych spowodowanej działaniem użytkownika lub osób trzecich.")
                LegalParagraph("Odpowiedzialność wobec konsumentów nie jest wyłączona ani ograniczona w zakresie, w jakim przepisy bezwzględnie obowiązujące na to nie pozwalają.")
            }
        }

        LegalSection(number: 9, title: "Reklamacje", icon: "envelope.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Reklamacje dotyczące Aplikacji można składać na adres: \(LegalDocMeta.contactEmail).")
                LegalParagraph("Reklamacja powinna zawierać imię, adres e-mail, opis problemu oraz oczekiwany sposób rozpatrzenia.")
                LegalParagraph("Usługodawca rozpatruje reklamacje w terminie 14 dni od ich otrzymania, informując o wyniku drogą elektroniczną.")
            }
        }

        LegalSection(number: 10, title: "Rozwiązanie umowy i usunięcie konta", icon: "trash.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("Użytkownik może w każdej chwili zakończyć korzystanie z Aplikacji i usunąć konto — bezpośrednio w Aplikacji (Ustawienia → profil użytkownika → „Usuń konto”) albo zgodnie z procedurą opisaną w Polityce prywatności.")
                LegalParagraph("Usługodawca może zablokować lub usunąć konto użytkownika w przypadku rażącego naruszenia Warunków, po uprzednim bezskutecznym wezwaniu do zaprzestania naruszeń, z wyjątkiem przypadków, w których natychmiastowa reakcja jest konieczna ze względu na bezpieczeństwo innych użytkowników lub Aplikacji.")
            }
        }

        LegalSection(number: 11, title: "Odstąpienie od umowy", icon: "arrow.uturn.backward.circle.fill") {
            LegalParagraph("Konsumentowi w rozumieniu art. 22(1) Kodeksu cywilnego przysługuje prawo odstąpienia od umowy o świadczenie usług drogą elektroniczną w terminie 14 dni od dnia jej zawarcia, bez podania przyczyny. Oświadczenie o odstąpieniu można złożyć w dowolnej formie, w szczególności drogą elektroniczną na adres \(LegalDocMeta.contactEmail). Prawo odstąpienia nie przysługuje, jeżeli świadczenie usługi zostało w pełni wykonane za wyraźną zgodą konsumenta, który został poinformowany o utracie tego prawa.")
        }

        LegalSection(number: 12, title: "Zmiany Warunków", icon: "arrow.triangle.2.circlepath") {
            LegalParagraph("Usługodawca może zmienić Warunki z ważnych powodów (zmiana prawa, zmiana zakresu lub charakteru usługi, względy bezpieczeństwa). O zmianach użytkownicy zostaną poinformowani w Aplikacji z co najmniej 14-dniowym wyprzedzeniem. Brak akceptacji zmian uprawnia użytkownika do rozwiązania umowy i usunięcia konta.")
        }

        LegalSection(number: 13, title: "Prawo właściwe i spory", icon: "building.columns.fill") {
            VStack(alignment: .leading, spacing: 6) {
                LegalParagraph("W sprawach nieuregulowanych Warunkami zastosowanie mają przepisy prawa polskiego.")
                LegalParagraph("Sądem właściwym do rozstrzygania sporów jest sąd właściwy miejscowo dla Usługodawcy, z zastrzeżeniem bezwzględnie obowiązujących przepisów dotyczących konsumentów.")
                LegalParagraph("Konsument może skorzystać z pozasądowych sposobów rozpatrywania reklamacji i dochodzenia roszczeń, w szczególności za pośrednictwem platformy ODR Komisji Europejskiej dostępnej pod adresem: https://ec.europa.eu/consumers/odr/.")
            }
        }

        LegalSection(number: 14, title: "Kontakt", icon: "bubble.left.and.bubble.right.fill") {
            LegalParagraph("Pytania dotyczące Warunków prosimy kierować na adres: \(LegalDocMeta.contactEmail).")
        }
    }
}

#Preview("Footer") {
    AuthFooterView()
        .padding()
}

#Preview("Privacy Policy") {
    LegalDocumentSheet(title: "Polityka prywatności") {
        PrivacyPolicyContent()
    }
}

#Preview("Terms of Service") {
    LegalDocumentSheet(title: "Warunki korzystania") {
        TermsOfServiceContent()
    }
}
