import AppKit
import SwiftUI

struct PlayerInspectorContext: Identifiable {
    enum Side {
        case playerA
        case playerB
    }

    let side: Side
    let match: OddsetMatch
    let surface: TennisSurface
    let stats: PlayerDashboardStats?
    let country: String?
    let market: Double?
    let model: Double?
    let winFactor: Double?
    let h2h: Int
    let rankingHistory: [RankingHistoryPoint]

    var id: String {
        "\(match.id)-\(side)-\(playerID)"
    }

    var fallbackPlayer: MatchPlayer {
        switch side {
        case .playerA:
            return match.playerA
        case .playerB:
            return match.playerB
        }
    }

    var displayName: String {
        stats?.name ?? fallbackPlayer.name
    }

    var displayCountry: String? {
        stats?.country ?? country ?? fallbackPlayer.country
    }

    var rank: Int? {
        stats?.rank ?? fallbackPlayer.rank
    }

    var playerID: String {
        stats?.id ?? fallbackPlayer.id ?? displayName
    }
}

struct PlayerInspectorView: View {
    let context: PlayerInspectorContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceSettings
    @State private var history: [PlayerInspectorPage] = []
    @State private var loadedStats: PlayerDashboardStats?
    @State private var loadedRankingHistory: [RankingHistoryPoint] = []
    @State private var matchTabs: [PlayerMatchTab] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlayerInspectorOverviewSection(stats: stats, surface: currentPage.surface)
                    PlayerInspectorTitlesSection(stats: stats)
                    PlayerInspectorRankingSection(history: rankingHistory, isLoading: isLoading, hasLoaded: hasLoaded)
                    PlayerInspectorMatchesSection(
                        tabs: matchTabs,
                        isLoading: isLoading,
                        hasLoaded: hasLoaded,
                        onSelectPlayer: navigate(to:)
                    )

                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
        }
        .id("\(appearance.mode.rawValue)-\(appearance.surface.rawValue)")
        .frame(minWidth: 1260, minHeight: 780)
        .background(AppColors.panelBackground)
        .task(id: currentPage.id) {
            await loadProfile()
        }
    }

    private var currentPage: PlayerInspectorPage {
        history.last ?? PlayerInspectorPage(context: context)
    }

    private var stats: PlayerDashboardStats? {
        loadedStats ?? currentPage.stats
    }

    private var rankingHistory: [RankingHistoryPoint] {
        if hasLoaded {
            return loadedRankingHistory
        }

        return loadedRankingHistory.isEmpty ? currentPage.rankingHistory : loadedRankingHistory
    }

    private var inspectorHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            CountryBadge(country: stats?.country ?? currentPage.country)
                .frame(width: 34, height: 34)

            Text(headerNameTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 16)

            if canGoBack {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.badgeText)
                .background(AppColors.tableRowBackground.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.badgeText)
            .background(AppColors.tableRowBackground.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColors.tableRowBackground.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.85), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private var headerNameTitle: String {
        let name = stats?.name ?? currentPage.name
        let country = (stats?.country ?? currentPage.country).map { ", \($0)" } ?? ""
        return "\(name)\(country)"
    }

    private var canGoBack: Bool {
        history.count > 1
    }

    @MainActor
    private func loadProfile() async {
        if history.isEmpty {
            history = [PlayerInspectorPage(context: context)]
        }

        isLoading = true
        hasLoaded = false
        loadError = nil
        loadedStats = nil
        loadedRankingHistory = []
        matchTabs = []

        do {
            let profile = try await ATPDatabase(settings: SettingsStore.loadDatabaseSettings())
                .loadPlayerProfile(name: currentPage.lookupName, surface: currentPage.surface)

            guard !Task.isCancelled else {
                return
            }

            loadedStats = profile.stats
            loadedRankingHistory = profile.rankingHistory
            matchTabs = profile.matchTabs
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else {
                return
            }

            loadError = "Kunde inte läsa spelarprofil från ATP-databasen."
            hasLoaded = true
        }

        isLoading = false
    }

    private func navigate(to player: MatchPlayer) {
        let page = PlayerInspectorPage(player: player, surface: currentPage.surface)
        if currentPage.id == page.id {
            return
        }

        history.append(page)
    }

    private func goBack() {
        guard history.count > 1 else {
            return
        }

        history.removeLast()
    }
}

