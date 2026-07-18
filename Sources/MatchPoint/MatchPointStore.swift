import Foundation

@MainActor
final class MatchPointStore: ObservableObject {
    @Published var apiSettings = SettingsStore.loadAPISettings()
    @Published var matches: [TennisMatch] = []
    @Published var oddsetMatches: [OddsetMatch] = []
    @Published var rankings: [RankedPlayer] = []
    @Published var selectedMatchID: String?
    @Published var selectedOddsetMatchID: String?
    @Published var playerSearchResults: [RankedPlayer] = []
    @Published var selectedPlayerID: String?
    @Published var selectedPlayerProfile: PlayerWorkspaceProfile?
    @Published var comparePlayerA: RankedPlayer?
    @Published var comparePlayerB: RankedPlayer?
    @Published var playerComparison: PlayerComparison?
    @Published var dataLog: [DataLogEntry] = []
    @Published var surfaceMode = SettingsStore.loadSurfaceMode()
    @Published var selectedSurface = SettingsStore.loadSurfaceMode().surface ?? .grass
    @Published var intelligence: MatchIntelligence?
    @Published var dashboard: MatchDashboard?
    @Published var isLoading = false
    @Published var isLoadingIntelligence = false
    @Published var isLoadingDashboard = false
    @Published var isLoadingPlayers = false
    @Published var isLoadingPlayerProfile = false
    @Published var isLoadingComparison = false
    @Published var status: MatchPointStatus = .idle
    private var dashboardLoadGeneration = 0
    private var playerSearchGeneration = 0
    private var playerProfileGeneration = 0
    private var comparisonGeneration = 0
    private var dashboardCache: [DashboardCacheKey: MatchDashboard] = [:]

    var selectedMatch: TennisMatch? {
        matches.first { $0.id == selectedMatchID } ?? matches.first
    }

    var selectedOddsetMatch: OddsetMatch? {
        oddsetMatches.first { $0.id == selectedOddsetMatchID } ?? oddsetMatches.first
    }

