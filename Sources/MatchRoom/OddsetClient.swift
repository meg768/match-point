import Foundation

struct OddsetClient {
    private let atpURL = URL(string: "https://eu1.offering-api.kambicdn.com/offering/v2018/svenskaspel/listView/tennis/atp/all/all/matches.json")!
    private let tennisURL = URL(string: "https://eu1.offering-api.kambicdn.com/offering/v2018/svenskaspel/listView/tennis/all/all/all/matches.json")!
    private let liveOpenURL = URL(string: "https://eu1.offering-api.kambicdn.com/offering/v2018/svenskaspel/event/live/open.json")!

    func loadMatches() async throws -> [OddsetMatch] {
        async let atp = loadSource(label: "tennis-atp", url: atpURL)
        async let live = loadSource(label: "tennis-live-open", url: liveOpenURL)
        async let all = loadSource(label: "tennis-all", url: tennisURL)

        let sources = await [atp, live, all]
        let matches = sources.flatMap { source in
            source.events
                .filter(isRelevantTennisEvent)
                .compactMap { normalize($0, source: source.label) }
        }

        if matches.isEmpty, let error = sources.compactMap(\.error).first {
            throw error
        }

        return dedupe(matches)
    }

    private func loadSource(label: String, url: URL) async -> OddsetSourceResult {
        do {
            let (data, response) = try await URLSession.shared.data(from: buildKambiURL(url))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw OddsetClientError.http(label, http.statusCode)
            }

            let payload = try JSONDecoder().decode(KambiResponse.self, from: data)
            return OddsetSourceResult(label: label, events: payload.allEvents, error: nil)
        } catch {
            return OddsetSourceResult(label: label, events: [], error: error)
        }
    }

    private func buildKambiURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        setQueryItem("channel_id", "1", in: &queryItems)
        setQueryItem("client_id", "200", in: &queryItems)
        setQueryItem("lang", "sv_SE", in: &queryItems)
        setQueryItem("market", "SE", in: &queryItems)

        if url.path.contains("/listView/") {
            setQueryItem("useCombined", "true", in: &queryItems)
            setQueryItem("useCombinedLive", "true", in: &queryItems)
        }

        components.queryItems = queryItems
        return components.url ?? url
    }

    private func setQueryItem(_ name: String, _ value: String, in queryItems: inout [URLQueryItem]) {
        queryItems.removeAll { $0.name == name }
        queryItems.append(URLQueryItem(name: name, value: value))
    }

    private func isRelevantTennisEvent(_ item: KambiEventItem) -> Bool {
        guard item.event.sport == "TENNIS", ["STARTED", "NOT_STARTED"].contains(item.event.state) else {
            return false
        }

        let path = item.event.path ?? []
        let terms = path.flatMap { [$0.termKey, $0.name, $0.englishName] }
            .map(normalizeToken)
            .filter { !$0.isEmpty }
        let searchText = ([item.event.name, item.event.group] + path.flatMap { [$0.name, $0.englishName, $0.termKey] })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let excludedTerms: Set<String> = ["wta", "challenger", "challenger_qual_", "utr_pro_tennis_series", "utr_pro_tennis_series_women"]

        if terms.contains(where: { excludedTerms.contains($0) || $0.contains("qual") || $0.contains("kval") }) {
            return false
        }

        if searchText.range(of: #"(^|[\s-])(damer|damsingel|damdubbel|women|womens|ladies|dubbel|doubles|kval|qual|qualification|qualifier)([\s-]|$)"#, options: .regularExpression) != nil {
            return false
        }

        return terms.contains("atp") || terms.contains("grand_slam")
    }

    private func normalize(_ item: KambiEventItem, source: String) -> OddsetMatch? {
        guard let id = item.event.id, let homeName = item.event.homeName, let awayName = item.event.awayName else {
            return nil
        }

        let outcomes = primaryMarket(item)?.outcomes ?? []
        let playerAOutcome = findOutcome(outcomes, type: "OT_ONE", fallbackIndex: 0)
        let playerBOutcome = findOutcome(outcomes, type: "OT_TWO", fallbackIndex: 1)
        let state: OddsetMatchState = item.event.state == "STARTED" ? .live : .upcoming

        return OddsetMatch(
            id: String(id),
            start: item.event.start.flatMap(Self.parseDate),
            tournament: item.event.group,
            state: state,
            score: state == .live ? buildScore(item) : nil,
            serve: item.liveData?.statistics?.sets?.homeServe == true ? "playerA" : (item.liveData == nil ? nil : "playerB"),
            playerA: MatchPlayer(id: item.event.home.map(String.init), name: homeName, country: nil, rank: nil, odds: decimalOdds(playerAOutcome)),
            playerB: MatchPlayer(id: item.event.away.map(String.init), name: awayName, country: nil, rank: nil, odds: decimalOdds(playerBOutcome)),
            source: source
        )
    }

    private func primaryMarket(_ item: KambiEventItem) -> KambiBetOffer? {
        item.betOffers?.first {
            $0.criterion?.label == "Matchodds" || $0.criterion?.englishLabel == "Match Odds"
        } ?? item.mainBetOffer
    }

    private func findOutcome(_ outcomes: [KambiOutcome], type: String, fallbackIndex: Int) -> KambiOutcome? {
        outcomes.first { $0.type == type } ?? (outcomes.indices.contains(fallbackIndex) ? outcomes[fallbackIndex] : nil)
    }

    private func decimalOdds(_ outcome: KambiOutcome?) -> Double? {
        guard let odds = outcome?.odds else {
            return nil
        }

        return Double(odds) / 1000
    }

    private func buildScore(_ item: KambiEventItem) -> String? {
        guard let liveData = item.liveData else {
            return nil
        }

        let homeSets = liveData.statistics?.sets?.home ?? []
        let awaySets = liveData.statistics?.sets?.away ?? []
        let setScores = zipLongest(homeSets, awaySets).compactMap { home, away -> String? in
            guard let home, let away, home >= 0, away >= 0, !(home == 0 && away == 0) else {
                return nil
            }

            return "\(home)-\(away)"
        }
        let gameScore = liveData.score.flatMap { score -> String? in
            guard let home = score.home, let away = score.away else {
                return nil
            }

            return "\(home)-\(away)"
        }
        let score = setScores.joined(separator: " ")

        if let gameScore {
            return score.isEmpty ? "[\(gameScore)]" : "\(score) [\(gameScore)]"
        }

        return score.isEmpty ? nil : score
    }

    private func zipLongest(_ lhs: [Int], _ rhs: [Int]) -> [(Int?, Int?)] {
        (0..<max(lhs.count, rhs.count)).map { index in
            (lhs.indices.contains(index) ? lhs[index] : nil, rhs.indices.contains(index) ? rhs[index] : nil)
        }
    }

    private func dedupe(_ matches: [OddsetMatch]) -> [OddsetMatch] {
        let byID = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return byID.values.sorted {
            ($0.start ?? .distantFuture, $0.matchupTitle) < ($1.start ?? .distantFuture, $1.matchupTitle)
        }
    }

    private func normalizeToken(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
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

private struct OddsetSourceResult {
    let label: String
    let events: [KambiEventItem]
    let error: Error?
}

private enum OddsetClientError: LocalizedError {
    case http(String, Int)

    var errorDescription: String? {
        switch self {
        case .http(let label, let statusCode):
            return "Oddset \(label) returned HTTP \(statusCode)."
        }
    }
}

private struct KambiResponse: Decodable {
    let events: [KambiEventItem]?
    let liveEvents: [KambiEventItem]?

    var allEvents: [KambiEventItem] {
        (events ?? []) + (liveEvents ?? [])
    }
}

private struct KambiEventItem: Decodable {
    let event: KambiEvent
    let liveData: KambiLiveData?
    let betOffers: [KambiBetOffer]?
    let mainBetOffer: KambiBetOffer?
}

private struct KambiEvent: Decodable {
    let id: Int?
    let sport: String?
    let name: String?
    let home: Int?
    let homeName: String?
    let away: Int?
    let awayName: String?
    let start: String?
    let group: String?
    let state: String?
    let path: [KambiPathTerm]?
}

private struct KambiPathTerm: Decodable {
    let termKey: String?
    let name: String?
    let englishName: String?
}

private struct KambiLiveData: Decodable {
    let score: KambiScore?
    let statistics: KambiStatistics?
}

private struct KambiScore: Decodable {
    let home: String?
    let away: String?
}

private struct KambiStatistics: Decodable {
    let sets: KambiSets?
}

private struct KambiSets: Decodable {
    let home: [Int]?
    let away: [Int]?
    let homeServe: Bool?
}

private struct KambiBetOffer: Decodable {
    let criterion: KambiCriterion?
    let outcomes: [KambiOutcome]?
}

private struct KambiCriterion: Decodable {
    let label: String?
    let englishLabel: String?
}

private struct KambiOutcome: Decodable {
    let type: String?
    let odds: Int?
}