private struct PlayerInspectorPage: Identifiable, Equatable {
    let id: String
    let lookupName: String
    let name: String
    let country: String?
    let rank: Int?
    let surface: TennisSurface
    let stats: PlayerDashboardStats?
    let rankingHistory: [RankingHistoryPoint]

    init(context: PlayerInspectorContext) {
        id = context.playerID
        lookupName = context.playerID
        name = context.displayName
        country = context.displayCountry
        rank = context.rank
        surface = context.surface
        stats = context.stats
        rankingHistory = context.rankingHistory
    }

    init(player: MatchPlayer, surface: TennisSurface) {
        id = player.id ?? player.name
        lookupName = player.id ?? player.name
        name = player.name
        country = player.country
        rank = player.rank
        self.surface = surface
        stats = nil
        rankingHistory = []
    }
}

struct PlayerInspectorOverviewSection: View {
    let stats: PlayerDashboardStats?
    let surface: TennisSurface

    var body: some View {
        PlayerInspectorSection(title: "Översikt") {
            PlayerInspectorOverviewGrid(stats: stats, surface: surface)
        }
    }
}

struct PlayerInspectorOverviewGrid: View {
    let stats: PlayerDashboardStats?
    let surface: TennisSurface
    private let avatarWidth: CGFloat = 150
    private let rowHeight: CGFloat = 62

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(136, (proxy.size.width - avatarWidth) / 7)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    PlayerInspectorAvatarCell(stats: stats)
                        .frame(width: avatarWidth)
                        .frame(height: rowHeight * 3)

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            summaryCell("Ålder", stats?.age.map(String.init) ?? "-", width: columnWidth)
                            summaryCell("Längd/vikt/BMI", physicalValue, width: columnWidth)
                            summaryCell("ELO", stats?.eloRank.map(String.init) ?? "-", width: columnWidth)
                            summaryCell("Hard/Clay/Grass", surfaceEloValue, width: columnWidth)
                            summaryCell("Serve", rating(stats?.serveRating), width: columnWidth)
                            summaryCell("Retur", rating(stats?.returnRating), width: columnWidth)
                            summaryCell("Underläge", rating(stats?.pressureRating), width: columnWidth)
                        }

                        HStack(spacing: 0) {
                            summaryCell("YTD", currentYear, width: columnWidth)
                            summaryCell("Ranking", stats?.rank.map(String.init) ?? "-", width: columnWidth)
                            summaryCell("Titlar", stats?.ytdTitles.map(String.init) ?? "-", width: columnWidth)
                            summaryCell("Vinster", recordWithPercent(wins: stats?.ytdWins, losses: stats?.ytdLosses), width: columnWidth)
                            summaryCell("Förluster", lossesWithPercent(wins: stats?.ytdWins, losses: stats?.ytdLosses), width: columnWidth)
                            summaryCell("Matcher", ytdMatches, width: columnWidth)
                            summaryCell("Prispengar", money(stats?.ytdPrize), width: columnWidth)
                        }

                        HStack(spacing: 0) {
                            summaryCell("Karriär", careerYears, width: columnWidth)
                            summaryCell("Ranking", highestRankValue, width: columnWidth)
                            summaryCell("Titlar", stats?.careerTitles.map(String.init) ?? "-", width: columnWidth)
                            summaryCell("Vinster", recordWithPercent(wins: stats?.totalWins, losses: stats?.totalLosses), width: columnWidth)
                            summaryCell("Förluster", lossesWithPercent(wins: stats?.totalWins, losses: stats?.totalLosses), width: columnWidth)
                            summaryCell("Matcher", stats.map { String($0.totalMatches) } ?? "-", width: columnWidth)
                            summaryCell("Prispengar", money(stats?.careerPrize), width: columnWidth)
                        }
                    }
                }
                .frame(width: avatarWidth + (columnWidth * 7), alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .frame(height: rowHeight * 3)
        .background(AppColors.panelBackground.opacity(0.22))
    }

    private func summaryCell(_ label: String, _ value: String, width: CGFloat) -> some View {
        ProfileGridCell(
            label: label,
            value: value,
            minHeight: rowHeight,
            width: width,
            horizontalPadding: 9
        )
    }

    private var physicalValue: String {
        let height = stats?.height.map(String.init) ?? "-"
        let weight = stats?.weight.map(String.init) ?? "-"
        let bmi = stats?.bmi.map { String(Int($0.rounded())) } ?? "-"
        return "\(height)/\(weight)/\(bmi)"
    }

    private var highestRankValue: String {
        guard let highestRank = stats?.highestRank else {
            return "-"
        }

        if let date = stats?.highestRankDate?.nonEmpty {
            return "\(highestRank) (\(date))"
        }

        return "\(highestRank)"
    }

    private var surfaceEloValue: String {
        guard let stats else {
            return "-"
        }

        let hard = stats.hardElo.map(String.init) ?? "-"
        let clay = stats.clayElo.map(String.init) ?? "-"
        let grass = stats.grassElo.map(String.init) ?? "-"
        return "\(hard)/\(clay)/\(grass)"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    private var careerYears: String {
        guard let pro = stats?.pro else {
            return "-"
        }

        return "\(pro) - \(currentYear)"
    }

    private var ytdMatches: String {
        guard let stats else {
            return "-"
        }

        return String((stats.ytdWins ?? 0) + (stats.ytdLosses ?? 0))
    }

    private func money(_ value: Int?) -> String {
        AppFormat.dollars(value)
    }

    private func rating(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func recordWithPercent(wins: Int?, losses: Int?) -> String {
        let wins = wins ?? 0
        let losses = losses ?? 0
        let total = wins + losses
        guard total > 0 else {
            return "-"
        }

        return "\(wins) (\(Int((Double(wins) / Double(total) * 100).rounded()))%)"
    }

    private func lossesWithPercent(wins: Int?, losses: Int?) -> String {
        let wins = wins ?? 0
        let losses = losses ?? 0
        let total = wins + losses
        guard total > 0 else {
            return "-"
        }

        return "\(losses) (\(Int((Double(losses) / Double(total) * 100).rounded()))%)"
    }
}

struct PlayerInspectorAvatarCell: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        ZStack {
            PlayerHeadshot(url: stats?.imageURL, name: stats?.name ?? "")
                .frame(width: 118, height: 118)
                .overlay {
                    Circle()
                        .stroke(AppColors.primaryStrong.opacity(0.82), lineWidth: 1.5)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(width: 1)
        }
    }
}

