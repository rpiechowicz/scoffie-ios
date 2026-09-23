import Foundation
import Sentry

/// Zgłaszanie awarii i wydajności do Sentry (projekt `scoffie/scoffie-ios`,
/// region UE). Odpowiednik `src/instrument.ts` w backendzie — ta sama zasada:
/// do Sentry idą dane TECHNICZNE, nigdy treść użytkownika.
///
/// Co idzie: crashe, zawieszenia UI, zabicia przez watchdog, ślady startu
/// aplikacji i zapytań do API (20% sesji w produkcji), profile CPU w ich
/// trakcie, identyfikator użytkownika, wersja i build.
/// Co NIE idzie: zrzuty ekranu i hierarchia widoków (na ekranie są alergeny,
/// kroki ze Zdrowia, plan posiłków), nagrania sesji, IP, nagłówki (token),
/// query w adresach, e-mail i imię.
///
/// `nonisolated`, bo haki `beforeSend`/`beforeBreadcrumb` SDK woła z własnych
/// wątków — domknięcie odziedziczone po `MainActor` byłoby kłamstwem.
nonisolated enum CrashReporting {
    private static let dsn =
        "https://6c79a0d71fd48af7c4e861a51540a228@o4512134566772736.ingest.de.sentry.io/4512134683426896"

    /// Wołane raz, w `ScoffieApp.init` — przed czymkolwiek, co może się wywrócić.
    static func start() {
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            #if DEBUG
            options.tracesSampleRate = 1.0
            #else
            options.tracesSampleRate = 0.2
            #endif
            options.configureProfiling = {
                $0.sessionSampleRate = 0.2
                $0.lifecycle = .trace
            }

            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Nagłówki śladu tylko do naszego API: łączą ślad z telefonu ze
            // śladem backendu. Domyślnie SDK dokleja je do KAŻDEGO hosta.
            options.tracePropagationTargets = ["api.scoffie.app"]
            // 5xx zgłasza backend — z requestId i pełnym kontekstem. Kopia
            // z telefonu byłaby tym samym błędem dwa razy.
            options.enableCaptureFailedRequests = false

            options.beforeSend = { event in scrubEvent(event) }
            options.beforeBreadcrumb = { crumb in scrubBreadcrumb(crumb) }
        }
    }

    /// Po zalogowaniu/odtworzeniu sesji i po wylogowaniu. Tylko identyfikator —
    /// ten sam, który backend wysyła przy swoich błędach, więc zgłoszenia
    /// z obu stron da się zestawić.
    static func setUser(id: String?) {
        SentrySDK.setUser(id.map { User(userId: $0) })
    }

    private static var environment: String {
        #if DEBUG
        return "development"
        #else
        // TestFlight instaluje z paragonem sandboxowym — osobne środowisko,
        // żeby błędy testerów nie mieszały się z produkcją.
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            ? "testflight"
            : "production"
        #endif
    }

    private static func scrubEvent(_ event: Event) -> Event? {
        if let request = event.request {
            request.headers = nil
            request.cookies = nil
            request.queryString = nil
            request.url = request.url.map { stripQuery($0) }
        }
        if let user = event.user {
            event.user = user.userId.map { User(userId: $0) }
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap { scrubBreadcrumb($0) }
        return event
    }

    private static func scrubBreadcrumb(_ crumb: Breadcrumb) -> Breadcrumb? {
        // `setData(value:key:)`, nie przypisanie całego `data` — setter jest
        // przestarzały (sentry-cocoa 9.29). `nil` usuwa klucz.
        guard let data = crumb.data else { return crumb }
        if let url = data["url"] as? String {
            crumb.setData(value: stripQuery(url), key: "url")
        }
        for key in ["http.query", "http.fragment"] where data[key] != nil {
            crumb.setData(value: nil, key: key)
        }
        return crumb
    }

    private static func stripQuery(_ url: String) -> String {
        guard let cut = url.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return url }
        return String(url[..<cut])
    }
}
