import Foundation
import UserNotifications

/// Zgoda systemu na powiadomienia — odczyt i prośba W KONTEKŚCIE.
///
/// Dawniej `AppDelegate` prosił o zgodę przy każdym starcie, jeszcze przed
/// logowaniem: pierwsze, co widział nowy użytkownik, to systemowe „Scoffie
/// chce wysyłać powiadomienia” bez słowa o tym, po co. Do tego aplikacja
/// nigdzie nie czytała `authorizationStatus`, więc kto odmówił, w Ustawieniach
/// widział „Włączone” i przełączniki, które niczego nie zmieniały.
///
/// Teraz o zgodę pytamy tam, gdzie powiadomienia mają oczywisty sens:
/// przyciskiem „Włącz powiadomienia” w Ustawieniach → Powiadomienia, po
/// udostępnieniu zaproszenia domownikowi (zmiany planu robione przez drugą
/// osobę to właśnie to, o czym powiadomienia mówią) i po pierwszym daniu
/// zapisanym w planie (`requestAfterPlanning` — przypomnienia o posiłkach).
///
/// Trzy stany zamiast `UNAuthorizationStatus`, żeby widoki nie musiały
/// importować `UserNotifications` ani rozróżniać `provisional`/`ephemeral`.
enum NotificationPermission: Equatable {
    /// System jeszcze nie pytał — przycisk „Włącz powiadomienia”.
    case notAsked
    /// Odmowa — zmienić to można już tylko w Ustawieniach iOS.
    case denied
    /// System wyświetli powiadomienie. `provisional` (ciche, prosto do
    /// Centrum powiadomień) i `ephemeral` też się liczą — zgoda jest.
    case allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notAsked
        case .denied:
            self = .denied
        case .authorized, .provisional, .ephemeral:
            self = .allowed
        @unknown default:
            self = .denied
        }
    }

    /// Aktualny stan zgody z systemu.
    static func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(settings.authorizationStatus)
    }

    /// Systemowa prośba o zgodę — TYLKO gdy jeszcze nie pytaliśmy. Po odmowie
    /// system i tak nie pokazałby okna drugi raz; wtedy jedyną drogą są
    /// Ustawienia iOS (`UIApplication.openNotificationSettingsURLString`).
    /// Oddaje stan PO prośbie.
    @discardableResult
    static func requestIfNotAsked() async -> NotificationPermission {
        let center = UNUserNotificationCenter.current()
        let before = await center.notificationSettings()
        guard before.authorizationStatus == .notDetermined else {
            return NotificationPermission(before.authorizationStatus)
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        let after = await center.notificationSettings()
        return NotificationPermission(after.authorizationStatus)
    }

    /// Po daniu zapisanym w planie („Wybierz przepis” w Planie, „Dodaj do
    /// planu” w szczegółach). Pierwszy zaplanowany posiłek to chwila, od
    /// której przypomnienia o posiłkach (`MealReminderService`) mają o czym
    /// mówić — a dom jednoosobowy bez Asystenta i Gotuj nie trafiał dotąd na
    /// żadne inne pytanie (6.10.2026). Arkusz, z którego zapisano, jeszcze
    /// zjeżdża, więc okno systemu wchodzi po nim. Po pierwszym pytaniu nic
    /// nie robi. Wołający czeka na odpowiedź — toast z „Cofnij” przychodzi
    /// dopiero po oknie systemu, z pełnym czasem na cofnięcie.
    static func requestAfterPlanning() async {
        guard await current() == .notAsked else { return }
        try? await Task.sleep(for: .milliseconds(450))
        await requestIfNotAsked()
    }
}