struct PlayerInspectorTitlesSection: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        PlayerInspectorSection(title: "Titlar") {
            PlayerInspectorGrid {
                ProfileGridCell(label: "Grand Slam", value: stats.map { String($0.grandSlamTitles) } ?? "-")
                ProfileGridCell(label: "Masters", value: stats.map { String($0.mastersTitles) } ?? "-")
                ProfileGridCell(label: "ATP-500", value: stats.map { String($0.atp500Titles) } ?? "-")
                ProfileGridCell(label: "ATP-250", value: stats.map { String($0.atp250Titles) } ?? "-")
            }
        }
    }
}

struct PlayerInspectorRankingSection: View {
    let history: [RankingHistoryPoint]
    let isLoading: Bool
    let hasLoaded: Bool
    @State private var selectedRange: RankingHistoryRange = .twoYears

    var body: some View {
        PlayerInspectorSection(title: "Ranking") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    RankingRangePicker(selectedRange: $selectedRange)
                }

                if !filteredHistory.isEmpty {
                    PlayerInspectorRankingChart(points: filteredHistory)
                        .frame(height: 178)
                        .padding(12)
                        .background(AppColors.panelBackground.opacity(0.22))
                } else if isLoading && !hasLoaded {
                    PlayerInspectorEmptyBlock(text: "Läser rankinghistorik...")
                } else {
                    PlayerInspectorEmptyBlock(text: "Ingen rankinghistorik i ATP-databasen.")
                }
            }
            .padding(14)
            .background(AppColors.tableRowBackground)
        }
    }

    private var filteredHistory: [RankingHistoryPoint] {
        guard let cutoff = selectedRange.cutoffMonth else {
            return history
        }

        return history.filter { $0.month >= cutoff }
    }
}

