import Foundation

enum SettingsStore {
    private static let apiBaseURLKey = "api.baseURL"
    private static let surfaceThemeKey = "ui.surfaceTheme"
    private static let selectedSurfaceKey = "model.surface"

    static func loadAPIBaseURL() -> String {
        UserDefaults.standard.string(forKey: apiBaseURLKey) ?? "https://tennis.egelberg.se"
    }

    static func save(apiBaseURL: String) {
        UserDefaults.standard.set(apiBaseURL, forKey: apiBaseURLKey)
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
}
