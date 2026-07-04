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
    private var dashboardLoadGeneration = 0

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
        status = .loading("Läser matcher...")

        let oddsetSnapshot = await loadOddsetMatches()

        switch oddsetSnapshot {
        case .success(let matches):
            oddsetMatches = matches
            if selectedOddsetMatchID == nil || !matches.contains(where: { $0.id == selectedOddsetMatchID }) {
                selectedOddsetMatchID = matches.first?.id
            }
            resolveAutomaticSurface()
            status = .ready("Laddade \(matches.filter { $0.state == .live }.count) live och \(matches.filter { $0.state == .upcoming }.count) kommande matcher.")
            if shouldReloadDashboard {
                await loadDashboardForSelectedOddsetMatch()
            }
        case .failure:
            oddsetMatches = []
            selectedOddsetMatchID = nil
            dashboard = nil
            status = .failed("Matcher är inte tillgängliga.")
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
        guard selectedOddsetMatchID != oddsetMatch.id else {
            return
        }

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

    private var shouldReloadDashboard: Bool {
        guard let selectedOddsetMatchID else {
            return false
        }

        return dashboard?.matchID != selectedOddsetMatchID || dashboard?.surface != selectedSurface
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

        dashboardLoadGeneration += 1
        let generation = dashboardLoadGeneration
        let requestedMatchID = match.id
        let requestedSurface = selectedSurface
        isLoadingDashboard = true

        do {
            let database = ATPDatabase(settings: databaseSettings)
            let loadedDashboard = try await database.loadDashboard(match: match, surface: requestedSurface)
            guard dashboardLoadGeneration == generation, selectedOddsetMatchID == requestedMatchID, selectedSurface == requestedSurface else {
                return
            }

            dashboard = loadedDashboard
            isLoadingDashboard = false
        } catch {
            guard dashboardLoadGeneration == generation, selectedOddsetMatchID == requestedMatchID, selectedSurface == requestedSurface else {
                return
            }

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
