import Foundation

enum MatchRoomAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid API base URL."
        case .invalidResponse(let status):
            return "HTTP \(status)"
        }
    }
}

struct MatchRoomAPI {
    var baseURLString: String

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func ping() async throws -> ServicePing {
        try await get("/api/ping")
    }

    func oddsetMatches() async throws -> [TennisMatch] {
        try await get("/api/oddset?states=STARTED,NOT_STARTED")
    }

    func rankings(top: Int = 30) async throws -> [RankedPlayer] {
        let response: RankingsResponse = try await get("/api/player/rankings?top=\(top)")
        return response.players
    }

    func odds(playerA: String, playerB: String, surface: TennisSurface) async throws -> OddsResponse {
        let query = [
            URLQueryItem(name: "playerA", value: playerA),
            URLQueryItem(name: "playerB", value: playerB),
            URLQueryItem(name: "surface", value: surface.rawValue)
        ]
        return try await get("/api/odds", queryItems: query)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let data = try await data(path, queryItems: queryItems)
        return try decoder.decode(T.self, from: data)
    }

    private func data(_ path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw MatchRoomAPIError.invalidBaseURL
        }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw MatchRoomAPIError.invalidBaseURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw MatchRoomAPIError.invalidResponse(httpResponse.statusCode)
        }

        return data
    }
}
