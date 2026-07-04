import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var store = MatchPointStore()
    @State private var searchText = ""
    @State private var matchPanelWidth: CGFloat? = SettingsStore.loadMatchPanelWidth()
    @State private var matchFilter: MatchListFilter = .all
    @State private var isShowingSettings = false
    @State private var inspectedPlayer: PlayerInspectorContext?
    private let liveRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            MatchPointSplitView(
                matches: filteredOddsetMatches,
                selectedFilter: matchFilter,
                selectedMatchID: store.selectedOddsetMatchID,
                selectedMatch: store.selectedOddsetMatch,
                dashboard: store.dashboard,
                isLoadingDashboard: store.isLoadingDashboard,
                matchPanelWidth: $matchPanelWidth,
                onFilterChange: { matchFilter = $0 },
                onSelect: store.select(oddsetMatch:),
                onInspectPlayer: { inspectedPlayer = $0 }
            )
            .padding([.horizontal, .top], 8)
            .padding(.bottom, 8)

            StatusBar(status: store.status, matchCount: store.oddsetMatches.count)
        }
        .id("\(appearance.mode.rawValue)-\(appearance.surface.rawValue)")
        .frame(minWidth: 1180, minHeight: 720)
        .background(AppColors.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filtrera matcher")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Inställningar", systemImage: "gearshape")
                }

                Button {
                    store.refresh()
                } label: {
                    Label("Uppdatera", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)

            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsDialog(
                appearance: appearance,
                surfaceMode: store.surfaceMode,
                onSurfaceModeChange: { mode in
                    store.changeSurfaceMode(mode)
                    appearance.surface = AppSurfaceTheme(surface: store.selectedSurface)
                }
            )
        }
        .sheet(item: $inspectedPlayer) { context in
            PlayerInspectorView(context: context)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
        .onAppear {
            store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMatchPointSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(liveRefreshTimer) { _ in
            store.refresh()
        }
        .onChange(of: matchPanelWidth) { _, width in
            if let width {
                SettingsStore.save(matchPanelWidth: width)
            }
        }
        .modifier(FunctionKeyShortcut(keyCode: 97, functionKey: NSF6FunctionKey) {
            appearance.toggle(over: colorScheme)
        })
        .modifier(FunctionKeyShortcut(keyCode: 99, functionKey: NSF3FunctionKey) {
            appearance.cycleSurface()
        })
        .onChange(of: store.selectedSurface) { _, surface in
            appearance.surface = AppSurfaceTheme(surface: surface)
        }
    }

    private var filteredMatches: [TennisMatch] {
        guard !searchText.isEmpty else {
            return store.matches
        }

        return store.matches.filter { match in
            [
                match.tournament,
                match.playerA.name,
                match.playerB.name,
                match.score ?? "",
                match.status ?? "",
                match.surface ?? "",
                match.eventType ?? ""
            ]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredOddsetMatches: [OddsetMatch] {
        searchedOddsetMatches.filter { match in
            switch matchFilter {
            case .all:
                return true
            case .live:
                return match.state == .live
            case .upcoming:
                return match.state == .upcoming
            }
        }
    }

    private var searchedOddsetMatches: [OddsetMatch] {
        guard !searchText.isEmpty else {
            return store.oddsetMatches
        }

        return store.oddsetMatches.filter { match in
            [
                match.tournament ?? "",
                match.playerA.name,
                match.playerB.name,
                match.score ?? "",
                match.state.title
            ]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct MatchPointSplitView: View {
    let matches: [OddsetMatch]
    let selectedFilter: MatchListFilter
    let selectedMatchID: String?
    let selectedMatch: OddsetMatch?
    let dashboard: MatchDashboard?
    let isLoadingDashboard: Bool
    @Binding var matchPanelWidth: CGFloat?
    let onFilterChange: (MatchListFilter) -> Void
    let onSelect: (OddsetMatch) -> Void
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    private let dividerWidth: CGFloat = 14
    private let minMatchWidth: CGFloat = 420
    private let minDashboardWidth: CGFloat = 520
    private let defaultDashboardWidth: CGFloat = 680

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let leftWidth = clampedMatchWidth(for: availableWidth)

            HStack(alignment: .top, spacing: 0) {
                OddsetPanel(
                    matches: matches,
                    selectedFilter: selectedFilter,
                    selectedMatchID: selectedMatchID,
                    onFilterChange: onFilterChange,
                    onSelect: onSelect
                )
                .frame(width: leftWidth)
                .frame(height: availableHeight, alignment: .top)

                SplitDivider()
                    .frame(width: dividerWidth, height: availableHeight)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("MatchPointSplitView"))
                            .onChanged { value in
                                matchPanelWidth = clampedMatchWidth(
                                    value.location.x - (dividerWidth / 2),
                                    availableWidth: availableWidth
                                )
                            }
                    )

                DashboardPanel(
                    match: selectedMatch,
                    dashboard: dashboard,
                    isLoading: isLoadingDashboard,
                    onInspectPlayer: onInspectPlayer
                )
                .frame(width: max(minDashboardWidth, availableWidth - leftWidth - dividerWidth))
                .frame(height: availableHeight, alignment: .top)
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .top)
            .coordinateSpace(name: "MatchPointSplitView")
        }
    }

    private func clampedMatchWidth(for availableWidth: CGFloat) -> CGFloat {
        let preferredWidth = matchPanelWidth ?? max(minMatchWidth, availableWidth - dividerWidth - defaultDashboardWidth)
        return clampedMatchWidth(preferredWidth, availableWidth: availableWidth)
    }

    private func clampedMatchWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let maxMatchWidth = max(minMatchWidth, availableWidth - dividerWidth - minDashboardWidth)
        return min(max(width, minMatchWidth), maxMatchWidth)
    }
}

struct SplitDivider: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppColors.pageBackground)

            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.panelBorder)
                .frame(width: 6)

            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.primaryStrong.opacity(0.65))
                .frame(width: 2, height: 54)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct SettingsDialog: View {
    @ObservedObject var appearance: AppearanceSettings
    let surfaceMode: TennisSurfaceMode
    let onSurfaceModeChange: (TennisSurfaceMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Inställningar")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(AppColors.heading)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.badgeText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.softSettingsHeader)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.fieldBorder, lineWidth: 1)
            }

            SettingsSection(title: "Färgläge") {
                SettingsSegmentedControl(
                    items: AppAppearanceMode.pickerOrder,
                    selected: appearance.mode,
                    title: \.title,
                    onSelect: { appearance.mode = $0 }
                )
            }

            SettingsSection(title: "Underlag") {
                SettingsSegmentedControl(
                    items: TennisSurfaceMode.allCases,
                    selected: surfaceMode,
                    title: \.title,
                    onSelect: onSurfaceModeChange
                )
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(AppColors.settingsDialogBackground)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.heading)

            content
        }
    }
}

struct SettingsSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selected == item ? AppColors.settingsSelectedText : AppColors.heading)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(selected == item ? AppColors.settingsSelectedBackground : AppColors.settingsSegmentBackground)
                        .overlay(alignment: .trailing) {
                            if item != items.last {
                                Rectangle()
                                    .fill(AppColors.fieldBorder)
                                    .frame(width: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.fieldBorder, lineWidth: 1)
        }
    }
}

