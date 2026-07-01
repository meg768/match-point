import Foundation
import CoreGraphics

enum SettingsStore {
    private static let databaseHostKey = "database.host"
    private static let databasePortKey = "database.port"
    private static let databaseNameKey = "database.name"
    private static let databaseUserKey = "database.user"
    private static let databasePasswordKey = "database.password"
    private static let appearanceModeKey = "ui.appearanceMode"
    private static let surfaceThemeKey = "ui.surfaceTheme"
    private static let surfaceModeKey = "model.surfaceMode"
    private static let matchPanelWidthKey = "ui.matchPanelWidth"

    static func loadDatabaseSettings() -> DatabaseSettings {
        let env = loadEnvironment()

        return DatabaseSettings(
            host: UserDefaults.standard.string(forKey: databaseHostKey) ?? env["MYSQL_HOST"] ?? "pi-sql",
            port: UserDefaults.standard.integer(forKey: databasePortKey).nonZero ?? Int(env["MYSQL_PORT"] ?? "") ?? 3306,
            database: UserDefaults.standard.string(forKey: databaseNameKey) ?? env["MYSQL_DATABASE"] ?? "atp",
            user: UserDefaults.standard.string(forKey: databaseUserKey) ?? env["MYSQL_USER"] ?? "root",
            password: nonEmpty(UserDefaults.standard.string(forKey: databasePasswordKey)) ?? env["MYSQL_PASSWORD"] ?? ""
        )
    }

    static func save(databaseSettings: DatabaseSettings) {
        UserDefaults.standard.set(databaseSettings.host, forKey: databaseHostKey)
        UserDefaults.standard.set(databaseSettings.port, forKey: databasePortKey)
        UserDefaults.standard.set(databaseSettings.database, forKey: databaseNameKey)
        UserDefaults.standard.set(databaseSettings.user, forKey: databaseUserKey)
        UserDefaults.standard.set(databaseSettings.password, forKey: databasePasswordKey)
    }

    static func loadAppearanceMode() -> AppAppearanceMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: appearanceModeKey),
            let mode = AppAppearanceMode(rawValue: rawValue)
        else {
            return .system
        }

        return mode
    }

    static func save(appearanceMode: AppAppearanceMode) {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
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

    static func loadSurfaceMode() -> TennisSurfaceMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: surfaceModeKey),
            let surfaceMode = TennisSurfaceMode(rawValue: rawValue)
        else {
            return .automatic
        }

        return surfaceMode
    }

    static func save(surfaceMode: TennisSurfaceMode) {
        UserDefaults.standard.set(surfaceMode.rawValue, forKey: surfaceModeKey)
    }

    static func loadMatchPanelWidth() -> CGFloat? {
        let width = UserDefaults.standard.double(forKey: matchPanelWidthKey)
        return width > 0 ? CGFloat(width) : nil
    }

    static func save(matchPanelWidth: CGFloat) {
        UserDefaults.standard.set(Double(matchPanelWidth), forKey: matchPanelWidthKey)
    }

    private static func loadEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.merging(loadAppSupportEnv()) { _, fileValue in fileValue }
    }

    private static func loadAppSupportEnv() -> [String: String] {
        guard
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return [:]
        }

        let envURL = appSupport.appendingPathComponent("Match Point", isDirectory: true).appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else {
            return [:]
        }

        return parseEnv(contents)
    }

    private static func parseEnv(_ contents: String) -> [String: String] {
        contents
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
