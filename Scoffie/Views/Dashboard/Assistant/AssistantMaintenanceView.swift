import SwiftUI

/// Asystent wyłączony na serwerze (503 `AI_DISABLED`, `AI_ENABLED=false`
/// na Railwayu) — przerwa techniczna, nie błąd.
///
/// Dotąd jedynym śladem było wyszarzone pole „Asystent jest teraz
/// niedostępny”: wyglądało jak zepsuta aplikacja. Teraz zakładka mówi to
/// wprost i ciepło — znak z kluczem, „mały remont”, jedno zdanie, co działa
/// dalej, i „Sprawdź ponownie”. Pole wiadomości znika (`AssistantView.composer`),
/// bo pisać i tak nie ma do kogo.
///
/// Blok stoi tam, gdzie powitanie (`AssistantEmptyState`): przy dolnej
/// krawędzi, w tej samej typografii (znak, otwarcie 28 semibold, zdanie 17).
/// Ruch: samo krycie kaskadą przy wejściu i żywy znak — bez ruchu całego
/// ekranu. Wyczerpana pula to INNY stan (`AssistantQuotaSpentCard`).
struct AssistantMaintenanceView: View {
    /// Trwa sprawdzanie — przycisk kręci się zamiast napisu.
    let isChecking: Bool
    /// `true` = asystent wrócił (ekran zniknie sam, bo `isUnavailable` spadło).
    let onRecheck: () async -> Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scTabIsActive) private var isActiveTab

    @State private var revealed = false
    /// Ostatnie sprawdzenie nic nie dało — pod przyciskiem krótkie „jeszcze nie”.
    @State private var stillDown = false
    @State private var checks = 0

    private struct Working: Identifiable {
        let id: String
        let title: String
        let icon: String
        let accent: Color
    }

    /// Co działa bez asystenta — to, po co ktoś i tak przyszedł do aplikacji.
    private let working: [Working] = [
        Working(id: "plan", title: MenuConstans.Plan.name, icon: MenuConstans.Plan.icon, accent: SCPalette.terracotta),
        Working(id: "recipes", title: MenuConstans.Recipes.name, icon: MenuConstans.Recipes.icon, accent: SCPalette.sage),
        Working(id: "shopping", title: "Zakupy", icon: MenuConstans.Products.icon, accent: SCPalette.indigo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
                .modifier(MaintenanceStep(revealed: revealed, delay: 0, reduceMotion: reduceMotion))

            Text("PRACE SERWISOWE")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(AssistantLook.terra(scheme))
                .padding(.top, 18)
                .modifier(MaintenanceStep(revealed: revealed, delay: 0.06, reduceMotion: reduceMotion))

            Text("Asystent jest na małym remoncie")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .lineSpacing(2)
                .foregroundStyle(AssistantLook.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
                .modifier(MaintenanceStep(revealed: revealed, delay: 0.1, reduceMotion: reduceMotion))

            Text("Dokręcamy kilka śrubek, żeby podpowiadał jeszcze trafniej. Wróci niedługo.")
                .font(.system(size: 17))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(AssistantLook.muted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
                .padding(.top, 8)
                .modifier(MaintenanceStep(revealed: revealed, delay: 0.16, reduceMotion: reduceMotion))

            workingCard
                .padding(.top, 20)
                .modifier(MaintenanceStep(revealed: revealed, delay: 0.24, reduceMotion: reduceMotion))

            recheckButton
                .padding(.top, 20)
                .modifier(MaintenanceStep(revealed: revealed, delay: 0.32, reduceMotion: reduceMotion))

            Text("Jeszcze nie wrócił — zajrzyj za kilka minut.")
                .font(.system(size: 13.5))
                .foregroundStyle(AssistantLook.faint(scheme))
                .padding(.top, 10)
                .padding(.leading, 4)
                .opacity(stillDown ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: stillDown)
                .accessibilityHidden(!stillDown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.warning, trigger: checks)
        // Każdy element ma własną animację z opóźnieniem (`MaintenanceStep`).
        .onAppear { revealed = true }
    }

    // MARK: - Części

    /// Żywy znak z kluczem w rogu — ta sama postać co w powitaniu, tylko
    /// „w warsztacie”. Klucz kiwa się co kilka sekund, na niewybranej
    /// zakładce i przy „Ogranicz ruch” stoi.
    private var mark: some View {
        SCLivingMark(
            mood: .idle,
            color: AssistantLook.terraFill(scheme),
            size: 26,
            lively: true
        )
        .frame(width: 34, height: 34, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(AssistantLook.terra(scheme))
                .symbolEffect(
                    .wiggle,
                    options: .repeat(.periodic(delay: 2.6)),
                    isActive: isActiveTab && !reduceMotion
                )
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.scPageBase(scheme)))
                .background(Circle().fill(AssistantLook.terraTint(scheme)).padding(-0.5))
                .overlay(Circle().stroke(AssistantLook.terraFill(scheme).opacity(0.35), lineWidth: 1))
                .offset(x: 8, y: 6)
        }
        .accessibilityHidden(true)
    }

    /// Jedna karta, trzy kafle: co działa bez asystenta.
    private var workingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssistantLook.sage(scheme))
                Text("Działa jak zawsze")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(AssistantLook.muted(scheme))
            }

            HStack(spacing: 8) {
                ForEach(working) { item in
                    VStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.accent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(item.accent.opacity(scheme == .dark ? 0.16 : 0.12)))
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AssistantLook.field(scheme))
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan, przepisy i zakupy działają jak zawsze")
    }

    /// Główna akcja w wariancie „soft”, na szerokość treści — jak w powitaniu.
    private var recheckButton: some View {
        Button {
            Task {
                stillDown = false
                let back = await onRecheck()
                if !back {
                    stillDown = true
                    checks += 1
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AssistantLook.terra(scheme))
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                }
                Text("Sprawdź ponownie")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.leading, 20)
            .padding(.trailing, 22)
            .frame(height: 50)
            .scSoftCapsule(AssistantLook.terra(scheme))
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(isChecking)
        .animation(.easeOut(duration: 0.2), value: isChecking)
    }
}

/// Kaskada wejścia: samo krycie, każdy element z własnym opóźnieniem.
private struct MaintenanceStep: ViewModifier {
    let revealed: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(delay), value: revealed)
    }
}

#Preview("Light") {
    ZStack(alignment: .bottom) {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        AssistantMaintenanceView(isChecking: false, onRecheck: { false })
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, 40)
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ZStack(alignment: .bottom) {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        AssistantMaintenanceView(isChecking: true, onRecheck: { false })
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, 40)
    }
    .preferredColorScheme(.dark)
}
