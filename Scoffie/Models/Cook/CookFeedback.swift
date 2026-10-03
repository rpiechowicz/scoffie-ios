import Foundation

/// Ocena gotowania: kciuk + pigułki + zdanie + zdarzenia sesji (§13.8).
/// Idzie na serwer (`recipes:cookFeedback`) dwa razy: po stuknięciu kciuka
/// i z uwagami z arkusza „Co byś zmienił?” — ten sam `sessionId`, więc
/// drugi zapis poprawia pierwszy. Panel czyta z tego, które timery ludzie
/// przedłużają (scenariusz do poprawki).
struct CookFeedback: Equatable {
    enum Rating: String, Equatable {
        case up = "UP"
        case down = "DOWN"
    }

    let rating: Rating
    let tags: [String]
    let comment: String
    let sessionId: UUID
    let recipeId: UUID
    let scenarioVersion: Int
    let servings: Int
    /// „+min” z sesji: id timera → suma sekund.
    let extensions: [String: Int]

    init(rating: Rating, tags: [String], comment: String, session: CookSession) {
        self.rating = rating
        self.tags = tags
        self.comment = comment
        self.sessionId = session.id
        self.recipeId = session.recipeId
        self.scenarioVersion = session.package.version
        self.servings = session.portions
        self.extensions = session.extensions.reduce(into: [:]) { $0[$1.timerId, default: 0] += $1.seconds }
    }

    /// `data` zdarzenia `recipes:cookFeedback` — id małymi literami, jak
    /// trzyma je baza; puste zdanie nie idzie wcale.
    var wireData: [String: Any] {
        var data: [String: Any] = [
            "sessionId": sessionId.uuidString.lowercased(),
            "recipeId": recipeId.uuidString.lowercased(),
            "scenarioVersion": scenarioVersion,
            "rating": rating.rawValue,
            "tags": tags,
            "extensions": extensions,
            "servings": servings
        ]
        if !comment.isEmpty { data["comment"] = comment }
        return data
    }
}

/// Ack `recipes:cookFeedback`.
struct CookFeedbackAck: Decodable {
    let sessionId: String
    let rating: String
}