struct OddsetPanel: View {
    let matches: [OddsetMatch]
    let selectedFilter: MatchListFilter
    let selectedMatchID: String?
    let onFilterChange: (MatchListFilter) -> Void
    let onSelect: (OddsetMatch) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FieldLabel("Matcher")
                Spacer()
                MatchFilterPill(title: "Alla", isSelected: selectedFilter == .all) {
                    onFilterChange(.all)
                }
                MatchFilterPill(title: "Live", isSelected: selectedFilter == .live) {
                    onFilterChange(.live)
                }
                MatchFilterPill(title: "Kommande", isSelected: selectedFilter == .upcoming) {
                    onFilterChange(.upcoming)
                }
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(matches) { match in
                        OddsetRow(
                            match: match,
                            isSelected: selectedMatchID == match.id,
                            action: {
                                onSelect(match)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct OddsetRow: View {
    let match: OddsetMatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PillLabel(match.state.title, isActive: match.state == .live)
                    Text(match.tournament ?? "Match")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(match.startTitleWithOdds)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.badgeText)
                }

                CompactMatchLine(match: match)

            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColors.selectionBackground : AppColors.tableRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppColors.primary.opacity(0.75) : AppColors.panelBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct CompactMatchLine: View {
    let match: OddsetMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            matchupLine
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(AppColors.heading)
    }

    private var matchupLine: some View {
        HStack(spacing: 6) {
            playerToken(match.playerA, isServing: match.serve == "playerA")

            Text("vs")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.badgeText)
                .fixedSize()

            playerToken(match.playerB, isServing: match.serve == "playerB")

            if let scoreText {
                Spacer(minLength: 8)
                Text(scoreText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.primaryStrong)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(3)
            }
        }
        .lineLimit(1)
    }

    private func playerToken(_ player: MatchPlayer, isServing: Bool) -> some View {
        HStack(spacing: 5) {
            CountryBadge(country: player.country)
                .frame(width: 18, height: 18)
            Text(playerTitle(player))
                .lineLimit(1)
                .truncationMode(.tail)
            if isServing {
                Text("🎾")
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(isServing ? 2 : 1)
    }

    private func playerTitle(_ player: MatchPlayer) -> String {
        let country = player.country.map { " (\($0))" } ?? ""
        let rank = player.rank.map { " #\($0)" } ?? ""
        return "\(player.name)\(country)\(rank)"
    }

    private var scoreText: String? {
        match.score?.nonEmpty
    }

}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension OddsetMatch {
    var startTitleWithOdds: String {
        guard let oddsPairText else {
            return startTitle
        }

        return "\(startTitle) \(oddsPairText)"
    }

    var oddsPairText: String? {
        guard let oddsA = playerA.odds, let oddsB = playerB.odds else {
            return nil
        }

        return "(\(formatOdds(oddsA))-\(formatOdds(oddsB)))"
    }
}

struct MatchFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(isSelected ? AppColors.primaryStrong : AppColors.badgeText)
                .background(isSelected ? AppColors.badgeBackground : AppColors.neutralBadgeBackground)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? AppColors.primary.opacity(0.75) : AppColors.fieldBorder, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DashboardPanel: View {
    let match: OddsetMatch?
    let dashboard: MatchDashboard?
    let isLoading: Bool
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel("Matchöversikt")

                if let match {
                    MatchOverviewPanel(match: match, dashboard: dashboard, onInspectPlayer: onInspectPlayer)
                    RankingHistoryPanel(match: match, dashboard: dashboard)
                } else {
                    EmptyState(text: "Ingen live eller kommande match vald.", systemImage: "tennisball")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct MatchTitleLine: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?

    var body: some View {
        HStack(spacing: 9) {
            CountryBadge(country: dashboard?.playerA?.country)
                .frame(width: 22, height: 22)
            Text(playerTitle(name: match.playerA.name, stats: dashboard?.playerA))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("vs")
                .foregroundStyle(AppColors.badgeText)

            CountryBadge(country: dashboard?.playerB?.country)
                .frame(width: 22, height: 22)
            Text(playerTitle(name: match.playerB.name, stats: dashboard?.playerB))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if match.state == .live {
                Text("🎾")
            }
        }
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(AppColors.heading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playerTitle(name: String, stats: PlayerDashboardStats?) -> String {
        let country = stats?.country.map { " (\($0))" } ?? ""
        return "\(stats?.name ?? name)\(country)"
    }
}

struct MatchOverviewPanel: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PillLabel(match.state.title, isActive: match.state == .live)
                Text(match.tournament ?? "Match")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.caption)
                    .textCase(.uppercase)
                Spacer()
                Text(match.startTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.badgeText)
            }

            EqualPlayerColumns(match: match, dashboard: dashboard, onInspectPlayer: onInspectPlayer)
            PlayerEloColumns(dashboard: dashboard)
            PlayerTitleColumns(dashboard: dashboard)
            MatchSignalsPanel(title: "Skrällar", signals: dashboard?.upsetWins ?? [], emptyText: "Inga tydliga skrällar.", isPositive: true)
            MatchSignalsPanel(title: "Varningsflaggor", signals: dashboard?.warningLosses ?? [], emptyText: "Inga tydliga varningsflaggor.", isPositive: false)
            PlayerProfileColumns(dashboard: dashboard)
            HeadToHeadMatchesPanel(dashboard: dashboard)
        }
        .padding(.bottom, 2)
    }
}

struct EqualPlayerColumns: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    private let spacing: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(220, (proxy.size.width - spacing) / 2)
            let scoreWidth = min(190, max(96, columnWidth + spacing - 156))

            VStack(spacing: 12) {
                ZStack {
                    HStack(alignment: .center, spacing: spacing) {
                        PlayerIdentityCard(
                            name: match.playerA.name,
                            country: dashboard?.playerA?.country ?? match.playerA.country,
                            stats: dashboard?.playerA,
                            onInspect: inspectPlayerA
                        )
                        .frame(width: columnWidth)

                        PlayerIdentityCard(
                            name: match.playerB.name,
                            country: dashboard?.playerB?.country ?? match.playerB.country,
                            stats: dashboard?.playerB,
                            onInspect: inspectPlayerB
                        )
                        .frame(width: columnWidth)
                    }

                    if shouldShowScore, let score = match.score {
                        DashboardLiveScore(score: score, serve: match.serve)
                            .frame(width: scoreWidth, height: 132)
                            .offset(y: -34)
                            .allowsHitTesting(false)
                    }
                }

                FieldLabel("Översikt")
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: spacing) {
                    PlayerStatsTable(
                        stats: dashboard?.playerA,
                        market: match.playerA.odds,
                        model: dashboard?.modelA,
                        winFactor: dashboard?.winFactorA,
                        h2h: dashboard?.headToHeadWinsA ?? 0
                    )
                    .frame(width: columnWidth)

                    PlayerStatsTable(
                        stats: dashboard?.playerB,
                        market: match.playerB.odds,
                        model: dashboard?.modelB,
                        winFactor: dashboard?.winFactorB,
                        h2h: dashboard?.headToHeadWinsB ?? 0
                    )
                    .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 362)
    }

    private var shouldShowScore: Bool {
        match.state == .live && match.score?.nonEmpty != nil
    }

    private func inspectPlayerA() {
        onInspectPlayer(
            PlayerInspectorContext(
                side: .playerA,
                match: match,
                stats: dashboard?.playerA,
                country: dashboard?.playerA?.country ?? match.playerA.country,
                market: match.playerA.odds,
                model: dashboard?.modelA,
                winFactor: dashboard?.winFactorA,
                h2h: dashboard?.headToHeadWinsA ?? 0,
                rankingHistory: dashboard?.rankingHistoryA ?? []
            )
        )
    }

    private func inspectPlayerB() {
        onInspectPlayer(
            PlayerInspectorContext(
                side: .playerB,
                match: match,
                stats: dashboard?.playerB,
                country: dashboard?.playerB?.country ?? match.playerB.country,
                market: match.playerB.odds,
                model: dashboard?.modelB,
                winFactor: dashboard?.winFactorB,
                h2h: dashboard?.headToHeadWinsB ?? 0,
                rankingHistory: dashboard?.rankingHistoryB ?? []
            )
        )
    }
}