struct PlayerInspectorMatchesSection: View {
    let tabs: [PlayerMatchTab]
    let isLoading: Bool
    let hasLoaded: Bool
    let onSelectPlayer: (MatchPlayer) -> Void
    @State private var selectedTabID: String?
    @State private var sortKey: PlayerInspectorMatchSortKey = .date
    @State private var sortAscending = false

    private var selectedTab: PlayerMatchTab? {
        if let selectedTabID, let tab = tabs.first(where: { $0.id == selectedTabID }) {
            return tab
        }

        return tabs.first
    }

    private var sortedMatches: [TennisMatch] {
        guard let selectedTab else {
            return []
        }

        return selectedTab.matches.sorted { left, right in
            let comparison = sortKey.compare(left, right)
            if comparison == .orderedSame {
                return left.date > right.date
            }

            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var body: some View {
        PlayerInspectorSection(title: "Matcher") {
            VStack(alignment: .leading, spacing: 10) {
                if !tabs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            PlayerInspectorMatchTabButton(
                                title: tab.title,
                                isSelected: selectedTab?.id == tab.id
                            ) {
                                selectedTabID = tab.id
                            }
                        }
                    }
                }

                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        PlayerInspectorMatchesHeader(
                            sortKey: sortKey,
                            sortAscending: sortAscending,
                            onSort: sort
                        )

                        if selectedTab != nil {
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(sortedMatches) { match in
                                        PlayerInspectorMatchRow(match: match, onSelectPlayer: onSelectPlayer)
                                    }
                                }
                            }
                            .frame(height: 432)
                            .scrollIndicators(.visible)
                        } else if isLoading && !hasLoaded {
                            PlayerInspectorTableMessage(text: "Läser matcher...")
                                .frame(height: 432, alignment: .top)
                        } else {
                            PlayerInspectorTableMessage(text: "Ingen matchhistorik i ATP-databasen.")
                                .frame(height: 432, alignment: .top)
                        }
                    }
                    .frame(minWidth: 1180)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                }
            }
            .padding(12)
            .background(AppColors.panelBackground.opacity(0.22))
        }
        .onChange(of: tabs.map(\.id)) { _, ids in
            if let selectedTabID, ids.contains(selectedTabID) {
                return
            }

            selectedTabID = ids.first
        }
    }

    private func sort(_ key: PlayerInspectorMatchSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = key.defaultAscending
        }
    }
}

struct PlayerInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title)
            content
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                }
        }
    }
}

struct PlayerInspectorGrid<Content: View>: View {
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            content
        }
        .background(AppColors.panelBackground.opacity(0.22))
    }
}

struct PlayerInspectorMatchTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppPill(title, isActive: isSelected, height: 28, activeStrokeOpacity: 0.75)
        }
        .buttonStyle(.plain)
    }
}

struct PlayerInspectorMatchesHeader: View {
    let sortKey: PlayerInspectorMatchSortKey
    let sortAscending: Bool
    let onSort: (PlayerInspectorMatchSortKey) -> Void

