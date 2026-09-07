import SwiftUI

/// Przez czyje oczy patrzymy na plan.
///
/// Mieszkał wcześniej razem z pigułką profilu w nagłówku (`PlanProfileChip`).
/// Plan v2 zdjął pigułkę z nagłówka — oś czasu dnia pokazuje dania domowników
/// obok siebie, więc soczewka przestała być czymś, co trzeba mieć pod kciukiem
/// przez cały czas — a sam wybór przeniósł się do menu „…”. Enum został, bo
/// zawężanie do jednej osoby dalej istnieje; tylko wejście do niego jest inne.
enum PlanProfile: Hashable {
    /// Wszystko, co je gospodarstwo — dania wspólne i osobiste razem.
    case household
    /// Jedna osoba: jej dania plus wszystko, co wspólne.
    case member(String)

    var memberId: String? {
        if case .member(let id) = self { return id }
        return nil
    }

    /// Czy posiłek o takim audytorium należy do bieżącej soczewki?
    /// Dania wspólne („Wspólne”, puste audytorium) należą zawsze.
    func includes(participantIds: [String]) -> Bool {
        switch self {
        case .household:
            return true
        case .member(let id):
            return participantIds.isEmpty || participantIds.contains(id)
        }
    }
}
