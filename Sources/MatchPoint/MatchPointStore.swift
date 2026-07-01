import Foundation

@MainActor
final class MatchPointStore: ObservableObject {
    @Published var databaseSettings = SettingsStore.loadDatabaseSettings()
    @Published var matches: [TennisMatch] = []
    @Published var oddsetMatches: [OddsetMatch] = []
    @Published var rankings: [RankedPlayer] = []
    @Published var selectedMatchID: String?
    @Published var selectedOddsetMatchID: String?
    @Published var surfaceMode = SettingsStore.loadSurfaceMode()
    @Published var selectedSurface = SettingsStore.loadSurfaceMode().surface ?? .grass
    @Published var intelligence: MatchIntelligence?
    @Published var dashboard: MatchDashboard?
    @Published var isLoading = false
    @Published var isLoadingIntelligence = false
    @Published var isLoadingDashboard = false
    @Published var status: MatchPointStatus = .idle

    var selectedMatch: TennisMatch? {
        matches.first { $0.id == selectedMatchID } ?? matches.first
    }

    var selectedOddsetMatch: OddsetMatch? {
        oddsetMatches.first { $0.id == selectedOddsetMatchID } ?? oddsetMatches.first
    }

    func refresh() {
        Task {
            await refreshNow()
        }
    }

    func refreshNow() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        status = .loading("Reading matches...")

        let oddsetSnapshot = await loadOddsetMatches()

        switch oddsetSnapshot {
        case .success(let matches):
            oddsetMatches = matches
            if selectedOddsetMatchID == nil || !matches.contains(where: { $0.id == selectedOddsetMatchID }) {
                selectedOddsetMatchID = matches.first?.id
            }
            resolveAutomaticSurface()
            status = .ready("Loaded \(matches.filter { $0.state == .live }.count) live and \(matches.filter { $0.state == .upcoming }.count) upcoming matches.")
            await loadDashboardForSelectedOddsetMatch()
        case .failure:
            oddsetMatches = []
            selectedOddsetMatchID = nil
            dashboard = nil
            status = .failed("Matches unavailable.")
        }

        isLoading = false
    }

    func select(match: TennisMatch) {
        selectedMatchID = match.id
        intelligence = nil
        Task {
            await loadIntelligenceForSelectedMatch()
        }
    }

    func select(oddsetMatch: OddsetMatch) {
        selectedOddsetMatchID = oddsetMatch.id
        dashboard = nil
        resolveAutomaticSurface()
        Task {
            await loadDashboardForSelectedOddsetMatch()
        }
    }

    func changeSurfaceMode(_ mode: TennisSurfaceMode) {
        surfaceMode = mode
        SettingsStore.save(surfaceMode: mode)
        selectedSurface = resolvedSurface(for: selectedOddsetMatch)
        SettingsStore.save(surfaceTheme: AppSurfaceTheme(surface: selectedSurface))
        intelligence = nil
        dashboard = nil
        Task {
            await loadIntelligenceForSelectedMatch()
            await loadDashboardForSelectedOddsetMatch()
        }
    }

    func saveDatabaseSettings() {
        SettingsStore.save(databaseSettings: databaseSettings)
    }

    private func resolveAutomaticSurface() {
        let resolved = resolvedSurface(for: selectedOddsetMatch)
        guard selectedSurface != resolved else {
            return
        }

        selectedSurface = resolved
        SettingsStore.save(surfaceTheme: AppSurfaceTheme(surface: resolved))
    }

    private func resolvedSurface(for match: OddsetMatch?) -> TennisSurface {
        surfaceMode.surface ?? match?.inferredSurface ?? .grass
    }

    func loadIntelligenceForSelectedMatch() async {
        guard let match = selectedMatch else {
            return
        }

        isLoadingIntelligence = true
        do {
            let database = ATPDatabase(settings: databaseSettings)
            intelligence = try await database.loadIntelligence(match: match, surface: selectedSurface)
            isLoadingIntelligence = false
        } catch {
            intelligence = nil
            isLoadingIntelligence = false
        }
    }

    func loadDashboardForSelectedOddsetMatch() async {
        guard let match = selectedOddsetMatch else {
            dashboard = nil
            return
        }

        isLoadingDashboard = true
        do {
            let database = ATPDatabase(settings: databaseSettings)
            dashboard = try await database.loadDashboard(match: match, surface: selectedSurface)
            isLoadingDashboard = false
        } catch {
            dashboard = nil
            isLoadingDashboard = false
        }
    }

    private func sortMatches(_ lhs: TennisMatch, _ rhs: TennisMatch) -> Bool {
        lhs.date > rhs.date
    }

    private func loadDatabaseSnapshot() async -> Result<(matches: [TennisMatch], rankings: [RankedPlayer]), Error> {
        do {
            let database = ATPDatabase(settings: databaseSettings)
            return .success(try await database.loadSnapshot())
        } catch {
            return .failure(error)
        }
    }

    private func loadOddsetMatches() async -> Result<[OddsetMatch], Error> {
        do {
            let matches = try await OddsetClient().loadMatches()
            let database = ATPDatabase(settings: databaseSettings)
            return .success((try? await database.enrichMatches(matches)) ?? matches)
        } catch {
            return .failure(error)
        }
    }
}
