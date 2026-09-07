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
    let onOpenAssistant: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

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
                            .padding(.top, 22)
                            .stagger(appeared, step: 1)

                        VStack(spacing: 6) {
                            ForEach(Array(howRows.enumerated()), id: \.element.title) { index, row in
                                howCard(row)
                                    .stagger(appeared, step: 2 + index)
                            }
                        }
                        .padding(.top, 8)

                        previewHeader
                            .padding(.top, 18)
                            .stagger(appeared, step: 5)

                        previewStrip
                            .padding(.top, 8)
                            .stagger(appeared, step: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .padding(.top, 18)
        }
        .task {
            // Jedna klatka opóźnienia — bez niej stan zmienia się w tej samej
            // klatce, w której widok powstaje, i animacji nie ma czego złapać.
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation { appeared = true }
        }
    }

    // MARK: - Nagłówek

    private var intro: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: SCPalette.terracotta.opacity(0.35), radius: 16, x: 0, y: 6)

                Image(systemName: MenuConstans.Assistant.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            Text("Ułożę Ci ten tydzień")
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text(introSubtitle)
                .font(.system(size: 14.5, weight: .regular))
                .tracking(-0.2)
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
                .padding(.top, 6)
        }
    }

    private var introSubtitle: String {
        isSolo
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
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(row.color.opacity(scheme == .dark ? 0.16 : 0.14))
                Image(systemName: row.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(row.color)
            }
            .frame(width: 34, height: 34)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scCardSurface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scCardStroke(scheme), lineWidth: 1)
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

    /// Siedem kafli w akcentach pór dnia — schemat, nie zdjęcia.
    ///
    /// Makieta ma tu wycinki prawdziwych dań, ale aplikacja nie zna jeszcze
    /// planu, którego ten podgląd dotyczy. Wymyślone zdjęcia obiecywałyby
    /// konkretne przepisy, więc zostaje rytm tygodnia: siedem dni, ciepłe
    /// kafle, dzisiaj podświetlone.
    private var previewStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.prefix(7).enumerated()), id: \.element) { index, day in
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Self.tileAccent(index).opacity(scheme == .dark ? 0.34 : 0.26),
                                        Self.tileAccent(index).opacity(scheme == .dark ? 0.14 : 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: Self.tileIcon(index))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Self.tileAccent(index))
                    }
                    .aspectRatio(1, contentMode: .fit)

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
            Button {
                dismiss()
                onOpenAssistant()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: MenuConstans.Assistant.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text("Przejdź do Asystenta")
                        .font(.system(size: 15.5, weight: .bold))
                        .tracking(-0.3)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(color: SCPalette.terracotta.opacity(0.30), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))

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
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
