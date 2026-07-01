import Foundation
import CoreGraphics

enum SettingsStore {
    private static let atpEnvPath = "/Users/magnus/Documents/GitHub/atp-tennis/.env"
    private static let databaseHostKey = "database.host"
    private static let databasePortKey = "database.port"
    private static let databaseNameKey = "database.name"
    private static let databaseUserKey = "database.user"
    private static let databasePasswordKey = "database.password"
    private static let surfaceThemeKey = "ui.surfaceTheme"
    private static let selectedSurfaceKey = "model.surface"
    private static let matchPanelWidthKey = "ui.matchPanelWidth"

    static func loadDatabaseSettings() -> DatabaseSettings {
        let localEnv = loadATPEnv()

        return DatabaseSettings(
            host: UserDefaults.standard.string(forKey: databaseHostKey) ?? localEnv["MYSQL_HOST"] ?? "pi-sql",
            port: UserDefaults.standard.integer(forKey: databasePortKey).nonZero ?? Int(localEnv["MYSQL_PORT"] ?? "") ?? 3306,
            database: UserDefaults.standard.string(forKey: databaseNameKey) ?? localEnv["MYSQL_DATABASE"] ?? "atp",
            user: UserDefaults.standard.string(forKey: databaseUserKey) ?? localEnv["MYSQL_USER"] ?? "root",
            password: nonEmpty(UserDefaults.standard.string(forKey: databasePasswordKey)) ?? localEnv["MYSQL_PASSWORD"] ?? ""
        )
    }

    static func save(databaseSettings: DatabaseSettings) {
        UserDefaults.standard.set(databaseSettings.host, forKey: databaseHostKey)
        UserDefaults.standard.set(databaseSettings.port, forKey: databasePortKey)
        UserDefaults.standard.set(databaseSettings.database, forKey: databaseNameKey)
        UserDefaults.standard.set(databaseSettings.user, forKey: databaseUserKey)
        UserDefaults.standard.set(databaseSettings.password, forKey: databasePasswordKey)
    }

    static func loadSurfaceTheme() -> AppSurfaceTheme {
        guard
            let rawValue = UserDefaults.standard.string(forKey: surfaceThemeKey),
            let surface = AppSurfaceTheme(rawValue: rawValue)
        else {
            return .grass
        }

        return surface
    }

    static func save(surfaceTheme: AppSurfaceTheme) {
        UserDefaults.standard.set(surfaceTheme.rawValue, forKey: surfaceThemeKey)
    }

    static func loadModelSurface() -> TennisSurface {
        guard
            let rawValue = UserDefaults.standard.string(forKey: selectedSurfaceKey),
            let surface = TennisSurface(rawValue: rawValue)
        else {
            return .grass
        }

        return surface
    }

    static func save(modelSurface: TennisSurface) {
        UserDefaults.standard.set(modelSurface.rawValue, forKey: selectedSurfaceKey)
    }

    static func loadMatchPanelWidth() -> CGFloat? {
        let width = UserDefaults.standard.double(forKey: matchPanelWidthKey)
        return width > 0 ? CGFloat(width) : nil
    }

    static func save(matchPanelWidth: CGFloat) {
        UserDefaults.standard.set(Double(matchPanelWidth), forKey: matchPanelWidthKey)
    }

    private static func loadATPEnv() -> [String: String] {
        guard let contents = try? String(contentsOfFile: atpEnvPath, encoding: .utf8) else {
            return ProcessInfo.processInfo.environment
        }

        let fileValues = contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else {
                    return
                }

                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }

        return ProcessInfo.processInfo.environment.merging(fileValues) { _, fileValue in fileValue }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