struct PlayerEloColumns: View {
    let dashboard: MatchDashboard?

    private let spacing: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("ELO")

            GeometryReader { proxy in
                let columnWidth = max(220, (proxy.size.width - spacing) / 2)

                HStack(alignment: .top, spacing: spacing) {
                    PlayerEloTable(stats: dashboard?.playerA)
                        .frame(width: columnWidth)
                    PlayerEloTable(stats: dashboard?.playerB)
                        .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 156)
    }
}

struct PlayerEloTable: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        VStack(spacing: 0) {
            PlayerInfoRow(label: "Totalt", value: stats?.eloRank.map(String.init) ?? "-")
            PlayerInfoRow(label: "Hardcourt", value: stats?.hardElo.map(String.init) ?? "-")
            PlayerInfoRow(label: "Grus", value: stats?.clayElo.map(String.init) ?? "-")
            PlayerInfoRow(label: "Gräs", value: stats?.grassElo.map(String.init) ?? "-")
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }
}

struct PlayerTitleColumns: View {
    let dashboard: MatchDashboard?

    private let spacing: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Titlar")

            GeometryReader { proxy in
                let columnWidth = max(220, (proxy.size.width - spacing) / 2)

                HStack(alignment: .top, spacing: spacing) {
                    PlayerTitleTable(stats: dashboard?.playerA)
                        .frame(width: columnWidth)
                    PlayerTitleTable(stats: dashboard?.playerB)
                        .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 189)
    }
}

struct PlayerTitleTable: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        VStack(spacing: 0) {
            PlayerInfoRow(label: "Totalt", value: titleValue(totalTitles))
            PlayerInfoRow(label: "Grand Slams", value: titleValue(stats?.grandSlamTitles))
            PlayerInfoRow(label: "Masters", value: titleValue(stats?.mastersTitles))
            PlayerInfoRow(label: "ATP-500", value: titleValue(stats?.atp500Titles))
            PlayerInfoRow(label: "ATP-250", value: titleValue(stats?.atp250Titles))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private var totalTitles: Int? {
        guard let stats else {
            return nil
        }

        return stats.grandSlamTitles + stats.mastersTitles + stats.atp500Titles + stats.atp250Titles
    }

    private func titleValue(_ value: Int?) -> String {
        guard let value else {
            return "-"
        }

        return String(value)
    }
}

struct PlayerProfileColumns: View {
    let dashboard: MatchDashboard?

    private let spacing: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Profil")

            GeometryReader { proxy in
                let columnWidth = max(220, (proxy.size.width - spacing) / 2)

                HStack(alignment: .top, spacing: spacing) {
                    PlayerProfileTable(stats: dashboard?.playerA)
                        .frame(width: columnWidth)
                    PlayerProfileTable(stats: dashboard?.playerB)
                        .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 156)
    }
}

struct PlayerProfileTable: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        VStack(spacing: 0) {
            PlayerInfoRow(label: "Ålder", value: stats?.age.map(String.init) ?? "-")
            PlayerInfoRow(label: "Längd", value: stats?.height.map { "\($0) cm" } ?? "-")
            PlayerInfoRow(label: "Vikt", value: stats?.weight.map { "\($0) kg" } ?? "-")
            PlayerInfoRow(label: "BMI", value: stats?.bmi.map(formatBMI) ?? "-")
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func formatBMI(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "sv_SE")).precision(.fractionLength(1)))
    }
}

struct PlayerIdentityCard: View {
    let name: String
    let country: String?
    let stats: PlayerDashboardStats?
    let onInspect: () -> Void

