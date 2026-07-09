import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var store = MatchPointStore()
    @State private var mode: MatchPointMode = .matches
    @State private var searchText = ""
    @State private var matchPanelWidths = SettingsStore.loadMatchPanelWidths()
    @State private var matchFilter: MatchListFilter = .all
    @State private var isShowingSettings = false
    @State private var inspectedPlayer: PlayerInspectorContext?
    private let liveRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ModePillBar(mode: $mode)

            MatchPointSplitView(
                mode: $mode,
                matches: filteredOddsetMatches,
                selectedFilter: matchFilter,
                selectedMatchID: store.selectedOddsetMatchID,
                selectedMatch: store.selectedOddsetMatch,
                dashboard: store.dashboard,
                players: store.playerSearchResults,
                selectedPlayerID: store.selectedPlayerID,
                selectedPlayer: store.selectedPlayer,
                playerProfile: store.selectedPlayerProfile,
                comparePlayerA: store.comparePlayerA,
                comparePlayerB: store.comparePlayerB,
                comparison: store.playerComparison,
                dataLog: store.dataLog,
                isLoadingPlayers: store.isLoadingPlayers,
                isLoadingPlayerProfile: store.isLoadingPlayerProfile,
                isLoadingComparison: store.isLoadingComparison,
                isLoadingDashboard: store.isLoadingDashboard,
                selectedSurface: store.selectedSurface,
                matchPanelWidth: matchPanelWidthBinding,
                onFilterChange: { matchFilter = $0 },
                onSelect: store.select(oddsetMatch:),
                onSelectPlayerResult: store.select(player:),
                onSetComparePlayer: store.setComparePlayer(_:slot:),
                onClearComparePlayer: store.clearComparePlayer(_:),
                onSwapComparePlayers: store.swapComparePlayers,
                onInspectPlayer: { inspectedPlayer = $0 }
            )
            .padding([.horizontal, .top], 8)
            .padding(.bottom, 8)

            StatusBar(status: store.status, matchCount: store.oddsetMatches.count)
        }
        .id("\(appearance.mode.rawValue)-\(appearance.surface.rawValue)")
        .frame(minWidth: 980, minHeight: 720)
        .background(AppColors.pageBackground)
        .background(WindowTitleHider())
        .searchable(text: $searchText, placement: .toolbar, prompt: mode.searchPrompt)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
            store.searchPlayers(query: "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMatchPointSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectMatchPointMode)) { notification in
            guard let rawValue = notification.object as? String,
                  let selectedMode = MatchPointMode(rawValue: rawValue) else {
                return
            }

            mode = selectedMode
        }
        .onReceive(liveRefreshTimer) { _ in
            store.refresh()
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
        .onChange(of: mode) { _, mode in
            if mode.usesPlayerSearch {
                store.searchPlayers(query: searchText)
            }
        }
        .onChange(of: searchText) { _, query in
            if mode.usesPlayerSearch {
                store.searchPlayers(query: query)
            }
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

    private var matchPanelWidthBinding: Binding<CGFloat?> {
        Binding(
            get: {
                matchPanelWidths[mode]
            },
            set: { width in
                if let width {
                    matchPanelWidths[mode] = width
                    SettingsStore.save(matchPanelWidth: width, for: mode)
                } else {
                    matchPanelWidths.removeValue(forKey: mode)
                }
            }
        )
    }
}

struct ModePillBar: View {
    @Binding var mode: MatchPointMode

    var body: some View {
        HStack(spacing: 10) {
            ModePillButton(item: .matches, mode: $mode)
            ModePillButton(item: .players, mode: $mode)
            ModePillButton(item: .compare, mode: $mode)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(AppColors.pageBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }
}

struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            hideTitle(for: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            hideTitle(for: nsView.window)
        }
    }

    private func hideTitle(for window: NSWindow?) {
        window?.title = ""
        window?.titleVisibility = .hidden
    }
}

struct ModePillButton: View {
    let item: MatchPointMode
    @Binding var mode: MatchPointMode

    var body: some View {
        let isSelected = mode == item

        Button {
            mode = item
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 10, weight: .bold))

                Text(item.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .foregroundStyle(isSelected ? AppColors.primaryStrong : AppColors.badgeText)
            .background(isSelected ? AppColors.badgeBackground : AppColors.panelBackground.opacity(0.34))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? AppColors.primary.opacity(0.72) : AppColors.fieldBorder.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: isSelected ? AppColors.primary.opacity(0.08) : Color.clear, radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}

enum MatchPointMode: String, CaseIterable, Identifiable {
    case matches
    case players
    case compare
    case databaseLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matches:
            return "Matcher"
        case .players:
            return "Spelare"
        case .compare:
            return "Jämför"
        case .databaseLog:
            return "Visa logg"
        }
    }

    var searchPrompt: String {
        switch self {
        case .matches:
            return "Filtrera matcher"
        case .players:
            return "Sök spelare"
        case .compare:
            return "Sök spelare att jämföra"
        case .databaseLog:
            return "Filtrera logg"
        }
    }

    var systemImage: String {
        switch self {
        case .matches:
            return "sportscourt"
        case .players:
            return "person.2"
        case .compare:
            return "arrow.left.arrow.right"
        case .databaseLog:
            return "list.bullet.rectangle"
        }
    }

    var usesPlayerSearch: Bool {
        switch self {
        case .players, .compare:
            return true
        case .matches, .databaseLog:
            return false
        }
    }
}

struct MatchPointSplitView: View {
    @Binding var mode: MatchPointMode
    let matches: [OddsetMatch]
    let selectedFilter: MatchListFilter
    let selectedMatchID: String?
    let selectedMatch: OddsetMatch?
    let dashboard: MatchDashboard?
    let players: [RankedPlayer]
    let selectedPlayerID: String?
    let selectedPlayer: RankedPlayer?
    let playerProfile: PlayerWorkspaceProfile?
    let comparePlayerA: RankedPlayer?
    let comparePlayerB: RankedPlayer?
    let comparison: PlayerComparison?
    let dataLog: [DataLogEntry]
    let isLoadingPlayers: Bool
    let isLoadingPlayerProfile: Bool
    let isLoadingComparison: Bool
    let isLoadingDashboard: Bool
    let selectedSurface: TennisSurface
    @Binding var matchPanelWidth: CGFloat?
    let onFilterChange: (MatchListFilter) -> Void
    let onSelect: (OddsetMatch) -> Void
    let onSelectPlayerResult: (RankedPlayer) -> Void
    let onSetComparePlayer: (RankedPlayer, ComparisonSlot) -> Void
    let onClearComparePlayer: (ComparisonSlot) -> Void
    let onSwapComparePlayers: () -> Void
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    private let dividerWidth: CGFloat = 14
    private let minListWidth: CGFloat = 280
    private let minDashboardWidth: CGFloat = 520
    private let defaultDashboardWidth: CGFloat = 680

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let listWidth = clampedMatchWidth(for: availableWidth)
            let detailWidth = max(minDashboardWidth, availableWidth - listWidth - dividerWidth)

