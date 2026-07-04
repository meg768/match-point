import Foundation

struct TennisAbstractOdds: Equatable {
    let oddsA: Double
    let oddsB: Double
    let probabilityA: Double
}

private struct TennisAbstractRatings: Equatable {
    let overall: Double
    let hard: Double
    let clay: Double
    let grass: Double

    func rating(for surface: TennisSurface) -> Double {
        switch surface {
        case .hard:
            return hard
        case .clay:
            return clay
        case .grass:
            return grass
        }
    }
}

actor TennisAbstractOddsClient {
    static let shared = TennisAbstractOddsClient()

    private let reportURL = URL(string: "https://tennisabstract.com/reports/atp_elo_ratings.html")!
    private var cachedHTML: String?
    private var cachedAt: Date?
    private var ratingsBySlug: [String: TennisAbstractRatings] = [:]
    private let cacheDuration: TimeInterval = 60 * 60

    func loadOdds(playerA: String, playerB: String, surface: TennisSurface) async throws -> TennisAbstractOdds {
        let html = try await reportHTML()
        let ratingsA = try ratings(for: playerA, in: html)
        let ratingsB = try ratings(for: playerB, in: html)
        let ratingA = ratingsA.rating(for: surface)
        let ratingB = ratingsB.rating(for: surface)
        let probabilityA = eloProbability(ratingA: ratingA, ratingB: ratingB)
        let probabilityB = 1 - probabilityA

        return TennisAbstractOdds(
            oddsA: probabilityToOdds(probabilityA),
            oddsB: probabilityToOdds(probabilityB),
            probabilityA: probabilityA
        )
    }

    private func reportHTML() async throws -> String {
        if let cachedHTML, let cachedAt, Date().timeIntervalSince(cachedAt) < cacheDuration {
            return cachedHTML
        }

        var request = URLRequest(url: reportURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let html = String(decoding: data, as: UTF8.self)
        cachedHTML = html
        cachedAt = Date()
        ratingsBySlug.removeAll()
        return html
    }

    private func ratings(for playerName: String, in html: String) throws -> TennisAbstractRatings {
        let slug = slugify(playerName)
        if let cached = ratingsBySlug[slug] {
            return cached
        }

        let lowercasedHTML = html.lowercased()
        let marker = "player.cgi?p=\(slug)".lowercased()
        guard let markerRange = lowercasedHTML.range(of: marker) else {
            throw TennisAbstractOddsError.playerNotFound(playerName)
        }

        guard
            let rowStart = lowercasedHTML[..<markerRange.lowerBound].range(of: "<tr>", options: .backwards)?.lowerBound,
            let rowEnd = lowercasedHTML[markerRange.upperBound...].range(of: "</tr>")?.upperBound
        else {
            throw TennisAbstractOddsError.incompleteRow(playerName)
        }

        let rowHTML = String(lowercasedHTML[rowStart..<rowEnd])
        let values = rightAlignedNumberValues(in: rowHTML)
        guard values.count >= 9 else {
            throw TennisAbstractOddsError.incompleteRow(playerName)
        }

        let ratings = TennisAbstractRatings(
            overall: values[2],
            hard: values[4],
            clay: values[6],
            grass: values[8]
        )
        ratingsBySlug[slug] = ratings
        return ratings
    }

    private func rightAlignedNumberValues(in rowHTML: String) -> [Double] {
        let pattern = #"<td align="right">([\d.]+)</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(rowHTML.startIndex..<rowHTML.endIndex, in: rowHTML)
        return regex.matches(in: rowHTML, range: nsRange).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: rowHTML) else {
                return nil
            }

            return Double(rowHTML[valueRange])
        }
    }

    private func slugify(_ name: String) -> String {
        String(name.folding(options: [.diacriticInsensitive], locale: .current)
            .filter { $0.isLetter })
    }

    private func eloProbability(ratingA: Double, ratingB: Double) -> Double {
        1 / (1 + pow(10, (ratingB - ratingA) / 400))
    }

    private func probabilityToOdds(_ probability: Double, margin: Double = 1.05) -> Double {
        let priced = min(0.999, max(0.001, probability * margin))
        return (1 / priced * 100).rounded() / 100
    }
}

enum TennisAbstractOddsError: LocalizedError {
    case playerNotFound(String)
    case incompleteRow(String)

    var errorDescription: String? {
        switch self {
        case .playerNotFound(let name):
            return "Tennis Abstract saknar \(name)."
        case .incompleteRow(let name):
            return "Tennis Abstract-raden för \(name) kunde inte läsas."
        }
    }
}
