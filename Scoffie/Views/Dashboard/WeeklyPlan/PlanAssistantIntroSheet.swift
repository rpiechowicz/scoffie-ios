import SwiftUI

// „Ułożę Ci ten tydzień” — arkusz zachęty asystenta przy pustym tygodniu.
//
// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html”, artboard E+
// (`components/plan-v2-empty.jsx`, `P2AssistIntroSheet`).
//
// Arkusz pokazuje się TYLKO wtedy, gdy w całym tygodniu nic nie stoi. Przy dniu
// częściowym przycisk asystenta w nagłówku dnia otwiera asystenta od razu:
// ktoś, kto ma już połowę tygodnia, wie, co asystent robi, i ekran zachęty
// byłby dla niego wyłącznie jednym stuknięciem więcej.
struct PlanAssistantIntroSheet: View {
    let members: [HouseholdMemberSnapshot]
    /// Dni bieżącego tygodnia — podpisy pod podglądem „tak może wyglądać”.
    let days: [Date]
    /// Ile posiłków dziennie planuje to gospodarstwo — z tego liczy się
    /// obietnica „21 posiłków”, żeby nie obiecywać trzech, gdy dom planuje pięć.
    let slotsPerDay: Int
    /// Czy w widocznym tygodniu stoi już cokolwiek. Zmienia obietnicę, a nie
    /// samą planszę: „ułożę” brzmi jak groźba nadpisania komuś, kto ma już
    /// pół tygodnia rozpisane ręcznie.
    var weekIsEmpty: Bool = true
    let onOpenAssistant: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

    /// Siedem dań pod podgląd tygodnia — losowane RAZ, przy otwarciu arkusza.
    ///
    /// Prawdziwe zdjęcia z katalogu, a nie kafle z ikonami: obietnica „tak może
    /// wyglądać Twój tydzień” pokazana kolorowymi prostokątami brzmi jak zrzut
    /// ekranu z wersji demo. Losowanie siedzi w `@State`, żeby dania nie
    /// przetasowywały się przy każdym przerysowaniu widoku.
    @State private var sample: [Recipe] = []

    /// Wejście treści: delikatny stagger po otwarciu arkusza. Sam arkusz
    /// wjeżdża systemowo, więc tu chodzi tylko o to, żeby zawartość nie
    /// pojawiła się gotowa w pierwszej klatce.
    @State private var appeared = false

    private var isSolo: Bool { members.count <= 1 }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        intro
                            .frame(maxWidth: .infinity)
                            .stagger(appeared, step: 0)

                        sectionLabel("JAK DOBIERAM")
                            .padding(.top, 28)
                            .stagger(appeared, step: 1)

                        VStack(spacing: 8) {
                            ForEach(Array(howRows.enumerated()), id: \.element.title) { index, row in
                                howCard(row)
                                    .stagger(appeared, step: 2 + index)
                            }
                        }
                        .padding(.top, 10)

                        previewHeader
                            .padding(.top, 26)
                            .stagger(appeared, step: 5)

