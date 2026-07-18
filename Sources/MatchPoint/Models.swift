import Foundation

struct APISettings: Equatable {
    var baseURL: URL

    var displayName: String {
        baseURL.absoluteString
    }
}

enum TennisSurface: String, CaseIterable, Identifiable {
    case grass
    case clay
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grass:
            return "Gräs"
        case .clay:
            return "Grus"
        case .hard:
            return "Hardcourt"
        }
    }
}

enum TennisSurfaceMode: String, CaseIterable, Identifiable {
    case hard
    case clay
    case grass
    case automatic

    var id: String { rawValue }

    var surface: TennisSurface? {
        switch self {
        case .hard:
            return .hard
        case .clay:
            return .clay
        case .grass:
            return .grass
        case .automatic:
            return nil
        }
    }

    var title: String {
        switch self {
        case .hard:
            return "Hardcourt"
        case .clay:
            return "Grus"
        case .grass:
            return "Gräs"
        case .automatic:
            return "Automatiskt"
        }
    }
}

struct MatchPlayer: Equatable {
    let id: String?
    let name: String
    let country: String?
    let rank: Int?
    let odds: Double?
}

struct TennisMatch: Identifiable, Equatable {
    let id: String
    let date: String
    let tournament: String
    let eventType: String?
    let surface: String?
    let round: String?
    let score: String?
    let status: String?
    let duration: String?
    let playerA: MatchPlayer
    let playerB: MatchPlayer

    var isLive: Bool { false }

    var stateTitle: String {
        status ?? "Match"
    }

    var dateTitle: String {
        date
    }

    var displayScore: String {
        score?.isEmpty == false ? score! : "-"
    }

    var matchupTitle: String {
        "\(playerA.name) vs \(playerB.name)"
    }

    var shortTitle: String {
        "\(playerA.lastName) - \(playerB.lastName)"
    }
}

enum OddsetMatchState: String, Equatable {
    case live
    case upcoming

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .upcoming:
            return "Kommande"
        }
    }
}

enum MatchListFilter: String, CaseIterable, Identifiable {
    case all
    case live
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Alla"
        case .live:
            return "Live"
        case .upcoming:
            return "Kommande"
        }
    }
}

struct OddsetMatch: Identifiable, Equatable {
    let id: String
    let start: Date?
    let tournament: String?
    let state: OddsetMatchState
    let score: String?
    let serve: String?
    let playerA: MatchPlayer
    let playerB: MatchPlayer
    let source: String

    var matchupTitle: String {
        "\(playerA.name) vs \(playerB.name)"
    }

    var startTitle: String {
        guard let start else {
            return "--:--"
        }

        let calendar = Calendar.current
        let day: String

        if calendar.isDateInToday(start) {
            day = "Idag"
        } else if calendar.isDateInTomorrow(start) {
            day = "I morgon"
        } else if calendar.isDateInYesterday(start) {
            day = "I går"
        } else {
            day = Self.dayFormatter.string(from: start)
        }

        return "\(day) \(Self.timeFormatter.string(from: start))"
    }

    var displayScore: String {
        score?.isEmpty == false ? score! : (state == .live ? "Live" : "Ej startad")
    }

    var inferredSurface: TennisSurface {
        let text = [tournament, source].compactMap { $0 }.joined(separator: " ").lowercased()

        if text.contains("wimbledon") || text.contains("grass") || text.contains("halle") || text.contains("queen") || text.contains("stuttgart") {
            return .grass
        }

        if text.contains("roland") || text.contains("garros") || text.contains("clay") || text.contains("monte carlo") || text.contains("madrid") || text.contains("rome") {
            return .clay
        }

        return .hard
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}

struct PlayerDashboardStats: Identifiable, Equatable {
    let id: String
    let name: String
    let country: String?
    let age: Int?
    let pro: Int?
    let height: Int?
    let weight: Int?
    let rank: Int?
    let points: Int?
    let highestRank: Int?
    let highestRankDate: String?
    let careerTitles: Int?
    let grandSlamTitles: Int
    let mastersTitles: Int
    let atp500Titles: Int
    let atp250Titles: Int
    let careerPrize: Int?
    let ytdWins: Int?
    let ytdLosses: Int?
    let ytdTitles: Int?
    let ytdPrize: Int?
    let serveRating: Double?
    let returnRating: Double?
    let pressureRating: Double?
    let eloRank: Int?
    let hardElo: Int?
    let clayElo: Int?
    let grassElo: Int?
    let totalMatches: Int
    let totalWins: Int
    let formMatches: Int
    let formWins: Int
    let recentMatches: Int
    let recentWins: Int
    let surfaceMatches: Int
    let surfaceWins: Int
    let hardMatches: Int
    let hardWins: Int
    let clayMatches: Int
    let clayWins: Int
    let grassMatches: Int
    let grassWins: Int

    var imageURL: URL? {
        SettingsStore.loadAPISettings().baseURL
            .appendingPathComponent("player")
            .appendingPathComponent(id.lowercased())
            .appendingPathComponent("headshot")
    }

