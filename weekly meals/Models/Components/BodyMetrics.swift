import SwiftUI

/// Sylwetka użytkownika w postaci, z której da się policzyć zapotrzebowanie.
///
/// Do tej pory suwak kalorii startował z płaskiej liczby przypisanej do celu
/// (`UserGoal.suggestedCalories`) — ta sama wartość dla osoby 150 cm / 45 kg
/// i 195 cm / 110 kg. Mając wzrost, wagę, wiek i liczbę treningów można podać
/// liczbę, która cokolwiek znaczy.
struct BodyMetrics: Equatable {
    var heightCm: Int
    /// Waga z częścią dziesiętną — 83,5 kg to normalny odczyt z wagi
    /// łazienkowej, a zaokrąglenie do 84 przesuwa i BMI, i zapotrzebowanie.
    var weightKg: Double
    var age: Int
    var activity: ActivityLevel
    /// `nil` dla kont założonych zanim pojawiło się to pole — wtedy BMR
    /// liczy się ze średniej obu wariantów wzoru.
    var sex: Sex?

    /// Zwraca `nil`, gdy którejkolwiek danej brakuje albo jest bez sensu —
    /// wtedy UI schodzi do płaskiej podpowiedzi z `UserGoal`, zamiast liczyć
    /// z zer. Płeć jest wyjątkiem: jej brak obniża dokładność, ale nie
    /// blokuje rachunku.
    init?(
        heightCm: Int,
        weightKg: Double,
        yearOfBirth: Int,
        activityRaw: Int,
        sexRaw: String = "",
        now: Date = Date()
    ) {
        let currentYear = Calendar.current.component(.year, from: now)
        let age = currentYear - yearOfBirth

        guard (120...230).contains(heightCm),
              (30...250).contains(weightKg),
              (13...110).contains(age),
              let activity = ActivityLevel(rawValue: activityRaw)
        else { return nil }

        self.heightCm = heightCm
        self.weightKg = weightKg
        self.age = age
        self.activity = activity
        self.sex = Sex(rawValue: sexRaw)
    }
}

/// Płeć biologiczna — używana wyłącznie we wzorze na podstawową przemianę
/// materii. Nie ma jej w żadnym innym miejscu aplikacji i nie wpływa na nic
/// poza liczbą kalorii, dlatego opis w UI mówi wprost, po co o nią pytamy.
enum Sex: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:   return "Mężczyzna"
        case .female: return "Kobieta"
        }
    }

    var icon: String {
        switch self {
        case .male:   return "figure.stand"
        case .female: return "figure.stand.dress"
        }
    }

    /// Stała ze wzoru Mifflina-St Jeora.
    var basalConstant: Double {
        switch self {
        case .male:   return 5
        case .female: return -161
        }
    }

    /// Backend trzyma wartości wielkimi literami (`MALE`, `FEMALE`).
    var backendValue: String { rawValue.uppercased() }
}

// MARK: - BMI

extension BodyMetrics {
    /// BMI = masa [kg] / wzrost [m]².
    var bmi: Double {
        let metres = Double(heightCm) / 100
        guard metres > 0 else { return 0 }
        return weightKg / (metres * metres)
    }

    var bmiCategory: BMICategory {
        switch bmi {
        case ..<18.5:   return .underweight
        case ..<25:     return .healthy
        case ..<30:     return .overweight
        default:        return .obese
        }
    }
}

/// Progi WHO. Świadomie bez podziału na stopnie otyłości — to ma być
/// wskazówka przy suwaku kalorii, a nie diagnoza.
enum BMICategory {
    case underweight
    case healthy
    case overweight
    case obese

    var title: String {
        switch self {
        case .underweight: return "Niedowaga"
        case .healthy:     return "Waga prawidłowa"
        case .overweight:  return "Nadwaga"
        case .obese:       return "Otyłość"
        }
    }