                        previewStrip
                            .padding(.top, 10)
                            .stagger(appeared, step: 6)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .padding(.top, 24)
        }
        .task {
            // Jedna klatka opóźnienia — bez niej stan zmienia się w tej samej
            // klatce, w której widok powstaje, i animacji nie ma czego złapać.
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation { appeared = true }
        }
        .task {
            await recipeCatalogStore.loadIfNeeded()
            guard sample.isEmpty else { return }
            sample = Self.pickSample(from: recipeCatalogStore.recipes)
        }
    }

    /// Siedem dań do podglądu — z tasowania, ale bez powtórki dwa razy pod rząd,
    /// dopóki jest z czego wybierać. Gdy katalog ma mniej niż siedem pozycji
    /// z okładką, worek napełnia się od nowa; przy pustym katalogu zostają
    /// kafle schematyczne.
    private static func pickSample(from recipes: [Recipe]) -> [Recipe] {
        let withImages = recipes.filter { $0.imageURL != nil }
        let pool = withImages.isEmpty ? recipes : withImages
        guard !pool.isEmpty else { return [] }

        var picked: [Recipe] = []
        var bag: [Recipe] = []
        while picked.count < 7 {
            if bag.isEmpty { bag = pool.shuffled() }
            picked.append(bag.removeFirst())
        }
        return picked
    }

    // MARK: - Nagłówek

    private var intro: some View {
        VStack(spacing: 0) {
            // 72 pt, nie 52: to jedyny znak graficzny na całym arkuszu i on
            // ma nieść „to robi asystent”, zanim ktokolwiek przeczyta tytuł.
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: SCPalette.terracotta.opacity(0.35), radius: 22, x: 0, y: 10)

                Image(systemName: MenuConstans.Assistant.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
            .padding(.top, 6)

            Text(weekIsEmpty ? "Ułożę Ci ten tydzień" : "Uzupełnię ten tydzień")
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            Text(introSubtitle)
                .font(.system(size: 14.5, weight: .regular))
                .tracking(-0.2)
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .frame(maxWidth: 300)
                .padding(.top, 8)
        }
    }

    private var introSubtitle: String {
        // Bez obietnicy „nie ruszę tego, co stoi": arkusz nie wie, co asystent
        // zrobi z już zaplanowanym dniem, a obietnica, której nie da się tu
        // dotrzymać, jest gorsza od jej braku.
        guard weekIsEmpty else {
            return "Powiedz, czego brakuje, a dopiszę resztę tygodnia. Każdy posiłek zmienisz potem jednym ruchem."
        }
        return isSolo
            ? "Kilka sekund i masz 7 dni posiłków. Każdy możesz potem zmienić jednym ruchem."
            : "Kilka sekund i masz 7 dni posiłków dla całego domu. Każdy możesz potem zmienić jednym ruchem."
    }

    // MARK: - Jak dobieram

    private struct HowRow {
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let showsMembers: Bool
    }

    private var howRows: [HowRow] {
        [
            HowRow(
                icon: "person.2.fill",
                color: SCPalette.sage,
                title: isSolo ? "Pod Twój profil" : "Pod domowników",
                subtitle: membersSubtitle,
                showsMembers: !isSolo
            ),
            HowRow(
                icon: "clock.fill",
                color: SCPalette.butter,
                title: isSolo ? "Pod Twój rytm" : "Pod Wasz rytm",
                subtitle: "W tygodniu szybko, do 30 minut. W weekend coś, przy czym można się zatrzymać.",
                showsMembers: false
            ),
            HowRow(
                icon: "heart.fill",
                color: SCPalette.terracotta,
                title: isSolo ? "Pod Twoje smaki" : "Pod Wasze smaki",
                subtitle: "Ulubione wracają, sezonowe składniki, żadnych powtórek dwa dni pod rząd.",
                showsMembers: false
            )
        ]
    }

    /// Imiona domowników wprost w zdaniu — obietnica robi się sprawdzalna
    /// dopiero wtedy, gdy widać w niej swój dom, a nie „gospodarstwo”.
    private var membersSubtitle: String {
        let names = members
            .prefix(3)
            .map { HouseholdMemberStyle.shortName($0.displayName) }
        guard !names.isEmpty else {
            return "Alergeny i wykluczenia domowników z ustawień — każdy dostaje swoje."
        }
        let list = names.joined(separator: ", ")
        let tail = members.count > 3 ? " i reszta domu" : ""
        return "\(list)\(tail) — każdy dostaje swoje, bez osobnego gotowania, gdy się da."
    }

    private func howCard(_ row: HowRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(row.color.opacity(scheme == .dark ? 0.16 : 0.14))
                Image(systemName: row.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(row.color)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if row.showsMembers { memberStack }
                }

                Text(row.subtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .tracking(-0.1)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private var memberStack: some View {
        HStack(spacing: -7) {
            ForEach(members.prefix(3), id: \.id) { member in
                MemberAvatar(member: member, members: members, size: 22)
                    .overlay(Circle().stroke(Color.scPageBase(scheme), lineWidth: 1.5))
            }
        }
        .fixedSize()
    }

    // MARK: - Podgląd tygodnia

    private var previewHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sectionLabel("TAK MOŻE WYGLĄDAĆ")

            Spacer(minLength: 4)

            Text("przykład · \(7 * max(1, slotsPerDay)) posiłków + lista zakupów")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.scFaint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Siedem dni z prawdziwymi daniami z katalogu.
    ///
    /// Kafle z ikonami stały tu wcześniej dlatego, że aplikacja nie zna planu,
    /// którego ten podgląd dotyczy — ale przez to obietnica „tak może wyglądać
    /// Twój tydzień” wyglądała jak zrzut z wersji demo. Losowe dania z KATALOGU
    /// niczego nie obiecują (podpis obok mówi „przykład”), a pokazują jedzenie,
    /// które ta apka naprawdę ma. Kafel schematyczny zostaje jako zapas na
    /// pusty katalog i przepis bez okładki.
    private var previewStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.prefix(7).enumerated()), id: \.element) { index, day in
                VStack(spacing: 6) {
                    // Kwadrat bierze się z przezroczystej podkładki, a nie
                    // z `aspectRatio` nałożonego wprost na zdjęcie: zdjęcie
                    // w trybie `fill` samo nie ma proporcji, którą da się
                    // zmierzyć, więc kolumna nie wiedziałaby, jak wysoka być.
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { previewTile(index) }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(Self.dayLabel(day))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func previewTile(_ index: Int) -> some View {
        if index < sample.count, let url = sample[index].imageURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    schematicTile(index)
                }
            }
        } else {
            schematicTile(index)
        }
    }

    private func schematicTile(_ index: Int) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Self.tileAccent(index).opacity(scheme == .dark ? 0.34 : 0.26),
                    Self.tileAccent(index).opacity(scheme == .dark ? 0.14 : 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: Self.tileIcon(index))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Self.tileAccent(index))
        }
    }

    /// „PON”, „WT” — `pl_PL` skraca dni z kropką („pon.”), której podpis
    /// pod kaflem nie nosi.
    private static func dayLabel(_ day: Date) -> String {
        shortDayFormatter
            .string(from: day)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    private static func tileAccent(_ index: Int) -> Color {
        [SCPalette.butter, SCPalette.sage, SCPalette.indigo][index % 3]
    }

    private static func tileIcon(_ index: Int) -> String {
        ["sunrise.fill", "fork.knife", "moon.stars.fill"][index % 3]
    }

    // MARK: - Stopka

    private var footer: some View {
        VStack(spacing: 2) {
            // Ten sam przycisk, co w stopkach pozostałych arkuszy — terakota
            // w wariancie „soft”, bez gradientu i cienia.
            EditorialPrimaryActionButton(
                title: "Przejdź do Asystenta",
                icon: MenuConstans.Assistant.icon
            ) {
                dismiss()
                onOpenAssistant()
            }

            Button {
                dismiss()
            } label: {
                Text("Wolę ułożyć sam")
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.99))
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Wspólne

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Color.scFaint(scheme))
            .lineLimit(1)
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EE"
        return f
    }()
}

// MARK: - Stagger

private extension View {
    /// Kolejne partie treści wchodzą jedna po drugiej, po 40 ms.
    /// Przesunięcie jest małe (10 pt) celowo: to ma być dopięcie ruchu
    /// arkusza, a nie druga animacja obok niego.
    func stagger(_ appeared: Bool, step: Int) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.92)
                    .delay(Double(step) * 0.04),
                value: appeared
            )
    }
}
