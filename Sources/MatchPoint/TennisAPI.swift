import Foundation

enum TennisAPIError: LocalizedError {
    case invalidBaseURL
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ogiltig API-adress."
        case .http(let status, let message):
            return "Tennis-API svarade med HTTP \(status): \(message)"
        case .invalidResponse:
            return "Tennis-API returnerade ett oväntat svar."
        }
    }
}

enum APIValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { throw DecodingError.typeMismatch(APIValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "1" : "0"
        case .null: return nil
        }
    }

    var int: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        case .null: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value): return value ? 1 : 0
        case .null: return nil
        }
    }
}

struct MySQLData: Encodable {
    let value: APIValue

    init(string: String) { value = .string(string) }
    init(int: Int) { value = .number(Double(int)) }

    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

struct MySQLRow {
    let values: [String: APIValue]
    func column(_ name: String) -> APIValue? { values[name] }
}

struct TennisAPIQueryResult {
    let client: TennisAPIClient
    let sql: String
    let values: [MySQLData]

    func get() async throws -> [MySQLRow] {
        try await client.query(sql: sql, values: values)
    }
}

struct MySQLConnection {
    let client: TennisAPIClient

    func query(_ sql: String, _ values: [MySQLData] = []) -> TennisAPIQueryResult {
        TennisAPIQueryResult(client: client, sql: sql, values: values)
    }
}

struct TennisAPIClient {
    let settings: APISettings

    func data(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: settings.baseURL)?.absoluteURL else {
            throw TennisAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TennisAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error) ?? String(decoding: data, as: UTF8.self)
            throw TennisAPIError.http(http.statusCode, message)
        }
        return data
    }

    func query(sql: String, values: [MySQLData]) async throws -> [MySQLRow] {
        let body = try JSONEncoder().encode(QueryRequest(sql: sql, format: values))
        let data = try await data(path: "query", method: "POST", body: body)
        let rows = try JSONDecoder().decode([[String: APIValue]].self, from: data)
        return rows.map(MySQLRow.init(values:))
    }

    private struct QueryRequest: Encodable {
        let sql: String
        let format: [MySQLData]
    }

    private struct APIErrorResponse: Decodable { let error: String }
}