    var accent: Color {
        switch self {
        case .underweight: return WMPalette.butter
        case .healthy:     return WMPalette.sage
        case .overweight:  return WMPalette.butter
        case .obese:       return WMPalette.terracotta
        }
    }
}

// MARK: - Zapotrzebowanie

extension BodyMetrics {
    /// Podstawowa przemiana materii wg Mifflina-St Jeora.
    ///
    /// Wzór ma dwie wersje różniące się wyłącznie stałą: +5 dla mężczyzn
    /// i −161 dla kobiet. Gdy płeć jest znana, bierzemy właściwą; gdy jej
    /// nie ma (konta sprzed dodania tego pola), zostaje środek (−78), co
    /// daje rozjazd rzędu ±83 kcal.
    var basalMetabolicRate: Double {
        10 * weightKg
            + 6.25 * Double(heightCm)
            - 5 * Double(age)
            + (sex?.basalConstant ?? -78)
    }

    /// Zapotrzebowanie zaokrąglone do 50 kcal — tak, jak pokazujemy je
    /// w UI. Surowe 2328 sugeruje precyzję, której ten wzór nie ma
    /// (±10 %), a i tak nie da się takiej wartości ustawić suwakiem.
    var maintenanceCalories: Int {
        Self.snapped(totalDailyEnergyExpenditure)
    }

    /// Całkowite zapotrzebowanie: BMR przemnożone przez współczynnik
    /// aktywności. Progi standardowe dla 4-stopniowej skali treningów.
    var totalDailyEnergyExpenditure: Double {
        let multiplier: Double
        switch activity {
        case .sedentary:  multiplier = 1.20
        case .light:      multiplier = 1.375
        case .active:     multiplier = 1.55
        case .veryActive: multiplier = 1.725
        }
        return basalMetabolicRate * multiplier
    }

    /// Sugerowany dzienny cel dla wybranego planu.
    ///
    /// Deficyt i nadwyżka są procentowe, nie ryczałtowe — 500 kcal mniej
    /// znaczy coś zupełnie innego przy zapotrzebowaniu 1700 niż przy 3200.
    /// Deficyt nigdy nie schodzi poniżej BMR: jedzenie poniżej własnej
    /// przemiany podstawowej to nie jest coś, co aplikacja ma podpowiadać.
    func suggestedCalories(for goal: UserGoal) -> Int {
        let tdee = totalDailyEnergyExpenditure

        let target: Double
        switch goal {
        case .lose:
            // 15 % deficytu — okolice 0,5 kg tygodniowo przy typowym TDEE.
            target = max(tdee * 0.85, basalMetabolicRate)
        case .gain:
            // 12 % nadwyżki — budowa masy bez zbędnego zapasu.
            target = tdee * 1.12
        case .maintain, .healthy, .plan:
            target = tdee
        }

        return Self.snapped(target)
    }

    /// Zaokrąglenie do kroku suwaka (50 kcal) i przycięcie do jego zakresu —
    /// podpowiedź musi być wartością, którą suwak w ogóle potrafi ustawić.
    static func snapped(_ raw: Double) -> Int {
        let stepped = (raw / 50).rounded() * 50
        return min(max(Int(stepped), 1200), 3500)
    }
}

// MARK: - Odczyt z UserDefaults

extension BodyMetrics {
    enum Keys {
        static let heightCm = "settings.profile.heightCm"
        static let weightKg = "settings.profile.weightKg"
        static let yearOfBirth = "settings.profile.yearOfBirth"
        static let activityLevel = "settings.diet.activityLevel"
        static let sex = "settings.profile.sex"
    }
}

extension UserGoal {
    /// Podpowiedź kaloryczna: policzona z sylwetki, gdy dane są kompletne,
    /// a w przeciwnym razie płaska wartość przypisana do celu.
    func suggestedCalories(for metrics: BodyMetrics?) -> Int {
        metrics?.suggestedCalories(for: self) ?? suggestedCalories
    }
}