    var totalLosses: Int { max(0, totalMatches - totalWins) }
    var formLosses: Int { max(0, formMatches - formWins) }
    var recentLosses: Int { max(0, recentMatches - recentWins) }
    var surfaceLosses: Int { max(0, surfaceMatches - surfaceWins) }
    var hardLosses: Int { max(0, hardMatches - hardWins) }
    var clayLosses: Int { max(0, clayMatches - clayWins) }
    var grassLosses: Int { max(0, grassMatches - grassWins) }
    var careerWinsForDisplay: Int { totalWins }
    var careerLossesForDisplay: Int { totalLosses }
    var bmi: Double? {
        guard let height, let weight, height > 0 else {
            return nil
        }

        let meters = Double(height) / 100
        return Double(weight) / (meters * meters)
    }

    var winPercentage: Double? {
        percentage(wins: totalWins, matches: totalMatches)
    }

    var recentWinPercentage: Double? {
        percentage(wins: recentWins, matches: recentMatches)
    }

    var formScore: Int? {
        guard formMatches > 0 else {
            return nil
        }

        let ratio = Double(formWins) / Double(formMatches)
        return min(5, max(1, Int((ratio * 5).rounded())))
    }

    var surfaceWinPercentage: Double? {
        percentage(wins: surfaceWins, matches: surfaceMatches)
    }

    private func percentage(wins: Int, matches: Int) -> Double? {
        guard matches > 0 else {
            return nil
        }

        return Double(wins) / Double(matches) * 100
    }
}

struct RankingHistoryPoint: Identifiable, Equatable {
    let id: String
    let month: String
    let rank: Int
}

struct PlayerMatchTab: Identifiable, Equatable {
    let id: String
    let title: String
    let matches: [TennisMatch]
}

struct PlayerWorkspaceProfile: Equatable {
    let stats: PlayerDashboardStats?
    let rankingHistory: [RankingHistoryPoint]
    let matchTabs: [PlayerMatchTab]
}

struct HeadToHeadMatch: Identifiable, Equatable {
    let id: String
    let date: String
    let tournament: String
    let surface: String?
    let winnerName: String
    let winnerRank: Int?
    let loserName: String
    let loserRank: Int?
    let score: String?
}

struct PlayerComparison: Equatable {
    let playerA: PlayerDashboardStats?
    let playerB: PlayerDashboardStats?
    let rankingHistoryA: [RankingHistoryPoint]
    let rankingHistoryB: [RankingHistoryPoint]
    let headToHeadWinsA: Int
    let headToHeadWinsB: Int
    let headToHeadMatches: [HeadToHeadMatch]
    let taA: Double?
    let taB: Double?
    let gptA: Double?
    let gptB: Double?
}

enum ComparisonSlot {
    case playerA
    case playerB
}

struct DataLogEntry: Identifiable, Equatable {
    enum Status: String {
        case started
        case success
        case failed
        case cache

        var title: String {
            switch self {
            case .started:
                return "Start"
            case .success:
                return "OK"
            case .failed:
                return "Fel"
            case .cache:
                return "Cache"
            }
        }
    }

    let id: UUID
    let timestamp: Date
    let source: String
    let operation: String
    let detail: String
    let durationMS: Int?
    let status: Status
}

struct MatchDashboard: Equatable {
    let matchID: String
    let surface: TennisSurface
    let playerA: PlayerDashboardStats?
    let playerB: PlayerDashboardStats?
    let rankingHistoryA: [RankingHistoryPoint]
    let rankingHistoryB: [RankingHistoryPoint]
    let headToHeadWinsA: Int
    let headToHeadWinsB: Int
    let headToHeadMatches: [HeadToHeadMatch]
    let modelA: Double?
    let modelB: Double?
    let winFactorA: Double?
    let gptA: Double?
    let gptB: Double?

    var winFactorB: Double? {
        winFactorA.map { 1 - $0 }
    }

    func withModelOdds(_ odds: TennisAbstractOdds?) -> MatchDashboard {
        MatchDashboard(
            matchID: matchID,
            surface: surface,
            playerA: playerA,
            playerB: playerB,
            rankingHistoryA: rankingHistoryA,
            rankingHistoryB: rankingHistoryB,
            headToHeadWinsA: headToHeadWinsA,
            headToHeadWinsB: headToHeadWinsB,
            headToHeadMatches: headToHeadMatches,
            modelA: odds?.oddsA,
            modelB: odds?.oddsB,
            winFactorA: odds?.probabilityA,
            gptA: gptA,
            gptB: gptB
        )
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

struct RankedPlayer: Identifiable, Equatable, Codable {
    let player: String
    let name: String
    let country: String?
    let rank: Int
    let points: Int?
    let eloRank: Int?
    let hardElo: Int?
    let clayElo: Int?
    let grassElo: Int?

    var id: String { player }
}

struct MatchIntelligence: Equatable {
    let matchID: String
    let surface: TennisSurface
    let playerA: String
    let playerB: String
    let modelA: Double?
    let modelB: Double?
    let winFactorA: Double?

    var winFactorB: Double? {
        winFactorA.map { 1 - $0 }
    }
}

enum MatchPointStatus: Equatable {
    case idle
    case loading(String)
    case ready(String)
    case failed(String)

    var text: String {
        switch self {
        case .idle:
            return "Redo"
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
