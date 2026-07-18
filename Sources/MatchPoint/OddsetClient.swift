import Foundation

struct OddsetClient {
    func loadMatches() async throws -> [OddsetMatch] {
        let client = TennisAPIClient(settings: SettingsStore.loadAPISettings())
        let data = try await client.data(path: "oddset")
        let rows = try JSONDecoder().decode([BackendOddsetMatch].self, from: data)

        return rows.map { row in
            let state: OddsetMatchState = row.state == "live" ? .live : .upcoming
            return OddsetMatch(
                id: row.id.map(String.init) ?? "\(row.start ?? "")-\(row.playerA.name)-\(row.playerB.name)",
                start: row.start.flatMap(Self.parseDate),
                tournament: row.tournament,
                state: state,
                score: row.score,
                serve: row.serve,
                playerA: MatchPlayer(id: row.playerA.id, name: row.playerA.name, country: nil, rank: nil, odds: row.playerA.odds),
                playerB: MatchPlayer(id: row.playerB.id, name: row.playerB.name, country: nil, rank: nil, odds: row.playerB.odds),
                source: "tennis.egelberg.se"
            )
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        isoDateFormatterWithFractions.date(from: value) ?? isoDateFormatter.date(from: value)
    }

    private static let isoDateFormatterWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateFormatter = ISO8601DateFormatter()
}

private struct BackendOddsetMatch: Decodable {
    let id: Int?
    let start: String?
    let tournament: String?
    let state: String?
    let score: String?
    let serve: String?
    let playerA: BackendOddsetPlayer
    let playerB: BackendOddsetPlayer
}

private struct BackendOddsetPlayer: Decodable {
    let id: String?
    let name: String
    let odds: Double?
}