    var body: some View {
        Button(action: onInspect) {
            VStack(spacing: 12) {
                PlayerHeadshot(url: stats?.imageURL, name: stats?.name ?? name)
                    .frame(width: 132, height: 132)
                    .overlay {
                        Circle()
                            .stroke(AppColors.panelBorder, lineWidth: 1)
                    }

                VStack(spacing: 5) {
                    Text(stats?.name ?? name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    HStack(spacing: 6) {
                        CountryBadge(country: country)
                            .frame(width: 18, height: 18)
                        Text([country, stats?.rank.map { "#\($0)" }].compactMap { $0 }.joined(separator: " "))
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.badgeText)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlayerStatsTable: View {
    let stats: PlayerDashboardStats?
    let market: Double?
    let model: Double?
    let winFactor: Double?
    let h2h: Int

    var body: some View {
        VStack(spacing: 0) {
            PlayerInfoRow(label: "Oddset", value: marketModelValue)
            PlayerInfoRow(label: "I år", value: record(wins: stats?.ytdWins, losses: stats?.ytdLosses))
            PlayerInfoRow(label: "Karriär", value: stats.map { "\($0.totalWins)-\($0.totalLosses)" } ?? "-")
            PlayerFormRow(score: stats?.formScore)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func record(wins: Int?, losses: Int?) -> String {
        guard wins != nil || losses != nil else {
            return "-"
        }

        return "\(wins ?? 0)-\(losses ?? 0)"
    }

    private var marketModelValue: String {
        switch (market, model) {
        case (.some(let market), .some(let model)):
            return "\(formatOdds(market)) (\(formatOdds(model)))"
        case (.some(let market), .none):
            return formatOdds(market)
        case (.none, .some(let model)):
            return "(\(formatOdds(model)))"
        case (.none, .none):
            return "-"
        }
    }
}

struct DashboardLiveScore: View {
    let score: String
    let serve: String?

    private var parsedScore: (sets: String?, point: String) {
        guard
            let openBracket = score.firstIndex(of: "["),
            let closeBracket = score.firstIndex(of: "]"),
            openBracket < closeBracket
        else {
            return (sets: nil, point: score)
        }

        let sets = score[..<openBracket].trimmingCharacters(in: .whitespacesAndNewlines)
        let pointStart = score.index(after: openBracket)
        let point = String(score[pointStart..<closeBracket])

        return (sets: sets.nonEmpty, point: point)
    }

    var body: some View {
        let parsed = parsedScore

        VStack(spacing: 4) {
            HStack(spacing: 8) {
                serveBall(for: "playerA")

                Text(parsed.point)
                    .font(.custom("DINCondensed-Bold", size: 60))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)

                serveBall(for: "playerB")
            }
            .frame(maxWidth: .infinity)

            Text(parsed.sets ?? "")
                .font(.custom("DINCondensed-Bold", size: 30))
                .tracking(1.5)
                .foregroundStyle(AppColors.primaryStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func serveBall(for server: String) -> some View {
        if serve == server {
            Text("🎾")
                .font(.system(size: 20))
                .frame(width: 22, height: 60)
                .offset(y: -3)
        } else {
            Color.clear
                .frame(width: 22, height: 60)
        }
    }
}

struct PlayerInfoColumn: View {
    let name: String
    let country: String?
    let stats: PlayerDashboardStats?
    let market: Double?
    let model: Double?
    let winFactor: Double?
    let h2h: Int
    let onInspect: () -> Void

    var body: some View {
        Button(action: onInspect) {
            VStack(spacing: 12) {
                PlayerHeadshot(url: stats?.imageURL, name: stats?.name ?? name)
                    .frame(width: 112, height: 112)
                    .overlay {
                        Circle()
                            .stroke(AppColors.panelBorder, lineWidth: 1)
                    }

                VStack(spacing: 5) {
                    Text(stats?.name ?? name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        CountryBadge(country: country)
                            .frame(width: 18, height: 18)
                        Text([country, stats?.rank.map { "#\($0)" }].compactMap { $0 }.joined(separator: " "))
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.badgeText)
                }

                VStack(spacing: 0) {
                    PlayerInfoRow(label: "Oddset", value: market.map(formatOdds) ?? "-")
                    PlayerInfoRow(label: "Modell", value: model.map(formatOdds) ?? "-")
                    PlayerInfoRow(label: "Vinst", value: winFactor.map { "\(formatPercent($0 * 100))%" } ?? "-")
                    PlayerInfoRow(label: "I år", value: record(wins: stats?.ytdWins, losses: stats?.ytdLosses))
                    PlayerInfoRow(label: "Karriär", value: stats.map { "\($0.totalWins)-\($0.totalLosses)" } ?? "-")
                    PlayerFormRow(score: stats?.formScore)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(AppColors.tableRowBackground.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func record(wins: Int?, losses: Int?) -> String {
        guard wins != nil || losses != nil else {
            return "-"
        }

        return "\(wins ?? 0)-\(losses ?? 0)"
    }
}

struct PlayerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.caption.opacity(0.64))
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 33)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }
}

struct PlayerFormRow: View {
    let score: Int?

    var body: some View {
        HStack {
            Text("Form")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.caption.opacity(0.64))
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer(minLength: 10)
            FormDots(score: score ?? 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 33)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }
}

struct FormDots: View {
    let score: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= score ? AppColors.primaryStrong : AppColors.panelBorder.opacity(0.42))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct MatchSignalsPanel: View {
    let title: String
    let signals: [MatchSignal]
    let emptyText: String
    let isPositive: Bool

    private var displayedSignals: [MatchSignal] {
        Array(signals.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title)

            VStack(spacing: 0) {
                if displayedSignals.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(AppColors.panelBackground.opacity(0.22))
                } else {
                    ForEach(displayedSignals) { signal in
                        MatchSignalRow(signal: signal, isPositive: isPositive)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
            }
        }
    }
}

struct MatchSignalRow: View {
    let signal: MatchSignal
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(isPositive ? "▲" : "▼")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(isPositive ? AppColors.primaryStrong : AppColors.danger)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(signal.winnerName) - \(signal.loserName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(signal.date) · \(signal.tournament)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.badgeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            Text(signal.score?.nonEmpty ?? "-")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.badgeText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }
}

struct HeadToHeadPanel: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Inbördes möten")

            HStack(alignment: .center, spacing: 12) {
                Text(match.playerA.lastName)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppColors.heading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(dashboard?.headToHeadWinsA ?? 0) - \(dashboard?.headToHeadWinsB ?? 0)")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundStyle(AppColors.primaryStrong)

                Text(match.playerB.lastName)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppColors.heading)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ComparisonBar(
                left: Double(dashboard?.headToHeadWinsA ?? 0),
                right: Double(dashboard?.headToHeadWinsB ?? 0)
            )
        }
        .padding(14)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

struct HeadToHeadMatchesPanel: View {
    let dashboard: MatchDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Tidigare möten (\(dashboard?.headToHeadWinsA ?? 0)-\(dashboard?.headToHeadWinsB ?? 0))")

            VStack(spacing: 0) {
                HeadToHeadMatchesHeader()

                if let matches = dashboard?.headToHeadMatches, !matches.isEmpty {
                    ForEach(matches) { match in
                        HeadToHeadMatchRow(match: match)
                    }
                } else {
                    Text("Inga tidigare möten i databasen.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(AppColors.panelBackground.opacity(0.22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
            }
        }
    }
}

private struct HeadToHeadMatchesHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            header("Datum", width: 88, alignment: .leading)
            header("Turnering", alignment: .leading)
            header("Underlag", width: 84, alignment: .leading)
            header("Vinnare", alignment: .leading)
            header("Förlorare", alignment: .leading)
            header("Resultat", width: 112, alignment: .trailing)
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

    private func header(_ text: String, width: CGFloat? = nil, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.caption.opacity(0.64))
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

private struct HeadToHeadMatchRow: View {
    let match: HeadToHeadMatch

    var body: some View {
        HStack(spacing: 10) {
            cell(match.date, width: 88, alignment: .leading)
            cell(match.tournament, alignment: .leading)
            cell(match.surface ?? "-", width: 84, alignment: .leading)
            cell(playerName(match.winnerName, rank: match.winnerRank), alignment: .leading)
            cell(playerName(match.loserName, rank: match.loserRank), alignment: .leading)
            cell(match.score?.nonEmpty ?? "-", width: 112, alignment: .trailing)
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

    private func playerName(_ name: String, rank: Int?) -> String {
        guard let rank else {
            return name
        }

        return "\(name) (#\(rank))"
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

struct RankingHistoryPanel: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?
    @State private var selectedRange: RankingHistoryRange = .twoYears

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Ranking")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    RankingRangePicker(selectedRange: $selectedRange)
                }

                if hasFilteredRankingData {
                    RankingChart(
                        playerAName: match.playerA.lastName,
                        playerBName: match.playerB.lastName,
                        playerA: filteredHistory(dashboard?.rankingHistoryA ?? []),
                        playerB: filteredHistory(dashboard?.rankingHistoryB ?? [])
                    )
                    .frame(height: 170)
                } else {
                    Text("Ingen rankinghistorik för matchen i ATP-databasen.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                }
            }
            .padding(14)
            .background(AppColors.tableRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }
        }
    }

    private var hasFilteredRankingData: Bool {
        !filteredHistory(dashboard?.rankingHistoryA ?? []).isEmpty || !filteredHistory(dashboard?.rankingHistoryB ?? []).isEmpty
    }

    private func filteredHistory(_ history: [RankingHistoryPoint]) -> [RankingHistoryPoint] {
        guard let cutoff = selectedRange.cutoffMonth else {
            return history
        }

        return history.filter { $0.month >= cutoff }
    }
}

enum RankingHistoryRange: Int, CaseIterable, Identifiable {
    case oneYear = 1
    case twoYears = 2
    case threeYears = 3
    case fourYears = 4
    case fiveYears = 5

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)Y"
    }

    var cutoffMonth: String? {
        guard let date = Calendar.current.date(byAdding: .year, value: -rawValue, to: Date()) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}

struct RankingRangePicker: View {
    @Binding var selectedRange: RankingHistoryRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RankingHistoryRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selectedRange == range ? AppColors.primaryStrong : AppColors.badgeText)
                        .frame(width: 30)
                        .frame(height: 24)
                        .background(selectedRange == range ? AppColors.badgeBackground : Color.clear)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(selectedRange == range ? AppColors.primary.opacity(0.75) : AppColors.fieldBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RankingChart: View {
    let playerAName: String
    let playerBName: String
    let playerA: [RankingHistoryPoint]
    let playerB: [RankingHistoryPoint]

    private let leftInset: CGFloat = 42
    private let bottomInset: CGFloat = 26
    private let topInset: CGFloat = 8
    private let rightInset: CGFloat = 12

    private var months: [String] {
        Array(Set((playerA + playerB).map(\.month))).sorted()
    }

    private var maxRank: Int {
        let observed = (playerA + playerB).map(\.rank).max() ?? 100
        return max(25, min(300, Int(ceil(Double(observed) / 25) * 25)))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    chartGrid(size: proxy.size)
                    rankingPath(points: playerA, months: months, size: proxy.size)
                        .stroke(AppColors.primaryStrong, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    rankingPath(points: playerB, months: months, size: proxy.size)
                        .stroke(AppColors.accentGold, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    pointMarks(points: playerA, months: months, size: proxy.size, color: AppColors.primaryStrong)
                    pointMarks(points: playerB, months: months, size: proxy.size, color: AppColors.accentGold)
                }
            }

            HStack(spacing: 14) {
                LegendItem(name: playerAName, color: AppColors.primaryStrong)
                LegendItem(name: playerBName, color: AppColors.accentGold)
            }
            .frame(maxWidth: .infinity, alignment: .center)
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
                context.draw(Text("\(rank)").font(.system(size: 11, weight: .bold)), at: CGPoint(x: 18, y: y), anchor: .leading)
            }

            let labels = monthLabels()
            for label in labels {
                guard let index = months.firstIndex(of: label) else {
                    continue
                }

                let x = xPosition(index: index, count: months.count, rect: rect)
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

    private func rankingPath(points: [RankingHistoryPoint], months: [String], size: CGSize) -> Path {
        let rect = chartRect(size: size)
        var path = Path()
        let keyed = Dictionary(uniqueKeysWithValues: points.map { ($0.month, $0.rank) })
        let series = months.compactMap { month -> (Int, Int)? in
            guard let index = months.firstIndex(of: month), let rank = keyed[month] else {
                return nil
            }

            return (index, rank)
        }

        for (offset, point) in series.enumerated() {
            let cgPoint = CGPoint(
                x: xPosition(index: point.0, count: months.count, rect: rect),
                y: yPosition(rank: point.1, rect: rect)
            )

            if offset == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }

        return path
    }

    private func pointMarks(points: [RankingHistoryPoint], months: [String], size: CGSize, color: Color) -> some View {
        let rect = chartRect(size: size)
        let keyed = Dictionary(uniqueKeysWithValues: points.map { ($0.month, $0.rank) })

        return ZStack {
            ForEach(months, id: \.self) { month in
                if let index = months.firstIndex(of: month), let rank = keyed[month] {
                    Circle()
                        .fill(AppColors.panelBackground)
                        .overlay {
                            Circle().stroke(color, lineWidth: 2)
                        }
                        .frame(width: 6, height: 6)
                        .position(
                            x: xPosition(index: index, count: months.count, rect: rect),
                            y: yPosition(rank: rank, rect: rect)
                        )
                }
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
        guard months.count > 4 else {
            return months
        }

        let step = max(1, months.count / 4)
        var labels = stride(from: 0, to: months.count, by: step).map { months[$0] }
        if labels.last != months.last {
            labels.append(months.last!)
        }
        return labels
    }
}

struct LegendItem: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

struct PlayerSummaryCard: View {
    let name: String
    let country: String?
    let stats: PlayerDashboardStats?
    let market: Double?
    let model: Double?
    let winFactor: Double?

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            PlayerHeadshot(url: stats?.imageURL, name: stats?.name ?? name)
                .frame(width: 176, height: 176)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(stats?.name ?? name)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 230, alignment: .center)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

struct MatchComparisonPanel: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Jämförelse")

            VStack(spacing: 0) {
                ComparisonRow(label: "Oddset", left: match.playerA.odds.map(formatOdds) ?? "-", right: match.playerB.odds.map(formatOdds) ?? "-")
                ComparisonRow(label: "Modell", left: dashboard?.modelA.map(formatOdds) ?? "-", right: dashboard?.modelB.map(formatOdds) ?? "-")
                ComparisonRow(label: "Vinst", left: dashboard?.winFactorA.map { "\(formatPercent($0 * 100))%" } ?? "-", right: dashboard?.winFactorB.map { "\(formatPercent($0 * 100))%" } ?? "-")
                ComparisonRow(label: "Ranking", left: rank(dashboard?.playerA?.rank), right: rank(dashboard?.playerB?.rank))
                ComparisonRow(label: "ELO", left: value(dashboard?.playerA?.eloRank), right: value(dashboard?.playerB?.eloRank))
                ComparisonRow(label: "Hardcourt ELO", left: value(dashboard?.playerA?.hardElo), right: value(dashboard?.playerB?.hardElo))
                ComparisonRow(label: "Grus ELO", left: value(dashboard?.playerA?.clayElo), right: value(dashboard?.playerB?.clayElo))
                ComparisonRow(label: "Gräs ELO", left: value(dashboard?.playerA?.grassElo), right: value(dashboard?.playerB?.grassElo))
                ComparisonRow(label: "I år", left: record(wins: dashboard?.playerA?.ytdWins, losses: dashboard?.playerA?.ytdLosses), right: record(wins: dashboard?.playerB?.ytdWins, losses: dashboard?.playerB?.ytdLosses))
                ComparisonRow(label: "Karriär DB", left: dbRecord(dashboard?.playerA), right: dbRecord(dashboard?.playerB))
                ComparisonRow(label: "Hardcourt DB", left: record(wins: dashboard?.playerA?.hardWins, losses: dashboard?.playerA?.hardLosses), right: record(wins: dashboard?.playerB?.hardWins, losses: dashboard?.playerB?.hardLosses))
                ComparisonRow(label: "Grus DB", left: record(wins: dashboard?.playerA?.clayWins, losses: dashboard?.playerA?.clayLosses), right: record(wins: dashboard?.playerB?.clayWins, losses: dashboard?.playerB?.clayLosses))
                ComparisonRow(label: "Gräs DB", left: record(wins: dashboard?.playerA?.grassWins, losses: dashboard?.playerA?.grassLosses), right: record(wins: dashboard?.playerB?.grassWins, losses: dashboard?.playerB?.grassLosses))
                ComparisonRow(label: "H2H", left: "\(dashboard?.headToHeadWinsA ?? 0)", right: "\(dashboard?.headToHeadWinsB ?? 0)")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }
        }
        .padding(14)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private func rank(_ rank: Int?) -> String {
        rank.map { "#\($0)" } ?? "-"
    }

    private func value(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private func record(wins: Int?, losses: Int?) -> String {
        guard wins != nil || losses != nil else {
            return "-"
        }

        return "\(wins ?? 0)-\(losses ?? 0)"
    }

    private func dbRecord(_ stats: PlayerDashboardStats?) -> String {
        guard let stats else {
            return "-"
        }

        return "\(stats.totalWins)-\(stats.totalLosses)"
    }

}

struct ComparisonRow: View {
    let label: String
    let left: String
    let right: String

    var body: some View {
        HStack(spacing: 12) {
            Text(left)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(AppColors.heading)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.caption)
                .textCase(.uppercase)
                .frame(width: 120)
                .lineLimit(1)
            Text(right)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(AppColors.heading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(AppColors.panelBackground.opacity(0.38))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder)
                .frame(height: 1)
        }
    }
}

struct PlayerStatsCard: View {
    let label: String
    let fallbackName: String
    let stats: PlayerDashboardStats?
    let surface: TennisSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(label)

            if let stats {
                HStack(alignment: .center, spacing: 12) {
                    PlayerHeadshot(url: stats.imageURL, name: stats.name)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stats.name)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(AppColors.heading)
                            .lineLimit(1)
                        Text([stats.country, stats.rank.map { "#\($0)" }, stats.points.map { "\($0) pts" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.badgeText)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    StatPill(title: "ELO", value: stats.eloRank.map(String.init) ?? "-")
                    StatPill(title: "Hardcourt", value: stats.hardElo.map(String.init) ?? "-")
                    StatPill(title: "Grus", value: stats.clayElo.map(String.init) ?? "-")
                    StatPill(title: "Gräs", value: stats.grassElo.map(String.init) ?? "-")
                }

                VStack(spacing: 7) {
                    StatLine(label: "Karriär DB", value: "\(stats.totalWins)-\(stats.totalLosses)", detail: stats.winPercentage.map { "\(formatPercent($0))%" })
                    ComparisonBar(left: Double(stats.totalWins), right: Double(stats.totalLosses))
                    StatLine(label: "Senaste 365d", value: "\(stats.recentWins)-\(stats.recentLosses)", detail: stats.recentWinPercentage.map { "\(formatPercent($0))%" })
                    ComparisonBar(left: Double(stats.recentWins), right: Double(stats.recentLosses))
                    StatLine(label: surface.title, value: "\(stats.surfaceWins)-\(stats.surfaceLosses)", detail: stats.surfaceWinPercentage.map { "\(formatPercent($0))%" })
                    ComparisonBar(left: Double(stats.surfaceWins), right: Double(stats.surfaceLosses))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fallbackName)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(AppColors.heading)
                    Text("Ingen träff i ATP-databasen.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

struct ComparisonBar: View {
    let left: Double
    let right: Double

    private var total: Double {
        max(1, left + right)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.primaryStrong.opacity(0.85))
                    .frame(width: max(4, proxy.size.width * left / total))
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.badgeText.opacity(0.35))
                    .frame(width: max(4, proxy.size.width * right / total))
            }
        }
        .frame(height: 6)
    }
}

struct CountryBadge: View {
    let country: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(AppColors.previewBackground)

                if let image = flagImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Text(countryCode)
                        .font(.system(size: max(7, proxy.size.width * 0.3), weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.primaryStrong)
                }
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(AppColors.primaryStrong.opacity(0.45), lineWidth: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var countryCode: String {
        country?.prefix(3).uppercased() ?? "--"
    }

    private var flagImage: NSImage? {
        guard countryCode != "--" else {
            return nil
        }

        if let url = Bundle.main.url(forResource: countryCode, withExtension: "svg", subdirectory: "Flags") {
            return NSImage(contentsOf: url)
        }

        return NSImage(contentsOfFile: "Resources/Flags/\(countryCode).svg")
    }
}

struct PlayerHeadshot: View {
    let url: URL?
    let name: String

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let imageSize = size * 0.94

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .overlay {
                        Circle()
                            .fill(AppColors.primaryStrong.opacity(0.12))
                    }

                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize, height: imageSize)
                    default:
                        Text(initials)
                            .font(.system(size: max(18, imageSize * 0.2), weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.heading.opacity(0.32))
                            .frame(width: imageSize, height: imageSize)
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(AppColors.primaryStrong.opacity(0.7), lineWidth: 1)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first).map(String.init)
        return letters.joined().uppercased()
    }
}

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(AppColors.caption)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.primaryStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColors.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StatLine: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColors.badgeText)
            Spacer()
            Text(value)
                .foregroundStyle(AppColors.heading)
            if let detail {
                Text(detail)
                    .foregroundStyle(AppColors.primaryStrong)
            }
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
    }
}

private func formatPercent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

private func formatOdds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}

struct MatchListPanel: View {
    let matches: [TennisMatch]
    let selectedMatchID: String?
    let onSelect: (TennisMatch) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FieldLabel("Matcher")
                Spacer()
                PillLabel("Senaste", isActive: true)
                PillLabel("\(matches.count) rader", isActive: false)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(matches) { match in
                        MatchRow(
                            match: match,
                            isSelected: selectedMatchID == match.id,
                            action: {
                                onSelect(match)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct MatchRow: View {
    let match: TennisMatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PillLabel(match.round ?? match.stateTitle, isActive: true)
                    Text(match.tournament)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(match.dateTitle)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.badgeText)
                }

                HStack(spacing: 8) {
                    PlayerLine(player: match.playerA)
                    Text("slog")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(AppColors.treeMuted)
                    PlayerLine(player: match.playerB)
                }

                HStack(spacing: 8) {
                    Text(match.displayScore)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.primaryStrong)
                    Spacer()
                    Text([match.surface, match.eventType].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.previewText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.previewBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColors.selectionBackground : AppColors.tableRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppColors.primary.opacity(0.75) : AppColors.panelBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct PlayerLine: View {
    let player: MatchPlayer

    var body: some View {
        HStack(spacing: 5) {
            Text(player.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .truncationMode(.tail)

            if let rank = player.rank {
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.badgeText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MatchDetailPanel: View {
    let match: TennisMatch?
    let rankings: [RankedPlayer]
    let selectedSurface: TennisSurface
    let intelligence: MatchIntelligence?
    let isLoadingIntelligence: Bool
    let onSurfaceChange: (TennisSurface) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                MatchCard(
                    match: match,
                    selectedSurface: selectedSurface,
                    intelligence: intelligence,
                    isLoadingIntelligence: isLoadingIntelligence,
                    onSurfaceChange: onSurfaceChange
                )
                RankingPanel(rankings: rankings)
            }

            WatchPanel(matches: rankings)
                .frame(width: 260)
        }
    }
}

struct MatchCard: View {
    let match: TennisMatch?
    let selectedSurface: TennisSurface
    let intelligence: MatchIntelligence?
    let isLoadingIntelligence: Bool
    let onSurfaceChange: (TennisSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                FieldLabel("Vald match")
                Spacer()
                SurfacePicker(selectedSurface: selectedSurface, onSurfaceChange: onSurfaceChange)
            }

            if let match {
                VStack(alignment: .leading, spacing: 8) {
                    Text(match.tournament)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.caption)
                        .textCase(.uppercase)
                    Text(match.matchupTitle)
                        .font(.system(size: 27, weight: .black))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(2)
                    Text(match.displayScore)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.primaryStrong)
                }

                HStack(spacing: 10) {
                    PlayerOddsCard(
                        title: match.playerA.name,
                        model: intelligence?.modelA,
                        winFactor: intelligence?.winFactorA
                    )
                    PlayerOddsCard(
                        title: match.playerB.name,
                        model: intelligence?.modelB,
                        winFactor: intelligence?.winFactorB
                    )
                }

                if isLoadingIntelligence {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Beräknar modellodds...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.badgeText)
                    }
                } else if intelligence == nil {
                    Text("Modellodds saknas för den här matchen.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                }
            } else {
                EmptyState(text: "Inga matcher har laddats ännu.", systemImage: "tennisball")
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct PlayerOddsCard: View {
    let title: String
    let model: Double?
    let winFactor: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)

            OddsMetric(title: "Modell", value: model)

            if let winFactor {
                HStack {
                    Text("Vinst")
                    Spacer()
                    Text(winFactor * 100, format: .number.precision(.fractionLength(1)))
                    Text("%")
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.primaryStrong)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

struct OddsMetric: View {
    let title: String
    let value: Double?

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.badgeText)
            Spacer()
            Text(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "-")
                .foregroundStyle(AppColors.heading)
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
    }
}

struct SurfacePicker: View {
    let selectedSurface: TennisSurface
    let onSurfaceChange: (TennisSurface) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TennisSurface.allCases) { surface in
                Button {
                    onSurfaceChange(surface)
                } label: {
                    Text(surface.title)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .foregroundStyle(selectedSurface == surface ? AppColors.primaryStrong : AppColors.badgeText)
                        .background(selectedSurface == surface ? AppColors.badgeBackground : AppColors.neutralBadgeBackground)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(selectedSurface == surface ? AppColors.primary.opacity(0.65) : AppColors.fieldBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RankingPanel: View {
    let rankings: [RankedPlayer]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FieldLabel("ATP Ranking")
                Spacer()
                PillLabel("Top \(rankings.count)", isActive: false)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rankings) { player in
                        RankingRow(player: player)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct RankingRow: View {
    let player: RankedPlayer

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(player.rank)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.primaryStrong)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
                Text([player.country, player.points.map { "\($0) pts" }, player.eloRank.map { "ELO \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(player.rank.isMultiple(of: 2) ? AppColors.tableAlternateRowBackground : AppColors.tableRowBackground)
    }
}

struct WatchPanel: View {
    let matches: [RankedPlayer]

    private let watchNames = ["Jannik Sinner", "Carlos Alcaraz", "Novak Djokovic", "Daniil Medvedev", "Stefanos Tsitsipas", "Daniel Altmaier"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel("Watchlist")

            ForEach(watchlist) { player in
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)
                    Text("#\(player.rank) · \(player.country ?? "-")")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.badgeText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.tableRowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }
            }

            Spacer()

            Text("Direkt DB-vy: senaste matcher, rankingkontext och SQL-modellodds från PLAYER_WIN_FACTOR.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.badgeText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppColors.panelBackground)
        .panelChrome()
    }

    private var watchlist: [RankedPlayer] {
        matches.filter { watchNames.contains($0.name) }
    }
}

struct EmptyState: View {
    let text: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(AppColors.badgeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBar: View {
    let status: MatchPointStatus
    let matchCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(statusTint)
            Text(status.text)
                .foregroundStyle(statusTint)

            Spacer()

            Text("\(matchCount) matcher")
                .foregroundStyle(AppColors.badgeText)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(AppColors.panelBackground.opacity(0.42))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private var statusTint: Color {
        switch status {
        case .idle, .loading:
            return AppColors.badgeText
        case .ready:
            return AppColors.primaryStrong
        case .failed:
            return AppColors.danger
        }
    }
}

struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(AppColors.caption)
            .textCase(.uppercase)
    }
}

struct PillLabel: View {
    let text: String
    var isActive = true

    init(_ text: String, isActive: Bool = true) {
        self.text = text
        self.isActive = isActive
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .foregroundStyle(isActive ? AppColors.primaryStrong : AppColors.badgeText)
            .background(isActive ? AppColors.badgeBackground : AppColors.neutralBadgeBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? AppColors.primary.opacity(0.65) : AppColors.fieldBorder, lineWidth: 1)
            }
            .contentShape(Capsule())
    }
}

struct IconPillLabel: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))

            Text(text)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .foregroundStyle(AppColors.primaryStrong)
        .background(AppColors.badgeBackground)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AppColors.primary.opacity(0.65), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private extension View {
    func settingsTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(AppColors.heading)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(AppColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.fieldBorder)
            }
    }
}

extension View {
    func panelChrome() -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }
    }
}

enum AppColors {
    private static var theme: AppTheme {
        AppTheme.surface(SettingsStore.loadSurfaceTheme())
    }

    static var pageBackground: Color { theme.pageBackground }
    static var panelBackground: Color { theme.panelBackground }
    static var panelBorder: Color { theme.panelBorder }
    static var inputBackground: Color { theme.inputBackground }
    static var fieldBorder: Color { theme.softBorder }
    static let caption = adaptive(light: nsColor(0.44, 0.46, 0.49), dark: nsColor(0.66, 0.71, 0.69))
    static let heading = adaptive(light: nsColor(0.13, 0.16, 0.24), dark: nsColor(0.93, 0.96, 0.94))
    static let topicName = adaptive(light: nsColor(0.36, 0.38, 0.42), dark: nsColor(0.80, 0.84, 0.82))
    static let treeMuted = adaptive(light: nsColor(0.76, 0.80, 0.86), dark: nsColor(0.40, 0.46, 0.43))
    static let badgeText = adaptive(light: nsColor(0.35, 0.38, 0.46), dark: nsColor(0.72, 0.78, 0.75))
    static var primary: Color { theme.primary }
    static var primaryStrong: Color { theme.primaryStrong }
    static var badgeBackground: Color { theme.softBackground }
    static var neutralBadgeBackground: Color { theme.neutralBackground }
    static var tableRowBackground: Color { theme.tableRowBackground }
    static var tableAlternateRowBackground: Color { theme.tableAlternateRowBackground }
    static var previewBackground: Color { theme.previewBackground }
    static var previewText: Color { theme.previewText }
    static var settingsDialogBackground: Color { theme.panelBackground }
    static var softSettingsHeader: Color { theme.tableAlternateRowBackground }
    static var settingsSegmentBackground: Color { theme.tableRowBackground.opacity(0.92) }
    static var settingsSelectedBackground: Color { theme.previewBackground.opacity(0.82) }
    static var settingsSelectedText: Color { theme.primaryStrong }
    static let accentGold = adaptive(light: nsColor(0.94, 0.70, 0.02), dark: nsColor(1.00, 0.82, 0.22))
    static let danger = adaptive(light: nsColor(0.86, 0.20, 0.18), dark: nsColor(1.00, 0.38, 0.34))
    static var selectionBackground: Color { theme.softBackground }

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func nsColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

struct AppTheme {
    let pageBackground: Color
    let panelBackground: Color
    let panelBorder: Color
    let inputBackground: Color
    let primary: Color
    let primaryStrong: Color
    let softBackground: Color
    let softBorder: Color
    let neutralBackground: Color
    let tableRowBackground: Color
    let tableAlternateRowBackground: Color
    let previewBackground: Color
    let previewText: Color

    static func surface(_ surface: AppSurfaceTheme) -> AppTheme {
        switch surface {
        case .hard:
            return AppTheme(
                pageBackground: AppColors.adaptive(light: AppColors.nsColor(0.42, 0.58, 0.72), dark: AppColors.nsColor(0.02, 0.07, 0.14)),
                panelBackground: AppColors.adaptive(light: AppColors.nsColor(0.98, 1.00, 1.00), dark: AppColors.nsColor(0.07, 0.11, 0.17)),
                panelBorder: AppColors.adaptive(light: AppColors.nsColor(0.83, 0.91, 0.98), dark: AppColors.nsColor(0.13, 0.24, 0.35)),
                inputBackground: AppColors.adaptive(light: AppColors.nsColor(0.99, 1.00, 1.00), dark: AppColors.nsColor(0.05, 0.10, 0.16)),
                primary: AppColors.adaptive(light: AppColors.nsColor(0.08, 0.36, 0.62), dark: AppColors.nsColor(0.35, 0.58, 0.86)),
                primaryStrong: AppColors.adaptive(light: AppColors.nsColor(0.02, 0.19, 0.36), dark: AppColors.nsColor(0.73, 0.86, 1.00)),
                softBackground: AppColors.adaptive(light: AppColors.nsColor(0.79, 0.88, 0.96), dark: AppColors.nsColor(0.05, 0.15, 0.25)),
                softBorder: AppColors.adaptive(light: AppColors.nsColor(0.42, 0.62, 0.82), dark: AppColors.nsColor(0.20, 0.42, 0.64)),
                neutralBackground: AppColors.adaptive(light: AppColors.nsColor(0.88, 0.93, 0.97), dark: AppColors.nsColor(0.10, 0.14, 0.20)),
                tableRowBackground: AppColors.adaptive(light: AppColors.nsColor(0.98, 1.00, 1.00), dark: AppColors.nsColor(0.07, 0.11, 0.17)),
                tableAlternateRowBackground: AppColors.adaptive(light: AppColors.nsColor(0.94, 0.98, 1.00), dark: AppColors.nsColor(0.09, 0.14, 0.21)),
                previewBackground: AppColors.adaptive(light: AppColors.nsColor(0.83, 0.91, 0.98), dark: AppColors.nsColor(0.04, 0.14, 0.24)),
                previewText: AppColors.adaptive(light: AppColors.nsColor(0.04, 0.27, 0.48), dark: AppColors.nsColor(0.54, 0.76, 1.00))
            )
        case .grass:
            return AppTheme(
                pageBackground: AppColors.adaptive(light: AppColors.nsColor(0.28, 0.62, 0.46), dark: AppColors.nsColor(0.08, 0.13, 0.12)),
                panelBackground: AppColors.adaptive(light: AppColors.nsColor(1, 1, 1), dark: AppColors.nsColor(0.11, 0.16, 0.14)),
                panelBorder: AppColors.adaptive(light: AppColors.nsColor(0.82, 0.93, 0.87), dark: AppColors.nsColor(0.15, 0.28, 0.22)),
                inputBackground: AppColors.adaptive(light: AppColors.nsColor(1, 1, 1), dark: AppColors.nsColor(0.09, 0.14, 0.12)),
                primary: AppColors.adaptive(light: AppColors.nsColor(0.18, 0.74, 0.51), dark: AppColors.nsColor(0.25, 0.80, 0.57)),
                primaryStrong: AppColors.adaptive(light: AppColors.nsColor(0.08, 0.52, 0.36), dark: AppColors.nsColor(0.46, 0.88, 0.68)),
                softBackground: AppColors.adaptive(light: AppColors.nsColor(0.78, 0.92, 0.85), dark: AppColors.nsColor(0.08, 0.22, 0.17)),
                softBorder: AppColors.adaptive(light: AppColors.nsColor(0.46, 0.78, 0.65), dark: AppColors.nsColor(0.18, 0.56, 0.40)),
                neutralBackground: AppColors.adaptive(light: AppColors.nsColor(0.89, 0.95, 0.91), dark: AppColors.nsColor(0.14, 0.19, 0.17)),
                tableRowBackground: AppColors.adaptive(light: AppColors.nsColor(0.99, 1.00, 0.99), dark: AppColors.nsColor(0.10, 0.16, 0.14)),
                tableAlternateRowBackground: AppColors.adaptive(light: AppColors.nsColor(0.93, 0.98, 0.95), dark: AppColors.nsColor(0.13, 0.20, 0.17)),
                previewBackground: AppColors.adaptive(light: AppColors.nsColor(0.82, 0.94, 0.88), dark: AppColors.nsColor(0.07, 0.23, 0.17)),
                previewText: AppColors.adaptive(light: AppColors.nsColor(0.02, 0.48, 0.34), dark: AppColors.nsColor(0.36, 0.88, 0.62))
            )
        case .clay:
            return AppTheme(
                pageBackground: AppColors.adaptive(light: AppColors.nsColor(0.58, 0.31, 0.24), dark: AppColors.nsColor(0.16, 0.10, 0.08)),
                panelBackground: AppColors.adaptive(light: AppColors.nsColor(1, 1, 1), dark: AppColors.nsColor(0.17, 0.12, 0.10)),
                panelBorder: AppColors.adaptive(light: AppColors.nsColor(0.96, 0.84, 0.78), dark: AppColors.nsColor(0.28, 0.18, 0.15)),
                inputBackground: AppColors.adaptive(light: AppColors.nsColor(1, 1, 1), dark: AppColors.nsColor(0.15, 0.10, 0.09)),
                primary: AppColors.adaptive(light: AppColors.nsColor(0.85, 0.42, 0.28), dark: AppColors.nsColor(0.89, 0.54, 0.41)),
                primaryStrong: AppColors.adaptive(light: AppColors.nsColor(0.44, 0.20, 0.16), dark: AppColors.nsColor(0.99, 0.80, 0.72)),
                softBackground: AppColors.adaptive(light: AppColors.nsColor(0.96, 0.84, 0.78), dark: AppColors.nsColor(0.23, 0.13, 0.10)),
                softBorder: AppColors.adaptive(light: AppColors.nsColor(0.86, 0.58, 0.47), dark: AppColors.nsColor(0.62, 0.31, 0.24)),
                neutralBackground: AppColors.adaptive(light: AppColors.nsColor(0.96, 0.90, 0.86), dark: AppColors.nsColor(0.22, 0.16, 0.14)),
                tableRowBackground: AppColors.adaptive(light: AppColors.nsColor(1.00, 0.99, 0.98), dark: AppColors.nsColor(0.17, 0.12, 0.10)),
                tableAlternateRowBackground: AppColors.adaptive(light: AppColors.nsColor(0.98, 0.93, 0.90), dark: AppColors.nsColor(0.22, 0.15, 0.12)),
                previewBackground: AppColors.adaptive(light: AppColors.nsColor(0.98, 0.88, 0.83), dark: AppColors.nsColor(0.24, 0.14, 0.11)),
                previewText: AppColors.adaptive(light: AppColors.nsColor(0.58, 0.24, 0.16), dark: AppColors.nsColor(0.94, 0.60, 0.46))
            )
        }
    }
}
