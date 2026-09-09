import SwiftUI

// MARK: - Wyzwalacz toastów na czas developmentu
//
// PLIK DO SKASOWANIA, gdy toasty przestaną być nowe. Nic w aplikacji od niego
// nie zależy: to jeden modyfikator wpięty raz w `ScoffieApp` i jedna biedronka
// przy prawej krawędzi ekranu.
//
// Istnieje, bo toasty odpalają się dziś wyłącznie z braku sieci i z błędów
// serwera — czyli z rzeczy, których nie da się wywołać na życzenie, patrząc
// akurat na ten ekran, który chce się obejrzeć. Bez tego jedynym sposobem na
// zobaczenie kapsuły byłoby wyłączanie Wi-Fi i odliczanie do sześciu.

extension View {
    /// Biedronka odpalająca każdy wariant toastu — TYLKO w kompilacji Debug.
    ///
    /// W Release cała gałąź znika już na etapie preprocesora, więc nie zostaje
    /// po niej ani przycisk, ani martwy kod do wycięcia przez optymalizator.
    ///
    /// Musi stać POD `scToastLayer` w drzewie widoków, bo to ona wstawia
    /// `\.toasts` do środowiska.
    func scToastDebugTrigger() -> some View {
        #if DEBUG
        modifier(SCToastDebugTriggerModifier())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct SCToastDebugTriggerModifier: ViewModifier {
    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            Menu {
                Section("Chwilowe") {
                    Button("Sukces — z podtytułem") {
                        toasts.success("Plan zapisany", "Czwartek, 4 posiłki")
                    }
                    Button("Sukces — sam tytuł") {
                        toasts.success("Zapisano")
                    }
                    Button("Informacja") {
                        toasts.info("Lista zamknięta", "Znajdziesz ją w historii zakupów.")
                    }
                    Button("Uwaga") {
                        toasts.warning("Cookidoo prosi o ponowne logowanie")
                    }
                    Button("Błąd") {
                        toasts.error("Nie udało się zapisać", "Spróbuj ponownie za chwilę.")
                    }
                }

                Section("Przypadki brzegowe") {
                    // Dwie linie w podtytule — sprawdza, czy kapsuła urosła
                    // do zmierzonej wysokości, a nie do zgadniętej.
                    Button("Długi tekst (2 linie)") {
                        toasts.error(
                            "Nie udało się odświeżyć planu tygodnia",
                            "Serwer odpowiedział błędem. Spróbuj ponownie za chwilę albo odśwież ekran."
                        )
                    }
                    // Trzy pod rząd — sprawdza kolejkę i podmianę W MIEJSCU:
                    // treść ma przeniknąć, wysokość dojechać, a kapsuła nie ma
                    // prawa wrócić do wyspy między komunikatami.
                    Button("Seria trzech (kolejka)") {
                        toasts.success("Zapisano")
                        toasts.info("Lista zamknięta")
                        toasts.warning("Cookidoo prosi o ponowne logowanie")
                    }
                    // Dwa razy to samo — powinien pokazać się JEDEN toast.
                    Button("Dwa razy to samo (tłumienie)") {
                        toasts.error("Nie udało się zapisać")
                        toasts.error("Nie udało się zapisać")
                    }
                }

                Section("Pasek stanu (zostaje)") {
                    Button("Brak internetu") {
                        toasts.setPersistent(
                            SCToast(
                                style: .warning,
                                title: "Brak połączenia z internetem",
                                message: "Widzisz ostatnio pobrane dane."
                            )
                        )
                    }
                    Button("Nie mogę połączyć się ze Scoffie") {
                        toasts.setPersistent(
                            SCToast(
                                style: .warning,
                                title: "Nie mogę połączyć się ze Scoffie",
                                message: "Widzisz ostatnio pobrane dane."
                            )
                        )
                    }
                    // Pasek zostaje na ekranie, więc można przy nim otworzyć
                    // arkusz i sprawdzić to, czego inaczej nie da się złapać:
                    // że kapsuła rysuje się NAD arkuszem, bo mieszka
                    // w osobnym oknie.
                    Button("Zgaś pasek + „wróciło”") {
                        toasts.setPersistent(nil)
                        toasts.success("Połączenie wróciło")
                    }
                }
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
            .padding(.trailing, 10)
            // Nad dolnym menu zakładek i nad stopkami z akcją główną.
            .padding(.bottom, 130)
            .accessibilityLabel("Wyzwalacz toastów (debug)")
        }
    }
}
#endif
