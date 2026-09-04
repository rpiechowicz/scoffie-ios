import Foundation
import HealthKit

/// Skąd czytamy kroki. Wybór użytkownika w arkuszu „Zdrowie" — jedno źródło
/// naraz, nigdy suma obu: Garmin Connect dopisuje kroki do Zdrowia obok
/// próbek iPhone'a, więc suma liczyłaby ten sam spacer dwa razy.
enum StepsSource: String, CaseIterable {
    case appleHealth = "APPLE_HEALTH"
    case garmin = "GARMIN"
}

struct DailyStepsSample: Equatable {
    /// Klucz dnia w formacie `MealCalendarStore.dateKey` (yyyy-MM-dd, strefa telefonu).
    let dateKey: String
    let steps: Int
}

/// Cienka warstwa nad HealthKit: autoryzacja odczytu kroków, dzienne sumy
/// i obserwacja zmian. Bez zapisu i bez background delivery (V1) — działa
/// tylko, gdy aplikacja żyje; resztę dogania odświeżenie przy foregroundzie.
final class HealthKitService {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private var observerQuery: HKObserverQuery?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// UWAGA: statusu autoryzacji ODCZYTU nie da się potem sprawdzić —
    /// `authorizationStatus(for:)` mówi wyłącznie o zapisie. Odmowa odczytu
    /// nie rzuca błędem: zapytania po prostu zwracają pustkę, a UX musi to
    /// przeżyć (podpowiedź o Ustawieniach w arkuszu „Zdrowie").
    func requestReadAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    /// Dzienne sumy kroków w [firstDay, lastDay] (granice dni w strefie
    /// telefonu). Dni bez ani jednej próbki są pomijane — zero jest
    /// nieodróżnialne od odmowy odczytu i nie wolno go zapisywać jako daną.
    func dailySteps(
        from firstDay: Date,
        to lastDay: Date,
        source: StepsSource
    ) async throws -> [DailyStepsSample] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: firstDay)
        guard let end = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)
        ) else { return [] }

        let rangePredicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        var samplePredicate: NSPredicate = rangePredicate
        if source == .garmin {
            let garminSources = try await garminSources()
            // Brak źródeł Garmina w Zdrowiu = Garmin Connect nie zapisuje tu
            // kroków — zwracamy pustkę, a arkusz pokaże jak włączyć sync.
            guard !garminSources.isEmpty else { return [] }
            samplePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                rangePredicate,
                HKQuery.predicateForObjects(from: garminSources),
            ])
        }

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: samplePredicate),
            // cumulativeSum deduplikuje nakładające się źródła (iPhone +
            // Apple Watch) wg priorytetów Zdrowia — wynik zgadza się z apką
            // Zdrowie. W trybie Garmin filtr źródeł zostawia tylko Garmina.
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await descriptor.result(for: store)
        var samples: [DailyStepsSample] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let total = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            guard total > 0 else { return }
            samples.append(DailyStepsSample(
                dateKey: MealCalendarStore.dateKey(for: stats.startDate),
                // Sufit z kontraktu backendu (@Max w DTO) — śmieciowa próbka
                // z aplikacji trzeciej powyżej limitu wywalałaby walidację
                // całego batcha i po cichu zatrzymała sync (błędy połykamy).
                steps: min(total, 200_000)
            ))
        }
        return samples
    }

    /// Obserwacja nowych próbek kroków, póki aplikacja działa. Handler
    /// przychodzi na wątku tła — odbiorca sam wskakuje na MainActor.
    func observeStepChanges(_ handler: @escaping @Sendable () -> Void) {
        stopObserving()
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completionHandler, _ in
            handler()
            // HealthKit wymaga potwierdzenia, inaczej po kilku zaległych
            // powiadomieniach przestaje wołać obserwatora.
            completionHandler()
        }
        observerQuery = query
        store.execute(query)
    }

    func stopObserving() {
        if let observerQuery {
            store.stop(observerQuery)
        }
        observerQuery = nil
    }

    /// Źródła w Zdrowiu, które kiedykolwiek zapisały kroki i wyglądają na
    /// Garmina (bundle `com.garmin.*` — Garmin Connect).
    private func garminSources() async throws -> Set<HKSource> {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: stepType, samplePredicate: nil) { _, sources, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let garmin = (sources ?? []).filter {
                    $0.bundleIdentifier.lowercased().hasPrefix("com.garmin")
                }
                continuation.resume(returning: garmin)
            }
            store.execute(query)
        }
    }
}
