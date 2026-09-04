import SwiftUI

/// Ustawienia → Integracje → „Cookidoo".
///
/// Trzy stany jednego arkusza: formularz logowania (niepołączono), karta
/// statusu z rozłączeniem (połączono) i formularz ponownego logowania
/// z bannerem (hasło do Cookidoo przestało działać). Hasło idzie prosto
/// na backend po HTTPS i nigdy nie wraca — status pokazuje tylko e-mail.
struct CookidooIntegrationSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    @State private var emailDraft = ""
    @State private var passwordDraft = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage: String?
    @State private var showInfoSheet = false
    @State private var showDisconnectAlert = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var store: CookidooIntegrationStore? { sessionStore.cookidooIntegrationStore }

    private var canSubmit: Bool {
        emailDraft.contains("@") && !passwordDraft.isEmpty
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialSheetHeader(
                        eyebrow: "Integracje",
                        title: "Cookidoo",
                        onClose: onClose
                    )

                    switch store?.status {
                    case .connected(let login):
                        connectedCard(login: login)
                        subscriptionWarningCard
                        howItWorksLink
                        disconnectButton
                    case .authFailed(let login):
                        authFailedBanner
                        connectForm(prefilledEmail: login)
                    case .notConnected, .unknown, .disabled, nil:
                        introCard
                        howItWorksLink
                        connectForm(prefilledEmail: nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            await store?.refresh()
        }
        .sheet(isPresented: $showInfoSheet) {
            ThermomixInfoSheet {
                showInfoSheet = false
            }
            .presentationDetents([.medium, .large])
            .dashboardLiquidSheet()
        }
        .alert("Rozłączyć Cookidoo?", isPresented: $showDisconnectAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Rozłącz", role: .destructive) {
                Task { @MainActor in
                    errorMessage = await store?.disconnect()
                }
            }
        } message: {
            Text("Wysyłanie przepisów na Thermomixa przestanie działać. Dane logowania zostaną usunięte z serwera.")
        }
    }

    // MARK: - Stan: niepołączono

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 28, height: 28)
                .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12)))

            Text("Połącz konto Cookidoo, aby wysyłać przepisy prosto na swojego Thermomixa. Przepis wyląduje w \u{201E}Mój tydzień\u{201D} i będzie czekał na ekranie urządzenia.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private var howItWorksLink: some View {
        Button {
            showInfoSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Jak to działa?")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(SCPalette.terracotta)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Formularz logowania

    private func connectForm(prefilledEmail: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Konto Cookidoo")

            VStack(spacing: 0) {
                TextField("E-mail", text: $emailDraft)
                    .font(.system(size: 15, weight: .medium))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)

                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14)

                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("Hasło", text: $passwordDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Hasło", text: $passwordDraft)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Ukryj hasło" : "Pokaż hasło")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.scChipBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        errorMessage == nil ? Color.scTileStroke(scheme) : Color.red.opacity(0.55),
                        lineWidth: 1
                    )
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }

            EditorialPrimaryActionButton(
                title: "Połącz z Cookidoo",
                icon: "link",
                isEnabled: canSubmit,
                isLoading: store?.isBusy ?? false
            ) {
                submitConnect()
            }
            .padding(.top, 4)

            Text("Dane logowania są przechowywane w postaci zaszyfrowanej i używane wyłącznie do połączenia z Cookidoo.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
        .onAppear {
            if let prefilledEmail, emailDraft.isEmpty {
                emailDraft = prefilledEmail
            }
        }
    }

    private func submitConnect() {
        focusedField = nil
        errorMessage = nil
        Task { @MainActor in
            errorMessage = await store?.connect(
                email: emailDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                password: passwordDraft
            )
            if errorMessage == nil {
                passwordDraft = ""
            }
        }
    }

    // MARK: - Stan: połączono

    private func connectedCard(login: String) -> some View {
        HStack(spacing: 14) {
            EditorialSettingsTileIcon(
                icon: "checkmark",
                color: SCPalette.sage,
                size: 44,
                radius: 12
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Połączono z Cookidoo")
                    .font(.system(size: 15.5, weight: .heavy))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(login)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)

                if let verified = store?.lastVerifiedAt {
                    Text("Ostatnia weryfikacja: \(Self.verifiedFormatter.string(from: verified))")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.10 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SCPalette.sage.opacity(scheme == .dark ? 0.45 : 0.36), lineWidth: 1.4)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subscriptionWarningCard: some View {
        if store?.subscriptionInactive == true {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SCPalette.butter)

                Text("Subskrypcja Cookidoo wygląda na nieaktywną — połączenie działa, ale Thermomix może nie pozwolić na gotowanie z przepisów.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SCPalette.butter.opacity(scheme == .dark ? 0.12 : 0.10))
            )
        }
    }

    private var disconnectButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(.horizontal, 6)
            }

            Button {
                showDisconnectAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 13, weight: .heavy))
                        .rotationEffect(.degrees(45))
                    Text("Rozłącz konto")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(Color.scChipBg(scheme))
                )
                .overlay(
                    Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Stan: błąd logowania

    private var authFailedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.85))

            Text("Hasło do Cookidoo się zmieniło albo sesja wygasła. Zaloguj się ponownie, aby przywrócić wysyłanie na Thermomixa.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(scheme == .dark ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.30), lineWidth: 1)
        )
    }

    /// Data ostatniej weryfikacji po polsku, np. „26 sie, 14:03".
    private static let verifiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()
}
