import Foundation

struct TennisAbstractOdds: Equatable {
    let oddsA: Double
    let oddsB: Double
    let probabilityA: Double
}

actor TennisAbstractOddsClient {
    static let shared = TennisAbstractOddsClient()

    func loadOdds(playerA: String, playerB: String, surface: TennisSurface?) async throws -> TennisAbstractOdds {
        let settings = SettingsStore.loadAPISettings()
        guard var components = URLComponents(url: settings.baseURL.appendingPathComponent("odds"), resolvingAgainstBaseURL: false) else {
            throw TennisAPIError.invalidBaseURL
        }
        components.queryItems = [
            URLQueryItem(name: "playerA", value: playerA),
            URLQueryItem(name: "playerB", value: playerB),
            URLQueryItem(name: "surface", value: surface.map { $0.rawValue.capitalized })
        ].filter { $0.value != nil }
        guard let url = components.url else { throw TennisAPIError.invalidBaseURL }

        let data = try await TennisAPIClient(settings: settings).data(path: url.absoluteString)
        let response = try JSONDecoder().decode(BackendOddsResponse.self, from: data)
        guard response.odds.TA.count == 2 else { throw TennisAPIError.invalidResponse }
        let oddsA = response.odds.TA[0]
        let oddsB = response.odds.TA[1]

        return TennisAbstractOdds(
            oddsA: oddsA,
            oddsB: oddsB,
            probabilityA: oddsB / (oddsA + oddsB)
        )
    }
}

private struct BackendOddsResponse: Decodable { let odds: BackendOdds }
private struct BackendOdds: Decodable { let TA: [Double] }

enum TennisAbstractOddsError: LocalizedError {
    case playerNotFound(String)

    var errorDescription: String? {
        switch self {
        case .playerNotFound(let name): return "Tennis-API:t saknar \(name)."
        }
    }
}