    var selectedPlayer: RankedPlayer? {
        playerSearchResults.first { $0.player == selectedPlayerID } ?? playerSearchResults.first
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
        let startedAt = Date()

        let oddsetSnapshot = await loadOddsetMatches()

        switch oddsetSnapshot {
        case .success(let matches):
            recordLog(
                source: "Oddset",
                operation: "Läs matcher",
                detail: "\(matches.filter { $0.state == .live }.count) live, \(matches.filter { $0.state == .upcoming }.count) kommande",
                startedAt: startedAt,
                status: .success
            )
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
            recordLog(
                source: "Oddset",
                operation: "Läs matcher",
                detail: "Matcher är inte tillgängliga",
                startedAt: startedAt,
                status: .failed
            )
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

    func searchPlayers(query: String) {
        Task {
            await searchPlayersNow(query: query)
        }
    }

    func select(player: RankedPlayer) {
        guard selectedPlayerID != player.player else {
            return
        }

        selectedPlayerID = player.player
        selectedPlayerProfile = nil
        Task {
            await loadSelectedPlayerProfile()
        }
    }

    func focus(player: RankedPlayer) {
        if !playerSearchResults.contains(where: { $0.player == player.player }) {
            playerSearchResults.insert(player, at: 0)
        }

        selectedPlayerID = player.player
        selectedPlayerProfile = nil
        Task {
            await loadSelectedPlayerProfile()
        }
    }

    func setComparePlayer(_ player: RankedPlayer, slot: ComparisonSlot) {
        switch slot {
        case .playerA:
            comparePlayerA = player
        case .playerB:
            comparePlayerB = player
        }

        Task {
            await loadPlayerComparison()
        }
    }

    func setComparePlayers(playerA: RankedPlayer, playerB: RankedPlayer) {
        comparePlayerA = playerA
        comparePlayerB = playerB

        Task {
            await loadPlayerComparison()
        }
    }

    func clearComparePlayer(_ slot: ComparisonSlot) {
        switch slot {
        case .playerA:
            comparePlayerA = nil
        case .playerB:
            comparePlayerB = nil
        }

        comparisonGeneration += 1
        playerComparison = nil
        isLoadingComparison = false
    }

    func swapComparePlayers() {
        guard comparePlayerA != nil || comparePlayerB != nil else {
            return
        }

        let previousA = comparePlayerA
        comparePlayerA = comparePlayerB
        comparePlayerB = previousA

        Task {
            await loadPlayerComparison()
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
            await loadSelectedPlayerProfile()
            await loadPlayerComparison()
        }
    }

    func saveAPISettings() {
        SettingsStore.save(apiSettings: apiSettings)
        dashboardCache.removeAll()
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
            let database = ATPDatabase(settings: apiSettings)
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
        let cacheKey = DashboardCacheKey(match: match, surface: requestedSurface)

        if let cachedDashboard = dashboardCache[cacheKey] {
            recordLog(
                source: "ATP",
                operation: "Matchöversikt",
                detail: "\(match.playerA.name) vs \(match.playerB.name) · \(requestedSurface.title)",
                startedAt: Date(),
                status: .cache
            )
            dashboard = cachedDashboard
            isLoadingDashboard = false
            return
        }

        isLoadingDashboard = true

        let database = ATPDatabase(settings: apiSettings)
        var hasOverview = false
        let startedAt = Date()

        if let overviewDashboard = try? await database.loadDashboardOverview(match: match, surface: requestedSurface) {
            guard dashboardLoadGeneration == generation, selectedOddsetMatchID == requestedMatchID, selectedSurface == requestedSurface else {
                return
            }

            dashboard = overviewDashboard
            hasOverview = true
            recordLog(
                source: "ATP",
                operation: "Matchöversikt snabb",
                detail: "\(match.playerA.name) vs \(match.playerB.name) · \(requestedSurface.title)",
                startedAt: startedAt,
                status: .success
            )
        }

        do {
            let fullStartedAt = Date()
            let loadedDashboard = try await database.loadDashboard(match: match, surface: requestedSurface)
            guard dashboardLoadGeneration == generation, selectedOddsetMatchID == requestedMatchID, selectedSurface == requestedSurface else {
                return
            }

            dashboard = loadedDashboard
            dashboardCache[cacheKey] = loadedDashboard
            recordLog(
                source: "ATP",
                operation: "Matchöversikt komplett",
                detail: "\(match.playerA.name) vs \(match.playerB.name) · \(requestedSurface.title)",
                startedAt: fullStartedAt,
                status: .success
            )
            isLoadingDashboard = false
        } catch {
            guard dashboardLoadGeneration == generation, selectedOddsetMatchID == requestedMatchID, selectedSurface == requestedSurface else {
                return
            }

            if !hasOverview {
                dashboard = nil
            }
            recordLog(
                source: "ATP",
                operation: "Matchöversikt komplett",
                detail: error.localizedDescription,
                startedAt: startedAt,
                status: .failed
            )
            status = .failed("ATP-data saknas: \(error.localizedDescription)")
            isLoadingDashboard = false
        }
    }

    func searchPlayersNow(query: String) async {
        playerSearchGeneration += 1
        let generation = playerSearchGeneration
        let startedAt = Date()
        isLoadingPlayers = true

        do {
            let database = ATPDatabase(settings: apiSettings)
            let players = try await database.searchPlayers(query: query)
            guard playerSearchGeneration == generation else {
                return
            }

            playerSearchResults = players
            recordLog(
                source: "ATP",
                operation: "Sök spelare",
                detail: "\(query.isEmpty ? "Topplista" : query) · \(players.count) träffar",
                startedAt: startedAt,
                status: .success
            )
            if selectedPlayerID == nil || !players.contains(where: { $0.player == selectedPlayerID }) {
                selectedPlayerID = players.first?.player
                selectedPlayerProfile = nil
            }
            isLoadingPlayers = false

            if selectedPlayerProfile == nil {
                await loadSelectedPlayerProfile()
            }
        } catch {
            guard playerSearchGeneration == generation else {
                return
            }

            playerSearchResults = []
            recordLog(
                source: "ATP",
                operation: "Sök spelare",
                detail: error.localizedDescription,
                startedAt: startedAt,
                status: .failed
            )
            selectedPlayerID = nil
            selectedPlayerProfile = nil
            isLoadingPlayers = false
        }
    }

    func loadSelectedPlayerProfile() async {
        guard let player = selectedPlayer else {
            selectedPlayerProfile = nil
            return
        }

        playerProfileGeneration += 1
        let generation = playerProfileGeneration
        let requestedPlayerID = player.player
        let requestedSurface = selectedSurface
        let startedAt = Date()
        isLoadingPlayerProfile = true

        do {
            let profile = try await ATPDatabase(settings: apiSettings)
                .loadPlayerProfile(name: requestedPlayerID, surface: requestedSurface)
            guard playerProfileGeneration == generation, selectedPlayerID == requestedPlayerID, selectedSurface == requestedSurface else {
                return
            }

            selectedPlayerProfile = PlayerWorkspaceProfile(
                stats: profile.stats,
                rankingHistory: profile.rankingHistory,
                matchTabs: profile.matchTabs
            )
            recordLog(
                source: "ATP",
                operation: "Spelarprofil",
                detail: "\(player.name) · \(requestedSurface.title)",
                startedAt: startedAt,
                status: .success
            )
            isLoadingPlayerProfile = false
        } catch {
            guard playerProfileGeneration == generation, selectedPlayerID == requestedPlayerID, selectedSurface == requestedSurface else {
                return
            }

            selectedPlayerProfile = nil
            recordLog(
                source: "ATP",
                operation: "Spelarprofil",
                detail: error.localizedDescription,
                startedAt: startedAt,
                status: .failed
            )
            isLoadingPlayerProfile = false
        }
    }

    func loadPlayerComparison() async {
        guard let comparePlayerA, let comparePlayerB else {
            playerComparison = nil
            return
        }

        comparisonGeneration += 1
        let generation = comparisonGeneration
        let playerAID = comparePlayerA.player
        let playerBID = comparePlayerB.player
        let requestedSurface = selectedSurface
        let startedAt = Date()
        isLoadingComparison = true

        do {
            let comparison = try await ATPDatabase(settings: apiSettings)
                .loadPlayerComparison(playerA: playerAID, playerB: playerBID, surface: requestedSurface)
            guard comparisonGeneration == generation,
                  comparePlayerA.player == playerAID,
                  comparePlayerB.player == playerBID,
                  selectedSurface == requestedSurface else {
                return
            }

            playerComparison = comparison
            recordLog(
                source: "ATP",
                operation: "Jämförelse",
                detail: "\(comparePlayerA.name) vs \(comparePlayerB.name) · \(requestedSurface.title)",
                startedAt: startedAt,
                status: .success
            )
            isLoadingComparison = false
        } catch {
            guard comparisonGeneration == generation else {
                return
            }

            playerComparison = nil
            recordLog(
                source: "ATP",
                operation: "Jämförelse",
                detail: error.localizedDescription,
                startedAt: startedAt,
                status: .failed
            )
            isLoadingComparison = false
        }
    }

    private func sortMatches(_ lhs: TennisMatch, _ rhs: TennisMatch) -> Bool {
        lhs.date > rhs.date
    }

    private func loadDatabaseSnapshot() async -> Result<(matches: [TennisMatch], rankings: [RankedPlayer]), Error> {
        do {
            let database = ATPDatabase(settings: apiSettings)
            return .success(try await database.loadSnapshot())
        } catch {
            return .failure(error)
        }
    }

    private func loadOddsetMatches() async -> Result<[OddsetMatch], Error> {
        do {
            let matches = try await OddsetClient().loadMatches()
            let database = ATPDatabase(settings: apiSettings)
            return .success((try? await database.enrichMatches(matches)) ?? matches)
        } catch {
            return .failure(error)
        }
    }

    private func recordLog(source: String, operation: String, detail: String, startedAt: Date, status: DataLogEntry.Status) {
        let durationMS = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        dataLog.insert(
            DataLogEntry(
                id: UUID(),
                timestamp: Date(),
                source: source,
                operation: operation,
                detail: detail,
                durationMS: durationMS,
                status: status
            ),
            at: 0
        )

        if dataLog.count > 200 {
            dataLog.removeLast(dataLog.count - 200)
        }
    }
}

private struct DashboardCacheKey: Hashable {
    let matchID: String
    let surface: TennisSurface
    let playerA: String
    let playerB: String

    init(match: OddsetMatch, surface: TennisSurface) {
        matchID = match.id
        self.surface = surface
        playerA = match.playerA.name
        playerB = match.playerB.name
    }
}
