import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var store = MatchRoomStore()
    @State private var searchText = ""
    @State private var settingsOpen = false

    var body: some View {
        VStack(spacing: 8) {
            HeaderPanel(
                apiBaseURL: $store.apiBaseURL,
                settingsOpen: $settingsOpen,
                serviceVersion: store.serviceVersion,
                isLoading: store.isLoading,
                onSave: store.saveBaseURL,
                onRefresh: store.refresh
            )

            HStack(spacing: 8) {
                MatchListPanel(
                    matches: filteredMatches,
                    selectedMatchID: store.selectedMatchID,
                    onSelect: store.select(match:)
                )
                .frame(minWidth: 430, idealWidth: 500, maxWidth: 560)

                MatchDetailPanel(
                    match: store.selectedMatch,
                    rankings: store.rankings,
                    selectedSurface: store.selectedSurface,
                    intelligence: store.intelligence,
                    isLoadingIntelligence: store.isLoadingIntelligence,
                    onSurfaceChange: store.changeSurface
                )
            }

            StatusBar(status: store.status, matchCount: store.matches.count)
        }
        .id("\(appearance.mode.rawValue)-\(appearance.surface.rawValue)")
        .padding(8)
        .frame(minWidth: 1180, minHeight: 720)
        .background(AppColors.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter matches")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)

                Button {
                    settingsOpen.toggle()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .onAppear {
            store.refresh()
        }
        .modifier(FunctionKeyShortcut(keyCode: 97, functionKey: NSF6FunctionKey) {
            appearance.toggle(over: colorScheme)
        })
        .modifier(FunctionKeyShortcut(keyCode: 99, functionKey: NSF3FunctionKey) {
            appearance.cycleSurface()
        })
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
                match.state
            ]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct HeaderPanel: View {
    @Binding var apiBaseURL: String
    @Binding var settingsOpen: Bool
    let serviceVersion: String
    let isLoading: Bool
    let onSave: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        FieldLabel("ATP Tennis")
                        PillLabel("v\(serviceVersion)", isActive: false)
                        if isLoading {
                            PillLabel("Refreshing")
                        }
                    }

                    Text("Match Room")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 9) {
                    AppLogoIcon()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Live odds, model odds, ranking context")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.primaryStrong)
                        Text("tennis.egelberg.se")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.badgeText)
                    }
                }
            }

            if settingsOpen {
                HStack(spacing: 10) {
                    FieldLabel("API")
                    TextField("https://tennis.egelberg.se", text: $apiBaseURL)
                        .settingsTextField()
                    Button {
                        onSave()
                        onRefresh()
                    } label: {
                        IconPillLabel("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(AppColors.panelBackground)
        .panelChrome()
    }
}

struct AppLogoIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.primaryStrong)
            Text("MR")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.panelBackground)
        }
    }
}

struct MatchListPanel: View {
    let matches: [TennisMatch]
    let selectedMatchID: Int?
    let onSelect: (TennisMatch) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FieldLabel("Matches")
                Spacer()
                PillLabel("\(matches.filter(\.isLive).count) live", isActive: true)
                PillLabel("\(matches.count) total", isActive: false)
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
                    PillLabel(match.stateTitle, isActive: match.isLive)
                    Text(match.tournament)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(match.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.badgeText)
                }

                HStack(spacing: 8) {
                    PlayerLine(player: match.playerA, isServing: match.serve == "player")
                    Text("vs")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(AppColors.treeMuted)
                    PlayerLine(player: match.playerB, isServing: match.serve == "opponent")
                }

                HStack(spacing: 8) {
                    Text(match.displayScore)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(match.isLive ? AppColors.primaryStrong : AppColors.badgeText)
                    Spacer()
                    Text("\(match.playerA.oddsText) / \(match.playerB.oddsText)")
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
    let isServing: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isServing {
                Circle()
                    .fill(AppColors.primaryStrong)
                    .frame(width: 7, height: 7)
            }

            Text(player.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)
                .truncationMode(.tail)
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
                FieldLabel("Selected Match")
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
                        .foregroundStyle(match.isLive ? AppColors.primaryStrong : AppColors.badgeText)
                }

                HStack(spacing: 10) {
                    PlayerOddsCard(
                        title: match.playerA.name,
                        bookmaker: match.playerA.odds,
                        model: intelligence?.modelA,
                        abstract: intelligence?.abstractA
                    )
                    PlayerOddsCard(
                        title: match.playerB.name,
                        bookmaker: match.playerB.odds,
                        model: intelligence?.modelB,
                        abstract: intelligence?.abstractB
                    )
                }

                if isLoadingIntelligence {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Computing model odds...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.badgeText)
                    }
                } else if intelligence == nil {
                    Text("Model odds unavailable for this matchup.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.badgeText)
                }
            } else {
                EmptyState(text: "No matches loaded yet.", systemImage: "tennisball")
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
    let bookmaker: Double?
    let model: Double?
    let abstract: Double?

    var valuePercent: Double? {
        guard let bookmaker, let model, bookmaker > 0, model > 0 else {
            return nil
        }

        return ((1 / model) - (1 / bookmaker)) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(AppColors.heading)
                .lineLimit(1)

            OddsMetric(title: "Book", value: bookmaker)
            OddsMetric(title: "Model", value: model)
            OddsMetric(title: "TA", value: abstract)

            if let valuePercent {
                HStack {
                    Text("Value")
                    Spacer()
                    Text(valuePercent, format: .number.precision(.fractionLength(1)))
                    Text("%")
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(valuePercent > 0 ? AppColors.primaryStrong : AppColors.danger)
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
                Text([player.country, player.points.map { "\($0) pts" }].compactMap { $0 }.joined(separator: " · "))
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

            Text("First cut: live board, upcoming odds, model comparison, ranking context.")
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
    let status: MatchRoomStatus
    let matchCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(statusTint)
            Text(status.text)
                .foregroundStyle(statusTint)

            Spacer()

            Text(matchCount == 1 ? "1 match" : "\(matchCount) matches")
                .foregroundStyle(AppColors.badgeText)
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(height: 40)
        .padding(.horizontal, 14)
        .background(AppColors.panelBackground)
        .panelChrome()
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
