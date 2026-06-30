import Foundation

enum TennisSurface: String, CaseIterable, Identifiable {
    case grass
    case clay
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grass:
            return "Grass"
        case .clay:
            return "Clay"
        case .hard:
            return "Hard"
        }
    }
}

struct ServicePing: Decodable {
    let message: String
    let version: String
}

struct MatchPlayer: Decodable, Equatable {
    let id: String?
    let name: String
    let odds: Double?
}

struct TennisMatch: Decodable, Identifiable, Equatable {
    let id: Int
    let start: Date
    let tournament: String
    let state: String
    let score: String?
    let serve: String?
    let playerA: MatchPlayer
    let playerB: MatchPlayer

    var isLive: Bool {
        state == "live"
    }

    var stateTitle: String {
        isLive ? "Live" : "Upcoming"
    }

    var displayScore: String {
        score?.isEmpty == false ? score! : start.formatted(date: .omitted, time: .shortened)
    }

    var matchupTitle: String {
        "\(playerA.name) vs \(playerB.name)"
    }

    var shortTitle: String {
        "\(playerA.lastName) - \(playerB.lastName)"
    }
}

extension MatchPlayer {
    var lastName: String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    var oddsText: String {
        guard let odds else {
            return "-"
        }

        return odds.formatted(.number.precision(.fractionLength(2)))
    }
}

struct RankingsResponse: Decodable {
    let players: [RankedPlayer]
}

struct RankedPlayer: Decodable, Identifiable, Equatable {
    let date: Date
    let player: String
    let name: String
    let country: String?
    let rank: Int
    let points: Int?

    var id: String { player }
}

struct OddsResponse: Decodable, Equatable {
    let computedOdds: [Double]?
    let tennisAbstractOdds: [Double]?

    var hasModel: Bool {
        computedOdds?.count == 2
    }
}

struct MatchIntelligence: Equatable {
    let matchID: Int
    let surface: TennisSurface
    let odds: OddsResponse

    var modelA: Double? { odds.computedOdds?.first }
    var modelB: Double? { odds.computedOdds?.dropFirst().first }
    var abstractA: Double? { odds.tennisAbstractOdds?.first }
    var abstractB: Double? { odds.tennisAbstractOdds?.dropFirst().first }
}

enum MatchRoomStatus: Equatable {
    case idle
    case loading(String)
    case ready(String)
    case failed(String)

    var text: String {
        switch self {
        case .idle:
            return "Ready"
        case .loading(let text), .ready(let text), .failed(let text):
            return text
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "circle"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