            HStack(alignment: .top, spacing: 0) {
                WorkspaceListPanel(
                    mode: mode,
                    matches: matches,
                    selectedFilter: selectedFilter,
                    selectedMatchID: selectedMatchID,
                    players: players,
                    selectedPlayerID: selectedPlayerID,
                    comparePlayerA: comparePlayerA,
                    comparePlayerB: comparePlayerB,
                    dataLog: dataLog,
                    isLoadingPlayers: isLoadingPlayers,
                    onFilterChange: onFilterChange,
                    onSelectMatch: onSelect,
                    onSelectPlayer: onSelectPlayerResult,
                    onSetComparePlayer: onSetComparePlayer,
                    onClearComparePlayer: onClearComparePlayer,
                    onSwapComparePlayers: onSwapComparePlayers
                )
                .frame(width: listWidth)
                .frame(height: availableHeight, alignment: .top)
                .mainColumnChrome()

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

                Group {
                    if mode == .matches {
                        DashboardPanel(
                            match: selectedMatch,
                            dashboard: dashboard,
                            isLoading: isLoadingDashboard,
                            selectedSurface: selectedSurface,
                            onInspectPlayer: onInspectPlayer
                        )
                    } else if mode == .players {
                        PlayerWorkspacePanel(
                            player: selectedPlayer,
                            profile: playerProfile,
                            isLoading: isLoadingPlayerProfile,
                            surface: selectedSurface
                        )
                    } else if mode == .compare {
                        PlayerComparisonPanel(
                            playerA: comparePlayerA,
                            playerB: comparePlayerB,
                            comparison: comparison,
                            isLoading: isLoadingComparison
                        )
                    } else {
                        DataLogPanel(entries: dataLog)
                    }
                }
                .frame(width: detailWidth)
                .frame(height: availableHeight, alignment: .top)
                .mainColumnChrome()
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .top)
            .coordinateSpace(name: "MatchPointSplitView")
        }
    }

    private func clampedMatchWidth(for availableWidth: CGFloat) -> CGFloat {
        let preferredWidth = matchPanelWidth ?? max(minListWidth, availableWidth - dividerWidth - defaultDashboardWidth)
        return clampedMatchWidth(preferredWidth, availableWidth: availableWidth)
    }

    private func clampedMatchWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let maxMatchWidth = max(minListWidth, availableWidth - dividerWidth - minDashboardWidth)
        return min(max(width, minListWidth), maxMatchWidth)
    }
}

struct SplitDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.panelBorder.opacity(0.72))
            .frame(width: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.pageBackground.opacity(0.001))
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

struct WorkspaceListPanel: View {
    let mode: MatchPointMode
    let matches: [OddsetMatch]
    let selectedFilter: MatchListFilter
    let selectedMatchID: String?
    let players: [RankedPlayer]
    let selectedPlayerID: String?
    let comparePlayerA: RankedPlayer?
    let comparePlayerB: RankedPlayer?
    let dataLog: [DataLogEntry]
    let isLoadingPlayers: Bool
    let onFilterChange: (MatchListFilter) -> Void
    let onSelectMatch: (OddsetMatch) -> Void
    let onSelectPlayer: (RankedPlayer) -> Void
    let onSetComparePlayer: (RankedPlayer, ComparisonSlot) -> Void
    let onClearComparePlayer: (ComparisonSlot) -> Void
    let onSwapComparePlayers: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .matches:
                OddsetPanelContent(
                    matches: matches,
                    selectedFilter: selectedFilter,
                    selectedMatchID: selectedMatchID,
                    onFilterChange: onFilterChange,
                    onSelect: onSelectMatch
                )
            case .players:
                PlayerSearchPanelContent(
                    players: players,
                    selectedPlayerID: selectedPlayerID,
                    isLoading: isLoadingPlayers,
                    onSelect: onSelectPlayer
                )
            case .compare:
                ComparePickerPanelContent(
                    players: players,
                    playerA: comparePlayerA,
                    playerB: comparePlayerB,
                    isLoading: isLoadingPlayers,
                    onSetPlayer: onSetComparePlayer,
                    onClearPlayer: onClearComparePlayer,
                    onSwapPlayers: onSwapComparePlayers
                )
            case .databaseLog:
                DataLogListContent(entries: dataLog)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.panelBackground)
    }
}