    var body: some View {
        HStack(spacing: 10) {
            header("Datum", key: .date, width: 88, alignment: .leading)
            header("Turnering", key: .tournament, alignment: .leading)
            header("Underlag", key: .surface, width: 76, alignment: .leading)
            header("Runda", key: .round, width: 56, alignment: .leading)
            header("Vinnare", key: .winner, alignment: .leading)
            header("Förlorare", key: .loser, alignment: .leading)
            header("Resultat", key: .score, width: 112, alignment: .trailing)
            header("Speltid", key: .duration, width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(AppColors.panelBackground.opacity(0.42))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private func header(_ text: String, key: PlayerInspectorMatchSortKey, width: CGFloat? = nil, alignment: Alignment) -> some View {
        Button {
            onSort(key)
        } label: {
            HStack(spacing: 3) {
                Text(text)
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(sortKey == key ? AppColors.primaryStrong : AppColors.caption.opacity(0.64))
            .textCase(.uppercase)
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        }
        .buttonStyle(.plain)
    }
}

struct PlayerInspectorMatchRow: View {
    let match: TennisMatch
    let onSelectPlayer: (MatchPlayer) -> Void

    var body: some View {
        HStack(spacing: 10) {
            cell(match.date, width: 88, alignment: .leading)
            cell(tournamentTitle, alignment: .leading)
            cell(match.surface ?? "-", width: 76, alignment: .leading)
            cell(match.round ?? "-", width: 56, alignment: .leading)
            PlayerInspectorMatchPlayerCell(player: match.playerA, alignment: .leading, onSelectPlayer: onSelectPlayer)
            PlayerInspectorMatchPlayerCell(player: match.playerB, alignment: .leading, onSelectPlayer: onSelectPlayer)
            cell(match.displayScore, width: 112, alignment: .trailing)
            cell(match.duration?.nonEmpty ?? "-", width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private var tournamentTitle: String {
        guard let eventType = match.eventType?.nonEmpty else {
            return match.tournament
        }

        return "\(match.tournament) (\(eventType))"
    }

    private func cell(_ text: String, width: CGFloat? = nil, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppColors.heading)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

struct PlayerInspectorMatchPlayerCell: View {
    let player: MatchPlayer
    let alignment: Alignment
    let onSelectPlayer: (MatchPlayer) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onSelectPlayer(player)
        } label: {
            Text(playerTitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isHovering ? AppColors.playerLinkHover : AppColors.primaryStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var playerTitle: String {
        if let rank = player.rank {
            return "\(player.name) (\(rank))"
        }

        return player.name
    }
}

enum PlayerInspectorMatchSortKey {
    case date
    case tournament
    case surface
    case round
    case winner
    case loser
    case score
    case duration

    var defaultAscending: Bool {
        switch self {
        case .date:
            return false
        case .duration:
            return false
        case .round:
            return true
        case .tournament, .surface, .winner, .loser, .score:
            return true
        }
    }

    func compare(_ left: TennisMatch, _ right: TennisMatch) -> ComparisonResult {
        switch self {
        case .date:
            return left.date.compare(right.date)
        case .tournament:
            return compareText(left.tournament, right.tournament)
        case .surface:
            return compareText(left.surface, right.surface)
        case .round:
            return compareInt(roundRank(left.round), roundRank(right.round))
        case .winner:
            return compareText(left.playerA.name, right.playerA.name)
        case .loser:
            return compareText(left.playerB.name, right.playerB.name)
        case .score:
            return compareText(left.displayScore, right.displayScore)
        case .duration:
            return compareInt(durationMinutes(left.duration), durationMinutes(right.duration))
        }
    }

    private func compareText(_ left: String?, _ right: String?) -> ComparisonResult {
        (left ?? "").localizedStandardCompare(right ?? "")
    }

    private func compareInt(_ left: Int, _ right: Int) -> ComparisonResult {
        if left < right {
            return .orderedAscending
        }
        if left > right {
            return .orderedDescending
        }
        return .orderedSame
    }

    private func roundRank(_ round: String?) -> Int {
        let rounds = ["F", "SF", "QF", "R16", "R32", "R64", "R128", "Q3", "Q2", "Q1", "RR", "RR2", "RR3", "RR4", "RR5", "RR6", "BR"]
        return rounds.firstIndex(of: round ?? "") ?? rounds.count
    }

    private func durationMinutes(_ duration: String?) -> Int {
        guard let duration = duration?.nonEmpty else {
            return -1
        }

        let parts = duration.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            return -1
        }

        return parts[0] * 60 + parts[1]
    }
}

struct PlayerInspectorTableMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(AppColors.panelBackground.opacity(0.22))
    }
}

struct PlayerInspectorEmptyBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.badgeText)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            .background(AppColors.panelBackground.opacity(0.22))
    }
}

struct PlayerInspectorRankingChart: View {
    let points: [RankingHistoryPoint]

    private let leftInset: CGFloat = 42
    private let bottomInset: CGFloat = 24
    private let topInset: CGFloat = 8
    private let rightInset: CGFloat = 12

    private var maxRank: Int {
        let observed = points.map(\.rank).max() ?? 100
        return max(25, min(300, Int(ceil(Double(observed) / 25) * 25)))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                chartGrid(size: proxy.size)
                rankingPath(size: proxy.size)
                    .stroke(AppColors.primaryStrong, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                pointMarks(size: proxy.size)
            }
        }
    }

    private func chartGrid(size: CGSize) -> some View {
        Canvas { context, _ in
            let rect = chartRect(size: size)
            let gridColor = Color(nsColor: NSColor(AppColors.primaryStrong).withAlphaComponent(0.35))
            let labelColor = Color(nsColor: NSColor(AppColors.heading).withAlphaComponent(0.75))

            for step in 0...4 {
                let rank = max(1, Int(round(Double(maxRank) * Double(step) / 4)))
                let y = yPosition(rank: rank, rect: rect)
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: y))
                line.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(line, with: .color(gridColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                context.draw(Text("\(rank)").font(.system(size: 11, weight: .bold)).foregroundStyle(labelColor), at: CGPoint(x: 18, y: y), anchor: .leading)
            }

            let labels = monthLabels()
            for label in labels {
                guard let index = points.firstIndex(where: { $0.month == label }) else {
                    continue
                }

                let x = xPosition(index: index, count: points.count, rect: rect)
                var line = Path()
                line.move(to: CGPoint(x: x, y: rect.minY))
                line.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(line, with: .color(gridColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                context.draw(Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(labelColor), at: CGPoint(x: x, y: rect.maxY + 14), anchor: .center)
            }

            var border = Path()
            border.addRect(rect)
            context.stroke(border, with: .color(AppColors.panelBorder), lineWidth: 1)
        }
    }

    private func rankingPath(size: CGSize) -> Path {
        let rect = chartRect(size: size)
        var path = Path()

        for (index, point) in points.enumerated() {
            let cgPoint = CGPoint(
                x: xPosition(index: index, count: points.count, rect: rect),
                y: yPosition(rank: point.rank, rect: rect)
            )

            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }

        return path
    }

    private func pointMarks(size: CGSize) -> some View {
        let rect = chartRect(size: size)

        return ZStack {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Circle()
                    .fill(AppColors.panelBackground)
                    .overlay {
                        Circle().stroke(AppColors.primaryStrong, lineWidth: 2)
                    }
                    .frame(width: 6, height: 6)
                    .position(
                        x: xPosition(index: index, count: points.count, rect: rect),
                        y: yPosition(rank: point.rank, rect: rect)
                    )
            }
        }
    }

    private func chartRect(size: CGSize) -> CGRect {
        CGRect(
            x: leftInset,
            y: topInset,
            width: max(1, size.width - leftInset - rightInset),
            height: max(1, size.height - topInset - bottomInset)
        )
    }

    private func xPosition(index: Int, count: Int, rect: CGRect) -> CGFloat {
        guard count > 1 else {
            return rect.midX
        }

        return rect.minX + rect.width * CGFloat(index) / CGFloat(count - 1)
    }

    private func yPosition(rank: Int, rect: CGRect) -> CGFloat {
        let clamped = min(max(1, rank), maxRank)
        let ratio = CGFloat(clamped - 1) / CGFloat(max(1, maxRank - 1))
        return rect.minY + rect.height * ratio
    }

    private func monthLabels() -> [String] {
        guard points.count > 4 else {
            return points.map(\.month)
        }

        let step = max(1, points.count / 4)
        var labels = stride(from: 0, to: points.count, by: step).map { points[$0].month }
        if labels.last != points.last?.month, let last = points.last?.month {
            labels.append(last)
        }
        return labels
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
