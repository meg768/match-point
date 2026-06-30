import Foundation

@MainActor
final class MatchRoomStore: ObservableObject {
    @Published var apiBaseURL = SettingsStore.loadAPIBaseURL()
    @Published var matches: [TennisMatch] = []
    @Published var rankings: [RankedPlayer] = []
    @Published var selectedMatchID: Int?
    @Published var selectedSurface = SettingsStore.loadModelSurface()
    @Published var intelligence: MatchIntelligence?
    @Published var isLoading = false
    @Published var isLoadingIntelligence = false
    @Published var status: MatchRoomStatus = .idle
    @Published var serviceVersion = "-"

    var selectedMatch: TennisMatch? {
        matches.first { $0.id == selectedMatchID } ?? matches.first
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
        status = .loading("Refreshing tennis room...")

        do {
            let api = MatchRoomAPI(baseURLString: apiBaseURL)
            async let ping = api.ping()
            async let oddset = api.oddsetMatches()
            async let rankingRows = api.rankings(top: 30)

            let (servicePing, fetchedMatches, fetchedRankings) = try await (ping, oddset, rankingRows)
            serviceVersion = servicePing.version
            matches = fetchedMatches.sorted(by: sortMatches)
            rankings = fetchedRankings

            if selectedMatchID == nil || !matches.contains(where: { $0.id == selectedMatchID }) {
                selectedMatchID = matches.first?.id
            }

            isLoading = false
            status = .ready("Loaded \(matches.count) matches and \(rankings.count) ranked players.")
            await loadIntelligenceForSelectedMatch()
        } catch {
            isLoading = false
            status = .failed(error.localizedDescription)
        }
    }

    func select(match: TennisMatch) {
        selectedMatchID = match.id
        intelligence = nil
        Task {
            await loadIntelligenceForSelectedMatch()
        }
    }

    func changeSurface(_ surface: TennisSurface) {
        selectedSurface = surface
        SettingsStore.save(modelSurface: surface)
        intelligence = nil
        Task {
            await loadIntelligenceForSelectedMatch()
        }
    }

    func saveBaseURL() {
        SettingsStore.save(apiBaseURL: apiBaseURL)
    }

    func loadIntelligenceForSelectedMatch() async {
        guard let match = selectedMatch else {
            return
        }

        let playerA = match.playerA.id ?? match.playerA.name
        let playerB = match.playerB.id ?? match.playerB.name

        isLoadingIntelligence = true
        do {
            let api = MatchRoomAPI(baseURLString: apiBaseURL)
            let odds = try await api.odds(playerA: playerA, playerB: playerB, surface: selectedSurface)
            intelligence = MatchIntelligence(matchID: match.id, surface: selectedSurface, odds: odds)
            isLoadingIntelligence = false
        } catch {
            intelligence = nil
            isLoadingIntelligence = false
        }
    }

    private func sortMatches(_ lhs: TennisMatch, _ rhs: TennisMatch) -> Bool {
        if lhs.isLive != rhs.isLive {
            return lhs.isLive && !rhs.isLive
        }

        return lhs.start < rhs.start
    }
}