struct ComparePickerPanelContent: View {
    let players: [RankedPlayer]
    let playerA: RankedPlayer?
    let playerB: RankedPlayer?
    let isLoading: Bool
    let onSetPlayer: (RankedPlayer, ComparisonSlot) -> Void
    let onClearPlayer: (ComparisonSlot) -> Void
    let onSwapPlayers: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jämför")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.heading)
                        Text(compareTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.badgeText)
                    }

                    Spacer(minLength: 0)

                    Button(action: onSwapPlayers) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSwap ? AppColors.primaryStrong : AppColors.caption.opacity(0.45))
                    .background(AppColors.neutralBadgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .disabled(!canSwap)
                    .help("Byt plats på spelare A och B")
                }

                VStack(spacing: 6) {
                    CompareSlotView(title: "Spelare A", player: playerA) {
                        onClearPlayer(.playerA)
                    }
                    CompareSlotView(title: "Spelare B", player: playerB) {
                        onClearPlayer(.playerB)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if isLoading && players.isEmpty {
                        LoadingRow(text: "Söker spelare...")
                    }

                    ForEach(players) { player in
                        ComparePlayerRow(
                            player: player,
                            isPlayerA: player.player == playerA?.player,
                            isPlayerB: player.player == playerB?.player,
                            onSetPlayerA: {
                                onSetPlayer(player, .playerA)
                            },
                            onSetPlayerB: {
                                onSetPlayer(player, .playerB)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    private var compareTitle: String {
        if let playerA, let playerB {
            return "\(playerA.name) vs \(playerB.name)"
        }

        return "Välj två spelare"
    }

    private var canSwap: Bool {
        playerA != nil || playerB != nil
    }
}

struct DataLogListContent: View {
    let entries: [DataLogEntry]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visa logg")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.heading)
                Text("\(entries.count) händelser")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if entries.isEmpty {
                        LoadingRow(text: "Ingen logg ännu.")
                    }

                    ForEach(entries) { entry in
                        DataLogListRow(entry: entry)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }
}

struct DataLogListRow: View {
    let entry: DataLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.source)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.primaryStrong)
                    .frame(width: 46, alignment: .leading)
                Text(entry.operation)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
                Spacer()
                Text(entry.status.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Text(entry.detail)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(entry.durationMS.map { "\($0) ms" } ?? "-")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.badgeText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .success, .cache:
            return AppColors.primaryStrong
        case .failed:
            return AppColors.danger
        case .started:
            return AppColors.badgeText
        }
    }
}

struct DataLogPanel: View {
    let entries: [DataLogEntry]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel("Databaslogg")

                LazyVGrid(columns: columns, spacing: 0) {
                    ProfileGridCell(label: "Händelser", value: String(entries.count), minHeight: 58)
                    ProfileGridCell(label: "Fel", value: String(entries.filter { $0.status == .failed }.count), minHeight: 58)
                    ProfileGridCell(label: "Cache", value: String(entries.filter { $0.status == .cache }.count), minHeight: 58)
                    ProfileGridCell(label: "Senaste", value: entries.first.map { timeText($0.timestamp) } ?? "-", minHeight: 58)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel("Senaste operationer")

                    VStack(spacing: 0) {
                        DataLogHeader()
                        if entries.isEmpty {
                            Text("Loggen fylls när appen läser Oddset, ATP-data, spelare eller jämförelser.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(AppColors.panelBackground.opacity(0.22))
                        } else {
                            ForEach(entries.prefix(40)) { entry in
                                DataLogTableRow(entry: entry)
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.panelBackground)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 0),
            GridItem(.flexible(), spacing: 0),
            GridItem(.flexible(), spacing: 0),
            GridItem(.flexible(), spacing: 0)
        ]
    }

    private func timeText(_ date: Date) -> String {
        DataLogFormat.time.string(from: date)
    }
}

struct DataLogHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            header("Tid", width: 76)
            header("Källa", width: 64)
            header("Operation")
            header("Status", width: 64, alignment: .trailing)
            header("Tid", width: 66, alignment: .trailing)
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

    private func header(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.caption.opacity(0.64))
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

struct DataLogTableRow: View {
    let entry: DataLogEntry

    var body: some View {
        HStack(spacing: 10) {
            cell(DataLogFormat.time.string(from: entry.timestamp), width: 76)
            cell(entry.source, width: 64)
            cell("\(entry.operation) · \(entry.detail)")
            cell(entry.status.title, width: 64, alignment: .trailing)
            cell(entry.durationMS.map { "\($0) ms" } ?? "-", width: 66, alignment: .trailing)
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

    private func cell(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.heading)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

enum DataLogFormat {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct CompareSlotView: View {
    let title: String
    let player: RankedPlayer?
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.caption.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.8)
                .frame(width: 70, alignment: .leading)

            Text(player?.name ?? "-")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)

            Spacer()

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(player == nil ? AppColors.caption.opacity(0.42) : AppColors.badgeText)
            .background(AppColors.neutralBadgeBackground.opacity(player == nil ? 0.45 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(player == nil)
            .help("Rensa \(title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }
}

struct ComparePlayerRow: View {
    let player: RankedPlayer
    let isPlayerA: Bool
    let isPlayerB: Bool
    let onSetPlayerA: () -> Void
    let onSetPlayerB: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CountryBadge(country: player.country)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
                Text(detailText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("A", action: onSetPlayerA)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isPlayerA ? AppColors.primaryStrong : AppColors.badgeText)
                .frame(width: 26, height: 26)
                .background(isPlayerA ? AppColors.selectionBackground : AppColors.neutralBadgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Button("B", action: onSetPlayerB)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isPlayerB ? AppColors.primaryStrong : AppColors.badgeText)
                .frame(width: 26, height: 26)
                .background(isPlayerB ? AppColors.selectionBackground : AppColors.neutralBadgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPlayerA || isPlayerB ? AppColors.selectionBackground.opacity(0.72) : AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPlayerA || isPlayerB ? AppColors.primary.opacity(0.55) : AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var detailText: String {
        [rankText, player.country, player.eloRank.map { "ELO \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var rankText: String? {
        player.rank < 9999 ? "#\(player.rank)" : nil
    }
}

struct WorkspaceNavigator: View {
    @Binding var mode: MatchPointMode
    @State private var isDatabaseExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match Point")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.caption.opacity(0.64))
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 12)
                .padding(.top, 16)

            VStack(spacing: 4) {
                navigatorButton(.matches)
                navigatorButton(.players)
                navigatorButton(.compare)

                navigatorGroup(
                    title: "Databas",
                    systemImage: "externaldrive.connected.to.line.below",
                    isExpanded: isDatabaseExpanded
                ) {
                    isDatabaseExpanded.toggle()
                }
                if isDatabaseExpanded {
                    navigatorButton(.databaseLog, level: 1)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.panelBackground)
    }

    private func navigatorGroup(title: String, systemImage: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 14)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.badgeText)
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func navigatorButton(_ item: MatchPointMode, level: Int = 0) -> some View {
        Button {
            mode = item
        } label: {
            HStack(spacing: 8) {
                if level == 0 {
                    Color.clear
                        .frame(width: 14)
                } else {
                    Color.clear
                        .frame(width: 32)
                }
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(mode == item ? AppColors.primaryStrong : AppColors.badgeText)
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(mode == item ? AppColors.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct OddsetPanelContent: View {
    let matches: [OddsetMatch]
    let selectedFilter: MatchListFilter
    let selectedMatchID: String?
    let onFilterChange: (MatchListFilter) -> Void
    let onSelect: (OddsetMatch) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matcher")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.heading)
                    Text("\(matches.count) matcher")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                }

                HStack(spacing: 8) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

struct PlayerSearchPanelContent: View {
    let players: [RankedPlayer]
    let selectedPlayerID: String?
    let isLoading: Bool
    let onSelect: (RankedPlayer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spelare")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.heading)
                Text("\(players.count) träffar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if isLoading && players.isEmpty {
                        LoadingRow(text: "Söker spelare...")
                    }

                    ForEach(players) { player in
                        PlayerSearchRow(
                            player: player,
                            isSelected: selectedPlayerID == player.player,
                            action: {
                                onSelect(player)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }
}

struct PlayerSearchRow: View {
    let player: RankedPlayer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CountryBadge(country: player.country)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)

                    Text(detailText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(rankText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primaryStrong)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
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

    private var rankText: String {
        player.rank < 9999 ? "#\(player.rank)" : "-"
    }

    private var detailText: String {
        [player.country, player.points.map { "\($0) p" }, player.eloRank.map { "ELO \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PillLabel(match.state.title, isActive: match.state == .live)
                Text(match.tournament ?? "Match")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.caption)
                    .lineLimit(1)
                Spacer()
                Text(match.startTitleWithOdds)
                    .font(.system(size: 11, weight: .semibold))
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
        .onTapGesture(perform: action)
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
                    .font(.system(size: 12, weight: .semibold))
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
            AppPill(title, isActive: isSelected, height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardPanel: View {
    let match: OddsetMatch?
    let dashboard: MatchDashboard?
    let isLoading: Bool
    let selectedSurface: TennisSurface
    let onInspectPlayer: (PlayerInspectorContext) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel("Matchöversikt")

                if let match {
                    MatchOverviewPanel(match: match, dashboard: dashboard, isLoading: isLoading, selectedSurface: selectedSurface, onInspectPlayer: onInspectPlayer)
                    RankingHistoryPanel(match: match, dashboard: dashboard, isLoading: isLoading)
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
    }
}

struct PlayerWorkspacePanel: View {
    let player: RankedPlayer?
    let profile: PlayerWorkspaceProfile?
    let isLoading: Bool
    let surface: TennisSurface
    @State private var selectedRange: RankingHistoryRange = .twoYears

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel("Spelaröversikt")

                if let player {
                    PlayerWorkspaceHeader(player: player, stats: profile?.stats)
                    PlayerWorkspaceProfileGrid(stats: profile?.stats, surface: surface)
                    PlayerWorkspaceTitles(stats: profile?.stats)
                    PlayerWorkspaceRanking(
                        name: profile?.stats?.name ?? player.name,
                        history: filteredHistory(profile?.rankingHistory ?? []),
                        selectedRange: $selectedRange,
                        isLoading: isLoading
                    )
                    PlayerWorkspaceMatches(
                        tabs: profile?.matchTabs ?? [],
                        isLoading: isLoading
                    )
                } else {
                    EmptyState(text: "Sök eller välj en spelare.", systemImage: "person.crop.circle")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.panelBackground)
    }

    private func filteredHistory(_ history: [RankingHistoryPoint]) -> [RankingHistoryPoint] {
        guard let cutoff = selectedRange.cutoffMonth else {
            return history
        }

        return history.filter { $0.month >= cutoff }
    }
}

struct PlayerComparisonPanel: View {
    let playerA: RankedPlayer?
    let playerB: RankedPlayer?
    let comparison: PlayerComparison?
    let isLoading: Bool
    @State private var selectedRange: RankingHistoryRange = .twoYears

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel("Jämförelse")

                if let playerA, let playerB {
                    ComparisonHero(playerA: playerA, playerB: playerB, comparison: comparison)
                    ComparisonProfileGrid(comparison: comparison, fallbackA: playerA, fallbackB: playerB)
                    ComparisonRankingPanel(
                        playerAName: comparison?.playerA?.name ?? playerA.name,
                        playerBName: comparison?.playerB?.name ?? playerB.name,
                        rankingHistoryA: filteredHistory(comparison?.rankingHistoryA ?? []),
                        rankingHistoryB: filteredHistory(comparison?.rankingHistoryB ?? []),
                        selectedRange: $selectedRange,
                        isLoading: isLoading
                    )
                    ComparisonHeadToHeadMatches(comparison: comparison, isLoading: isLoading)
                } else {
                    EmptyState(text: "Välj två spelare att jämföra.", systemImage: "arrow.left.arrow.right")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.panelBackground)
    }

    private func filteredHistory(_ history: [RankingHistoryPoint]) -> [RankingHistoryPoint] {
        guard let cutoff = selectedRange.cutoffMonth else {
            return history
        }

        return history.filter { $0.month >= cutoff }
    }
}

struct ComparisonHero: View {
    let playerA: RankedPlayer
    let playerB: RankedPlayer
    let comparison: PlayerComparison?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                heroPlayer(name: comparison?.playerA?.name ?? playerA.name, country: comparison?.playerA?.country ?? playerA.country, alignment: .leading)
                Text("\(comparison?.headToHeadWinsA ?? 0) - \(comparison?.headToHeadWinsB ?? 0)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColors.primaryStrong)
                    .frame(width: 110)
                heroPlayer(name: comparison?.playerB?.name ?? playerB.name, country: comparison?.playerB?.country ?? playerB.country, alignment: .trailing)
            }

            ComparisonBar(
                left: Double(comparison?.headToHeadWinsA ?? 0),
                right: Double(comparison?.headToHeadWinsB ?? 0)
            )
        }
        .padding(14)
        .background(AppColors.tableRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private func heroPlayer(name: String, country: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                if alignment == .trailing {
                    Spacer(minLength: 0)
                }
                CountryBadge(country: country)
                    .frame(width: 18, height: 18)
                Text(country ?? "-")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                if alignment == .leading {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

struct ComparisonProfileGrid: View {
    let comparison: PlayerComparison?
    let fallbackA: RankedPlayer
    let fallbackB: RankedPlayer

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Översikt")

            LazyVGrid(columns: columns, spacing: 0) {
                ProfileGridCell(label: "Ranking A", value: rank(comparison?.playerA?.rank ?? fallbackA.rank), minHeight: 58)
                ProfileGridCell(label: "Ranking B", value: rank(comparison?.playerB?.rank ?? fallbackB.rank), minHeight: 58)
                ProfileGridCell(label: "ELO A", value: elo(comparison?.playerA?.eloRank ?? fallbackA.eloRank), minHeight: 58)
                ProfileGridCell(label: "ELO B", value: elo(comparison?.playerB?.eloRank ?? fallbackB.eloRank), minHeight: 58)
                ProfileGridCell(label: "Titlar A", value: titles(comparison?.playerA), minHeight: 58)
                ProfileGridCell(label: "Titlar B", value: titles(comparison?.playerB), minHeight: 58)
                ProfileGridCell(label: "Bästa A", value: bestRank(comparison?.playerA), minHeight: 58)
                ProfileGridCell(label: "Bästa B", value: bestRank(comparison?.playerB), minHeight: 58)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
            }
        }
    }

    private func rank(_ value: Int?) -> String {
        guard let value, value < 9999 else {
            return "-"
        }

        return "#\(value)"
    }

    private func elo(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private func titles(_ stats: PlayerDashboardStats?) -> String {
        guard let stats else {
            return "-"
        }

        return String(stats.grandSlamTitles + stats.mastersTitles + stats.atp500Titles + stats.atp250Titles)
    }

    private func bestRank(_ stats: PlayerDashboardStats?) -> String {
        guard let value = stats?.highestRank else {
            return "-"
        }

        return "#\(value)"
    }
}

struct ComparisonRankingPanel: View {
    let playerAName: String
    let playerBName: String
    let rankingHistoryA: [RankingHistoryPoint]
    let rankingHistoryB: [RankingHistoryPoint]
    @Binding var selectedRange: RankingHistoryRange
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Ranking")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    RankingRangePicker(selectedRange: $selectedRange)
                }

                if !rankingHistoryA.isEmpty || !rankingHistoryB.isEmpty {
                    RankingChart(
                        playerAName: playerAName,
                        playerBName: playerBName,
                        playerA: rankingHistoryA,
                        playerB: rankingHistoryB
                    )
                    .frame(height: 170)
                } else if isLoading {
                    LoadingBlock(text: "Läser rankinghistorik...")
                } else {
                    Text("Ingen rankinghistorik i ATP-databasen.")
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
}

struct ComparisonHeadToHeadMatches: View {
    let comparison: PlayerComparison?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Tidigare möten (\(comparison?.headToHeadWinsA ?? 0)-\(comparison?.headToHeadWinsB ?? 0))")

            VStack(spacing: 0) {
                HeadToHeadMatchesHeader()

                if let matches = comparison?.headToHeadMatches, !matches.isEmpty {
                    ForEach(matches) { match in
                        HeadToHeadMatchRow(match: match)
                    }
                } else if isLoading {
                    LoadingRow(text: "Läser tidigare möten...")
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

struct PlayerWorkspaceHeader: View {
    let player: RankedPlayer
    let stats: PlayerDashboardStats?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerHeadshot(url: stats?.imageURL, name: stats?.name ?? player.name)
                .frame(width: 74, height: 74)
                .overlay {
                    Circle()
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    CountryBadge(country: stats?.country ?? player.country)
                        .frame(width: 22, height: 22)
                    Text(stats?.name ?? player.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background(AppColors.tableRowBackground.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private var summary: String {
        [
            rankText,
            pointsText,
            eloText,
            stats?.country ?? player.country
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var rankText: String? {
        let rank = stats?.rank ?? player.rank
        return rank < 9999 ? "#\(rank)" : nil
    }

    private var pointsText: String? {
        (stats?.points ?? player.points).map { "\($0) poäng" }
    }

    private var eloText: String? {
        (stats?.eloRank ?? player.eloRank).map { "ELO \($0)" }
    }
}

struct PlayerWorkspaceProfileGrid: View {
    let stats: PlayerDashboardStats?
    let surface: TennisSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Profil")
            PlayerProfileGridCard(stats: stats, surface: surface)
        }
    }
}

struct PlayerWorkspaceTitles: View {
    let stats: PlayerDashboardStats?

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Titlar")

            LazyVGrid(columns: columns, spacing: 0) {
                ProfileGridCell(label: "Totalt", value: totalTitles, valueFontSize: 15, minHeight: 58)
                ProfileGridCell(label: "Grand Slam", value: stats.map { String($0.grandSlamTitles) } ?? "-", valueFontSize: 15, minHeight: 58)
                ProfileGridCell(label: "Masters", value: stats.map { String($0.mastersTitles) } ?? "-", valueFontSize: 15, minHeight: 58)
                ProfileGridCell(label: "ATP-500", value: stats.map { String($0.atp500Titles) } ?? "-", valueFontSize: 15, minHeight: 58)
                ProfileGridCell(label: "ATP-250", value: stats.map { String($0.atp250Titles) } ?? "-", valueFontSize: 15, minHeight: 58)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
            }
        }
    }

    private var totalTitles: String {
        guard let stats else {
            return "-"
        }

        return String(stats.grandSlamTitles + stats.mastersTitles + stats.atp500Titles + stats.atp250Titles)
    }
}

struct PlayerWorkspaceRanking: View {
    let name: String
    let history: [RankingHistoryPoint]
    @Binding var selectedRange: RankingHistoryRange
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Ranking")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    RankingRangePicker(selectedRange: $selectedRange)
                }

                if !history.isEmpty {
                    RankingChart(
                        playerAName: name,
                        playerBName: "",
                        playerA: history,
                        playerB: []
                    )
                    .frame(height: 170)
                } else if isLoading {
                    LoadingBlock(text: "Läser rankinghistorik...")
                } else {
                    Text("Ingen rankinghistorik i ATP-databasen.")
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
}

struct PlayerWorkspaceMatches: View {
    let tabs: [PlayerMatchTab]
    let isLoading: Bool
    @State private var selectedTabID: String?

    private var selectedTab: PlayerMatchTab? {
        if let selectedTabID, let tab = tabs.first(where: { $0.id == selectedTabID }) {
            return tab
        }

        return tabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Matcher")

            VStack(alignment: .leading, spacing: 0) {
                if !tabs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tabs) { tab in
                                Button {
                                    selectedTabID = tab.id
                                } label: {
                                    AppPill(tab.title, isActive: (selectedTab?.id ?? tabs.first?.id) == tab.id, fontSize: 11, height: 26)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                    }

                    ForEach(Array((selectedTab?.matches ?? []).prefix(8))) { match in
                        PlayerWorkspaceMatchRow(match: match)
                    }
                } else if isLoading {
                    LoadingRow(text: "Läser matcher...")
                } else {
                    Text("Ingen matchhistorik i ATP-databasen.")
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

struct PlayerWorkspaceMatchRow: View {
    let match: TennisMatch

    var body: some View {
        HStack(spacing: 10) {
            Text(match.dateTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.badgeText)
                .frame(width: 88, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(match.tournament)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.caption)
                    .lineLimit(1)
                Text("\(match.playerA.name) slog \(match.playerB.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(match.displayScore)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.primaryStrong)
                .lineLimit(1)
                .frame(width: 116, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
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
    let isLoading: Bool
    let selectedSurface: TennisSurface
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.badgeText)
            }

            EqualPlayerColumns(match: match, dashboard: dashboard, selectedSurface: selectedSurface, onInspectPlayer: onInspectPlayer)
            MatchOddsColumns(match: match, dashboard: dashboard)
            PlayerTitleColumns(dashboard: dashboard)
            PlayerProfileGridPreview(dashboard: dashboard)
            HeadToHeadMatchesPanel(dashboard: dashboard, isLoading: isLoading)
        }
        .padding(.bottom, 2)
    }
}

struct EqualPlayerColumns: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?
    let selectedSurface: TennisSurface
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
                        winFactor: dashboard?.winFactorA,
                        h2h: dashboard?.headToHeadWinsA ?? 0
                    )
                    .frame(width: columnWidth)

                    PlayerStatsTable(
                        stats: dashboard?.playerB,
                        winFactor: dashboard?.winFactorB,
                        h2h: dashboard?.headToHeadWinsB ?? 0
                    )
                    .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 360)
    }

    private var shouldShowScore: Bool {
        match.state == .live && match.score?.nonEmpty != nil
    }

    private func inspectPlayerA() {
        onInspectPlayer(
            PlayerInspectorContext(
                side: .playerA,
                match: match,
                surface: dashboard?.surface ?? selectedSurface,
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
                surface: dashboard?.surface ?? selectedSurface,
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

struct PlayerTitleColumns: View {
    let dashboard: MatchDashboard?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Titlar")

            PlayerTitleTable(
                playerA: dashboard?.playerA,
                playerB: dashboard?.playerB
            )
        }
    }
}

struct MatchOddsColumns: View {
    let match: OddsetMatch
    let dashboard: MatchDashboard?
    private let bankroll = 1_000

    private var codexOdds: CodexOdds? {
        CodexOdds(playerA: dashboard?.playerA, playerB: dashboard?.playerB, surface: dashboard?.surface ?? match.inferredSurface)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Odds")

            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    MatchOddsHeaderRow()
                    MatchOddsRow(
                        name: dashboard?.playerA?.name ?? match.playerA.name,
                        oddset: match.playerA.odds,
                        oddsetOpponent: match.playerB.odds,
                        ta: dashboard?.modelA,
                        taOpponent: dashboard?.modelB,
                        mp: dashboard?.mpA,
                        mpOpponent: dashboard?.mpB,
                        codex: codexOdds?.oddsA,
                        codexOpponent: codexOdds?.oddsB
                    )
                    MatchOddsRow(
                        name: dashboard?.playerB?.name ?? match.playerB.name,
                        oddset: match.playerB.odds,
                        oddsetOpponent: match.playerA.odds,
                        ta: dashboard?.modelB,
                        taOpponent: dashboard?.modelA,
                        mp: dashboard?.mpB,
                        mpOpponent: dashboard?.mpA,
                        codex: codexOdds?.oddsB,
                        codexOpponent: codexOdds?.oddsA
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                }

                KellyRecommendationGrid(recommendation: kellyRecommendation, bankroll: bankroll)
            }
        }
    }

    private var kellyRecommendation: KellyRecommendation? {
        KellyRecommendation.best(
            bankroll: bankroll,
            candidates: [
                KellyCandidate(
                    playerName: dashboard?.playerA?.name ?? match.playerA.name,
                    source: "TA",
                    marketOdds: match.playerA.odds,
                    marketOpponentOdds: match.playerB.odds,
                    modelOdds: dashboard?.modelA,
                    modelOpponentOdds: dashboard?.modelB
                ),
                KellyCandidate(
                    playerName: dashboard?.playerB?.name ?? match.playerB.name,
                    source: "TA",
                    marketOdds: match.playerB.odds,
                    marketOpponentOdds: match.playerA.odds,
                    modelOdds: dashboard?.modelB,
                    modelOpponentOdds: dashboard?.modelA
                ),
                KellyCandidate(
                    playerName: dashboard?.playerA?.name ?? match.playerA.name,
                    source: "MP",
                    marketOdds: match.playerA.odds,
                    marketOpponentOdds: match.playerB.odds,
                    modelOdds: dashboard?.mpA,
                    modelOpponentOdds: dashboard?.mpB
                ),
                KellyCandidate(
                    playerName: dashboard?.playerB?.name ?? match.playerB.name,
                    source: "MP",
                    marketOdds: match.playerB.odds,
                    marketOpponentOdds: match.playerA.odds,
                    modelOdds: dashboard?.mpB,
                    modelOpponentOdds: dashboard?.mpA
                ),
                KellyCandidate(
                    playerName: dashboard?.playerA?.name ?? match.playerA.name,
                    source: "Codex",
                    marketOdds: match.playerA.odds,
                    marketOpponentOdds: match.playerB.odds,
                    modelOdds: codexOdds?.oddsA,
                    modelOpponentOdds: codexOdds?.oddsB
                ),
                KellyCandidate(
                    playerName: dashboard?.playerB?.name ?? match.playerB.name,
                    source: "Codex",
                    marketOdds: match.playerB.odds,
                    marketOpponentOdds: match.playerA.odds,
                    modelOdds: codexOdds?.oddsB,
                    modelOpponentOdds: codexOdds?.oddsA
                )
            ]
        )
    }
}

struct MatchOddsHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            oddsHeader("Namn")
                .frame(maxWidth: .infinity, alignment: .leading)
            oddsHeader("Oddset", width: 96, alignment: .trailing)
            oddsHeader("TA", width: 122, alignment: .trailing)
            oddsHeader("MP", width: 122, alignment: .trailing)
            oddsHeader("Codex", width: 122, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppColors.panelBackground.opacity(0.28))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private func oddsHeader(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.caption.opacity(0.64))
            .textCase(.uppercase)
            .tracking(0.8)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

struct MatchOddsRow: View {
    let name: String
    let oddset: Double?
    let oddsetOpponent: Double?
    let ta: Double?
    let taOpponent: Double?
    let mp: Double?
    let mpOpponent: Double?
    let codex: Double?
    let codexOpponent: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            oddsCell(oddset, width: 96)
            oddsCell(ta, edge: edge(model: ta, modelOpponent: taOpponent), width: 122)
            oddsCell(mp, edge: edge(model: mp, modelOpponent: mpOpponent), width: 122)
            oddsCell(codex, edge: edge(model: codex, modelOpponent: codexOpponent), width: 122)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private func oddsCell(_ value: Double?, edge: Int? = nil, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(value.map(formatOdds) ?? "-")
                .foregroundStyle(AppColors.heading)
            if let edge {
                Text("(+\(edge)%)")
                    .foregroundStyle(AppColors.primaryStrong)
            }
        }
        .font(.system(size: 14, weight: .regular))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(width: width, alignment: .trailing)
    }

    private func edge(model: Double?, modelOpponent: Double?) -> Int? {
        guard
            let marketProbability = noVigProbability(odds: oddset, opponentOdds: oddsetOpponent),
            let modelProbability = noVigProbability(odds: model, opponentOdds: modelOpponent)
        else {
            return nil
        }

        let edge = Int(((modelProbability - marketProbability) * 100).rounded())
        return edge > 0 ? edge : nil
    }

    private func noVigProbability(odds: Double?, opponentOdds: Double?) -> Double? {
        guard let odds, let opponentOdds, odds > 1, opponentOdds > 1 else {
            return nil
        }

        let probability = 1 / odds
        let opponentProbability = 1 / opponentOdds
        let total = probability + opponentProbability
        guard total > 0 else {
            return nil
        }

        return probability / total
    }
}

private struct CodexOdds {
    let oddsA: Double
    let oddsB: Double
    let probabilityA: Double

    init?(playerA: PlayerDashboardStats?, playerB: PlayerDashboardStats?, surface: TennisSurface) {
        guard let playerA, let playerB else {
            return nil
        }

        let score = Self.score(player: playerA, opponent: playerB, surface: surface)
            - Self.score(player: playerB, opponent: playerA, surface: surface)
        let probabilityA = min(0.92, max(0.08, 1 / (1 + exp(-score))))
        let probabilityB = 1 - probabilityA

        self.probabilityA = probabilityA
        oddsA = Self.pricedOdds(probabilityA)
        oddsB = Self.pricedOdds(probabilityB)
    }

    private static func score(player: PlayerDashboardStats, opponent: PlayerDashboardStats, surface: TennisSurface) -> Double {
        var score = 0.0

        if let playerElo = elo(for: player, surface: surface), let opponentElo = elo(for: opponent, surface: surface) {
            score += Double(playerElo - opponentElo) / 520 * 0.62
        }

        if let playerRank = player.rank, let opponentRank = opponent.rank, playerRank > 0, opponentRank > 0 {
            score += log(Double(opponentRank) / Double(playerRank)) * 0.28
        }

        if let playerSurface = ratio(wins: player.surfaceWins, matches: player.surfaceMatches),
           let opponentSurface = ratio(wins: opponent.surfaceWins, matches: opponent.surfaceMatches) {
            score += (playerSurface - opponentSurface) * 0.38
        }

        if let playerRecent = ratio(wins: player.recentWins, matches: player.recentMatches),
           let opponentRecent = ratio(wins: opponent.recentWins, matches: opponent.recentMatches) {
            score += (playerRecent - opponentRecent) * 0.22
        }

        if let playerForm = ratio(wins: player.formWins, matches: player.formMatches),
           let opponentForm = ratio(wins: opponent.formWins, matches: opponent.formMatches) {
            score += (playerForm - opponentForm) * 0.18
        }

        return score
    }

    private static func elo(for player: PlayerDashboardStats, surface: TennisSurface) -> Int? {
        switch surface {
        case .grass:
            return player.grassElo ?? player.eloRank
        case .clay:
            return player.clayElo ?? player.eloRank
        case .hard:
            return player.hardElo ?? player.eloRank
        }
    }

    private static func ratio(wins: Int, matches: Int) -> Double? {
        guard matches > 0 else {
            return nil
        }

        return Double(wins) / Double(matches)
    }

    private static func pricedOdds(_ probability: Double, margin: Double = 1.05) -> Double {
        roundDisplayOdds(1 / (probability * margin))
    }
}

private struct KellyRecommendationGrid: View {
    let recommendation: KellyRecommendation?
    let bankroll: Int

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ProfileGridCell(label: "Kelly-tips", value: recommendation?.playerName ?? "Avstå", valueFontSize: 14, minHeight: 54)
                ProfileGridCell(label: "Källa", value: recommendation?.source ?? "-", valueFontSize: 14, minHeight: 54)
                ProfileGridCell(label: "Bankrulle", value: AppFormat.kronor(bankroll), valueFontSize: 14, minHeight: 54)
                ProfileGridCell(label: "Full Kelly", value: recommendation.map { formatKellyPercent($0.fullKellyFraction) } ?? "-", valueFontSize: 14, minHeight: 54)
            }

            LazyVGrid(columns: columns, spacing: 0) {
                KellyStakeCell(label: "1/4 Kelly", amount: recommendation?.stake(fraction: 0.25))
                KellyStakeCell(label: "1/8 Kelly", amount: recommendation?.stake(fraction: 0.125))
                KellyStakeCell(label: "1/16 Kelly", amount: recommendation?.stake(fraction: 0.0625))
                KellyStakeCell(label: "1/32 Kelly", amount: recommendation?.stake(fraction: 0.03125))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct KellyStakeCell: View {
    let label: String
    let amount: Int?

    var body: some View {
        ProfileGridCell(
            label: label,
            value: amount.map(AppFormat.kronor) ?? "-",
            valueFontSize: 15,
            minHeight: 58
        )
    }
}

private struct KellyCandidate {
    let playerName: String
    let source: String
    let marketOdds: Double?
    let marketOpponentOdds: Double?
    let modelOdds: Double?
    let modelOpponentOdds: Double?
}

private struct KellyRecommendation {
    let playerName: String
    let source: String
    let bankroll: Int
    let fullKellyFraction: Double

    func stake(fraction: Double) -> Int {
        Int((Double(bankroll) * fullKellyFraction * fraction).rounded())
    }

    static func best(bankroll: Int, candidates: [KellyCandidate]) -> KellyRecommendation? {
        candidates.compactMap { candidate -> KellyRecommendation? in
            guard
                let marketOdds = candidate.marketOdds,
                marketOdds > 1,
                let modelProbability = normalizedProbability(odds: candidate.modelOdds, opponentOdds: candidate.modelOpponentOdds)
            else {
                return nil
            }

            let netOdds = marketOdds - 1
            let lossProbability = 1 - modelProbability
            let fullKellyFraction = ((netOdds * modelProbability) - lossProbability) / netOdds

            guard fullKellyFraction > 0 else {
                return nil
            }

            return KellyRecommendation(
                playerName: candidate.playerName,
                source: candidate.source,
                bankroll: bankroll,
                fullKellyFraction: min(fullKellyFraction, 1)
            )
        }
        .max { $0.fullKellyFraction < $1.fullKellyFraction }
    }

    private static func normalizedProbability(odds: Double?, opponentOdds: Double?) -> Double? {
        guard let odds, let opponentOdds, odds > 1, opponentOdds > 1 else {
            return nil
        }

        let probability = 1 / odds
        let opponentProbability = 1 / opponentOdds
        let total = probability + opponentProbability
        guard total > 0 else {
            return nil
        }

        return probability / total
    }
}

struct PlayerTitleTable: View {
    let playerA: PlayerDashboardStats?
    let playerB: PlayerDashboardStats?

    var body: some View {
        VStack(spacing: 0) {
            PlayerTitleHeaderRow()
            PlayerTitleRow(stats: playerA)
            PlayerTitleRow(stats: playerB)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
    }
}

struct PlayerTitleHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            titleHeader("Namn")
                .frame(maxWidth: .infinity, alignment: .leading)
            titleHeader("Titlar", width: 64, alignment: .trailing)
            titleHeader("Grand Slam", width: 86, alignment: .trailing)
            titleHeader("Masters", width: 72, alignment: .trailing)
            titleHeader("ATP-500", width: 72, alignment: .trailing)
            titleHeader("ATP-250", width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppColors.panelBackground.opacity(0.28))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private func titleHeader(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.caption.opacity(0.64))
            .textCase(.uppercase)
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: alignment)
    }
}

struct PlayerTitleRow: View {
    let stats: PlayerDashboardStats?

    var body: some View {
        HStack(spacing: 10) {
            Text(stats?.name ?? "-")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueCell(totalTitles, width: 64)
            valueCell(stats?.grandSlamTitles, width: 86)
            valueCell(stats?.mastersTitles, width: 72)
            valueCell(stats?.atp500Titles, width: 72)
            valueCell(stats?.atp250Titles, width: 72)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
    }

    private var totalTitles: Int? {
        guard let stats else {
            return nil
        }

        return stats.grandSlamTitles + stats.mastersTitles + stats.atp500Titles + stats.atp250Titles
    }

    private func valueCell(_ value: Int?, width: CGFloat) -> some View {
        Text(value.map(String.init) ?? "-")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(AppColors.heading)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

struct PlayerProfileGridPreview: View {
    let dashboard: MatchDashboard?

    private let spacing: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Profil")

            GeometryReader { proxy in
                let columnWidth = max(220, (proxy.size.width - spacing) / 2)

                HStack(alignment: .top, spacing: spacing) {
                    PlayerProfileGridCard(stats: dashboard?.playerA, surface: dashboard?.surface)
                        .frame(width: columnWidth)
                    PlayerProfileGridCard(stats: dashboard?.playerB, surface: dashboard?.surface)
                        .frame(width: columnWidth)
                }
            }
        }
        .frame(height: 232)
    }
}

struct PlayerProfileGridCard: View {
    let stats: PlayerDashboardStats?
    let surface: TennisSurface?

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text(stats?.name ?? "-")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(AppColors.panelBackground.opacity(0.28))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppColors.panelBorder.opacity(0.72))
                        .frame(height: 1)
                }

            LazyVGrid(columns: columns, spacing: 0) {
                ProfileGridCell(label: "Ålder", value: stats?.age.map(String.init) ?? "-")
                ProfileGridCell(label: "Längd/vikt/BMI", value: physicalValue)
                ProfileGridCell(label: "Ranking", value: stats?.rank.map { "#\($0)" } ?? "-")
                ProfileGridCell(label: "ELO", value: eloValue)
                ProfileGridCell(label: "Bästa ranking", value: highestRankValue)
                ProfileGridCell(label: "Proffs sedan", value: stats?.pro.map(String.init) ?? "-")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
        }
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
            return "#\(highestRank) (\(date))"
        }

        return "#\(highestRank)"
    }

    private var eloValue: String {
        guard let stats else {
            return "-"
        }

        let surfaceElo: Int?
        switch surface {
        case .grass:
            surfaceElo = stats.grassElo
        case .clay:
            surfaceElo = stats.clayElo
        case .hard:
            surfaceElo = stats.hardElo
        case .none:
            surfaceElo = nil
        }

        switch (surfaceElo, stats.eloRank) {
        case (.some(let surfaceElo), .some(let totalElo)):
            return "\(surfaceElo)/\(totalElo)"
        case (.some(let surfaceElo), .none):
            return "\(surfaceElo)/-"
        case (.none, .some(let totalElo)):
            return "-/\(totalElo)"
        case (.none, .none):
            return "-"
        }
    }
}

struct ProfileGridCell: View {
    let label: String
    let value: String
    var valueFontSize: CGFloat = 15
    var minHeight: CGFloat = 58
    var width: CGFloat?
    var horizontalPadding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.caption.opacity(0.64))
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.system(size: valueFontSize, weight: .regular))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(AppColors.panelBackground.opacity(0.22))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.58))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.panelBorder.opacity(0.72))
                .frame(height: 1)
        }
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
                    .font(.system(size: 12, weight: .semibold))
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
    let winFactor: Double?
    let h2h: Int

    var body: some View {
        VStack(spacing: 0) {
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                }

                VStack(spacing: 0) {
                    PlayerInfoRow(label: "Oddset", value: market.map(formatOdds) ?? "-")
                    PlayerInfoRow(label: "TA", value: model.map(formatOdds) ?? "-")
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
                .font(.system(size: 15, weight: .regular))
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
                    .font(.system(size: 24, weight: .black))
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
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Tidigare möten (\(dashboard?.headToHeadWinsA ?? 0)-\(dashboard?.headToHeadWinsB ?? 0))")

            VStack(spacing: 0) {
                HeadToHeadMatchesHeader()

                if let matches = dashboard?.headToHeadMatches, !matches.isEmpty {
                    ForEach(matches) { match in
                        HeadToHeadMatchRow(match: match)
                    }
                } else if isLoading {
                    LoadingRow(text: "Läser tidigare möten...")
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
    let isLoading: Bool
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
                } else if isLoading {
                    LoadingBlock(text: "Läser rankinghistorik...")
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
                    AppPill(
                        range.title,
                        isActive: selectedRange == range,
                        inactiveBackground: .clear,
                        fontSize: 11,
                        horizontalPadding: 0,
                        width: 30,
                        height: 24
                    )
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
                    if !playerB.isEmpty {
                        rankingPath(points: playerB, months: months, size: proxy.size)
                            .stroke(AppColors.accentGold, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    pointMarks(points: playerA, months: months, size: proxy.size, color: AppColors.primaryStrong)
                    if !playerB.isEmpty {
                        pointMarks(points: playerB, months: months, size: proxy.size, color: AppColors.accentGold)
                    }
                }
            }

            HStack(spacing: 14) {
                LegendItem(name: playerAName, color: AppColors.primaryStrong)
                if !playerB.isEmpty {
                    LegendItem(name: playerBName, color: AppColors.accentGold)
                }
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
                ComparisonRow(label: "TA", left: dashboard?.modelA.map(formatOdds) ?? "-", right: dashboard?.modelB.map(formatOdds) ?? "-")
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
                .font(.system(size: 16, weight: .regular))
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
                .font(.system(size: 16, weight: .regular))
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
                        .font(.system(size: max(7, proxy.size.width * 0.3), weight: .bold))
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
                            .font(.system(size: max(18, imageSize * 0.2), weight: .black))
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
                .font(.system(size: 13, weight: .black))
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
        .font(.system(size: 13, weight: .bold))
    }
}

private func formatPercent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}

private func formatKellyPercent(_ value: Double) -> String {
    "\(formatPercent(value * 100))%"
}

private func formatOdds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}

private func roundDisplayOdds(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

enum AppFormat {
    static func kronor(_ value: Int?) -> String {
        guard let value else {
            return "-"
        }

        return "\(groupedInteger(value)) kr"
    }

    static func dollars(_ value: Int?) -> String {
        guard let value else {
            return "-"
        }

        return "$\(groupedInteger(value))"
    }

    private static func groupedInteger(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let digits = String(abs(value))
        let groups = stride(from: digits.count, to: 0, by: -3).map { end -> Substring in
            let start = max(0, end - 3)
            let startIndex = digits.index(digits.startIndex, offsetBy: start)
            let endIndex = digits.index(digits.startIndex, offsetBy: end)
            return digits[startIndex..<endIndex]
        }

        return sign + groups.reversed().joined(separator: ",")
    }
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
                        .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.primaryStrong)
                    Spacer()
                    Text([match.surface, match.eventType].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .bold))
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
                    .font(.system(size: 11, weight: .bold))
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
                        .font(.system(size: 18, weight: .bold))
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
                        Text("Hämtar TA-odds...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.badgeText)
                    }
                } else if intelligence == nil {
                    Text("TA-odds saknas för den här matchen.")
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

            OddsMetric(title: "TA", value: model)

            if let winFactor {
                HStack {
                    Text("Vinst")
                    Spacer()
                    Text(winFactor * 100, format: .number.precision(.fractionLength(1)))
                    Text("%")
                }
                .font(.system(size: 13, weight: .bold))
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
        .font(.system(size: 13, weight: .bold))
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
                    AppPill(surface.title, isActive: selectedSurface == surface, fontSize: 12, horizontalPadding: 10)
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
                .font(.system(size: 13, weight: .black))
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
                        .font(.system(size: 12, weight: .bold))
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

            Text("Direkt DB-vy: senaste matcher, rankingkontext och TA-odds.")
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

struct LoadingRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppColors.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(AppColors.panelBackground.opacity(0.22))
    }
}

struct LoadingBlock: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AppColors.badgeText)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
        AppPill(text, isActive: isActive)
    }
}

struct AppPill: View {
    let text: String
    var isActive = true
    var activeBackground = AppColors.badgeBackground
    var inactiveBackground = AppColors.neutralBadgeBackground
    var fontSize: CGFloat = 11
    var horizontalPadding: CGFloat = 12
    var width: CGFloat?
    var height: CGFloat = 24
    var activeStrokeOpacity: Double = 0.65

    init(
        _ text: String,
        isActive: Bool = true,
        activeBackground: Color = AppColors.badgeBackground,
        inactiveBackground: Color = AppColors.neutralBadgeBackground,
        fontSize: CGFloat = 11,
        horizontalPadding: CGFloat = 12,
        width: CGFloat? = nil,
        height: CGFloat = 24,
        activeStrokeOpacity: Double = 0.65
    ) {
        self.text = text
        self.isActive = isActive
        self.activeBackground = activeBackground
        self.inactiveBackground = inactiveBackground
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.width = width
        self.height = height
        self.activeStrokeOpacity = activeStrokeOpacity
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(width: width)
            .frame(height: height)
            .foregroundStyle(isActive ? AppColors.primaryStrong : AppColors.badgeText)
            .background(isActive ? activeBackground : inactiveBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? AppColors.primary.opacity(activeStrokeOpacity) : AppColors.fieldBorder, lineWidth: 1)
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

            Text(text.uppercased())
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
    func mainColumnChrome() -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

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
