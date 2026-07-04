import SwiftUI

struct PlayerInspectorContext: Identifiable {
    enum Side {
        case playerA
        case playerB
    }

    let side: Side
    let match: OddsetMatch
    let stats: PlayerDashboardStats?
    let country: String?
    let market: Double?
    let model: Double?
    let winFactor: Double?
    let h2h: Int
    let rankingHistory: [RankingHistoryPoint]

    var id: String {
        "\(match.id)-\(side)"
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
    @EnvironmentObject private var appearance: AppearanceSettings
    @State private var playerMatches: [TennisMatch] = []
    @State private var isLoadingMatches = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                InspectorFormPanel(summary: PlayerFormSummary(playerName: context.displayName, matches: playerMatches), isLoading: isLoadingMatches)

                InspectorRankingPanel(history: context.rankingHistory, name: context.fallbackPlayer.lastName)

                InspectorSnapshotPanel(groups: snapshotGroups)
            }
            .padding(22)
        }
        .id("\(appearance.mode.rawValue)-\(appearance.surface.rawValue)")
        .frame(minWidth: 720, minHeight: 560)
        .background(AppColors.panelBackground)
        .task(id: context.playerID) {
            await loadMatches()
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 22) {
            PlayerHeadshot(url: context.stats?.imageURL, name: context.displayName)
                .frame(width: 138, height: 138)
                .overlay {
                    Circle()
                        .stroke(AppColors.primaryStrong.opacity(0.45), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("Spelarprofil")

                Text(context.displayName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.heading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 8) {
                    CountryBadge(country: context.displayCountry)
                        .frame(width: 26, height: 26)
                    Text([context.displayCountry, context.rank.map { "#\($0)" }, context.stats?.points.map { "\($0) poäng" }]
                        .compactMap { $0 }
                        .joined(separator: "  "))
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.badgeText)

                InspectorMetricStrip(items: heroMetrics)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppColors.tableRowBackground.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.panelBorder.opacity(0.85), lineWidth: 1)
        }
    }

    private var rankDisplay: String {
        context.rank.map { "#\($0)" } ?? "-"
    }

    private var heroMetrics: [(String, String)] {
        [
            ("Ranking", rankDisplay),
            ("ELO", context.stats?.eloRank.map(String.init) ?? "-"),
            ("Titlar", context.stats?.careerTitles.map(String.init) ?? "-"),
            ("I år", record(wins: context.stats?.ytdWins, losses: context.stats?.ytdLosses))
        ]
    }

    private var snapshotGroups: [InspectorSnapshotGroup] {
        [
            InspectorSnapshotGroup(title: "Profil", rows: profileRows),
            InspectorSnapshotGroup(title: "Ranking", rows: rankingRows),
            InspectorSnapshotGroup(title: "Styrka", rows: ratingRows),
            InspectorSnapshotGroup(title: "Resultat", rows: resultRows)
        ]
    }

    private var profileRows: [(String, String)] {
        [
            ("Ålder", context.stats?.age.map(String.init) ?? "-"),
            ("Längd", context.stats?.height.map { "\($0) cm" } ?? "-"),
            ("Vikt", context.stats?.weight.map { "\($0) kg" } ?? "-"),
            ("BMI", bmiDisplay)
        ]
    }

    private var rankingRows: [(String, String)] {
        [
            ("Nuvarande", rankDisplay),
            ("Poäng", context.stats?.points.map(String.init) ?? "-"),
            ("Högsta ranking", context.stats?.highestRank.map { "#\($0)" } ?? "-"),
            ("Datum", context.stats?.highestRankDate ?? "-")
        ]
    }

    private var ratingRows: [(String, String)] {
        [
            ("ELO", context.stats?.eloRank.map(String.init) ?? "-"),
            ("Hardcourt", context.stats?.hardElo.map(String.init) ?? "-"),
            ("Grus", context.stats?.clayElo.map(String.init) ?? "-"),
            ("Gräs", context.stats?.grassElo.map(String.init) ?? "-")
        ]
    }

    private var resultRows: [(String, String)] {
        [
            ("I år", record(wins: context.stats?.ytdWins, losses: context.stats?.ytdLosses)),
            ("Karriär", context.stats.map { "\($0.totalWins)-\($0.totalLosses)" } ?? "-"),
            ("Senaste 365d", context.stats.map { "\($0.recentWins)-\($0.recentLosses)" } ?? "-"),
            ("Titlar i år", context.stats?.ytdTitles.map(String.init) ?? "-")
        ]
    }

    private var bmiDisplay: String {
        guard let height = context.stats?.height, let weight = context.stats?.weight, height > 0 else {
            return "-"
        }
        let meters = Double(height) / 100
        let bmi = Double(weight) / (meters * meters)
        return bmi.formatted(.number.precision(.fractionLength(1)))
    }

    private func record(wins: Int?, losses: Int?) -> String {
        guard wins != nil || losses != nil else {
            return "-"
        }

        return "\(wins ?? 0)-\(losses ?? 0)"
    }

    @MainActor
    private func loadMatches() async {
        isLoadingMatches = true

        do {
            playerMatches = try await ATPDatabase(settings: SettingsStore.loadDatabaseSettings())
                .loadPlayerMatches(name: context.displayName, limit: 80)
        } catch {
            playerMatches = []
        }

        isLoadingMatches = false
    }
}

private struct InspectorMetricStrip: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.9)
                        .foregroundStyle(AppColors.caption.opacity(0.75))
                    Text(item.1)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.heading)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppColors.tableRowBackground.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
                }
            }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title)
            content
        }
        .padding(14)
        .background(AppColors.tableRowBackground.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct InspectorSnapshotGroup {
    let title: String
    let rows: [(String, String)]
}

private struct InspectorSnapshotPanel: View {
    let groups: [InspectorSnapshotGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Fakta")

            HStack(alignment: .top, spacing: 10) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(AppColors.caption.opacity(0.75))

                        VStack(spacing: 0) {
                            ForEach(group.rows, id: \.0) { row in
                                HStack {
                                    Text(row.0)
                                        .font(.system(size: 10, weight: .medium))
                                        .textCase(.uppercase)
                                        .tracking(0.6)
                                        .foregroundStyle(AppColors.caption.opacity(0.66))
                                    Spacer()
                                    Text(row.1)
                                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                                        .foregroundStyle(AppColors.heading)
                                        .lineLimit(1)
                                }
                                .frame(height: 28)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(AppColors.tableRowBackground.opacity(0.56))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.panelBorder.opacity(0.7), lineWidth: 1)
                    }
                }
            }
        }
        .padding(14)
        .background(AppColors.tableRowBackground.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct InspectorInfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(AppColors.caption.opacity(0.7))
                    Spacer()
                    Text(row.1)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppColors.heading)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(AppColors.tableRowBackground.opacity(0.58))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppColors.panelBorder.opacity(0.62))
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.panelBorder.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct PlayerFormSummary {
    let recentMatches: [TennisMatch]
    let wins: Int
    let losses: Int
    let health: Int
    let healthTitle: String
    let note: String
    let standoutWins: [TennisMatch]
    let warningLosses: [TennisMatch]

    init(playerName: String, matches: [TennisMatch]) {
        let recent = Array(matches.prefix(12))
        recentMatches = recent
        wins = recent.filter { Self.didWin(playerName: playerName, match: $0) }.count
        losses = max(0, recent.count - wins)

        let base = recent.isEmpty ? 2.5 : Double(wins) / Double(recent.count) * 5
        let upsetBonus = Double(recent.filter { Self.isStandoutWin(playerName: playerName, match: $0) }.count) * 0.35
        let badLossPenalty = Double(recent.filter { Self.isWarningLoss(playerName: playerName, match: $0) }.count) * 0.45
        let computedHealth = Int((base + upsetBonus - badLossPenalty).rounded())
        health = min(5, max(1, computedHealth))

        switch health {
        case 5:
            healthTitle = "Stackad"
        case 4:
            healthTitle = "Bra form"
        case 3:
            healthTitle = "Stabil"
        case 2:
            healthTitle = "Skör"
        default:
            healthTitle = "Röd zon"
        }

        if recent.isEmpty {
            note = "Ingen färsk matchhistorik hittades."
        } else if wins >= 8 {
            note = "Vinner mycket just nu. Leta efter vem segrarna kommit mot."
        } else if losses >= 8 {
            note = "Formen blinkar rött. Flera färska förluster."
        } else if recent.contains(where: { Self.isStandoutWin(playerName: playerName, match: $0) }) {
            note = "Har slagit bättre rankat motstånd nyligen."
        } else if recent.contains(where: { Self.isWarningLoss(playerName: playerName, match: $0) }) {
            note = "Har tappat mot lägre rankat motstånd nyligen."
        } else {
            note = "Inga extrema signaler i de senaste matcherna."
        }

        standoutWins = Array(matches.filter { Self.isStandoutWin(playerName: playerName, match: $0) }.prefix(4))
        warningLosses = Array(matches.filter { Self.isWarningLoss(playerName: playerName, match: $0) }.prefix(4))
    }

    private static func didWin(playerName: String, match: TennisMatch) -> Bool {
        match.playerA.name == playerName
    }

    private static func playerRank(playerName: String, match: TennisMatch) -> Int? {
        didWin(playerName: playerName, match: match) ? match.playerA.rank : match.playerB.rank
    }

    private static func opponentRank(playerName: String, match: TennisMatch) -> Int? {
        didWin(playerName: playerName, match: match) ? match.playerB.rank : match.playerA.rank
    }

    private static func isStandoutWin(playerName: String, match: TennisMatch) -> Bool {
        guard didWin(playerName: playerName, match: match), let ownRank = playerRank(playerName: playerName, match: match), let opponentRank = opponentRank(playerName: playerName, match: match) else {
            return false
        }
        return opponentRank < ownRank && ownRank - opponentRank >= 15
    }

    private static func isWarningLoss(playerName: String, match: TennisMatch) -> Bool {
        guard !didWin(playerName: playerName, match: match), let ownRank = playerRank(playerName: playerName, match: match), let opponentRank = opponentRank(playerName: playerName, match: match) else {
            return false
        }
        return opponentRank > ownRank && opponentRank - ownRank >= 20
    }
}

private struct InspectorFormPanel: View {
    let summary: PlayerFormSummary
    let isLoading: Bool

    var body: some View {
        InspectorSection(title: "Form") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Health")
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(1.0)
                            .foregroundStyle(AppColors.caption.opacity(0.75))

                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(index <= summary.health ? healthColor : AppColors.panelBorder.opacity(0.45))
                                    .frame(width: 34, height: 16)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isLoading ? "Läser form..." : summary.healthTitle)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.heading)
                        Text(isLoading ? "Matchhistoriken laddas från ATP-databasen." : "\(summary.wins)-\(summary.losses) senaste \(summary.recentMatches.count) matcher. \(summary.note)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.badgeText)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                HStack(alignment: .top, spacing: 12) {
                    SignalList(title: "Skrällvinster", matches: summary.standoutWins, emptyText: "Inga tydliga skrällar.", positive: true)
                    SignalList(title: "Varningsflaggor", matches: summary.warningLosses, emptyText: "Inga tydliga tapp.", positive: false)
                }
            }
        }
    }

    private var healthColor: Color {
        switch summary.health {
        case 5:
            return AppColors.primaryStrong
        case 4:
            return AppColors.primary
        case 3:
            return AppColors.accentGold
        default:
            return AppColors.danger
        }
    }
}

private struct SignalList: View {
    let title: String
    let matches: [TennisMatch]
    let emptyText: String
    let positive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(AppColors.caption.opacity(0.75))

            if matches.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            } else {
                ForEach(matches) { match in
                    HStack(spacing: 8) {
                        Text(positive ? "▲" : "▼")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(positive ? AppColors.primaryStrong : AppColors.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(signalTitle(match))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.heading)
                                .lineLimit(1)
                            Text("\(match.date) · \(match.tournament)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppColors.badgeText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(match.displayScore)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.badgeText)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(AppColors.tableRowBackground.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func signalTitle(_ match: TennisMatch) -> String {
        if positive {
            return "Slog \(opponentText(match.playerB))"
        }
        return "Förlorade mot \(opponentText(match.playerA))"
    }

    private func opponentText(_ player: MatchPlayer) -> String {
        if let rank = player.rank {
            return "\(player.name) #\(rank)"
        }
        return player.name
    }
}

private struct InspectorRankingPanel: View {
    let history: [RankingHistoryPoint]
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FieldLabel("Rating över tid")
                Spacer()
                Text("\(name) · ranking")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.badgeText)
            }

            if history.isEmpty {
                Text("Ingen rankinghistorik i ATP-databasen.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                InspectorRankingSparkline(points: Array(history.suffix(48)))
                    .frame(height: 180)
            }
        }
        .padding(14)
        .background(AppColors.tableRowBackground.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.panelBorder.opacity(0.85), lineWidth: 1)
        }
    }
}

private struct InspectorRankingSparkline: View {
    let points: [RankingHistoryPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else {
                return
            }

            let ranks = points.map(\.rank)
            let maxRank = max(300, ranks.max() ?? 300)
            let minRank = max(1, min(1, ranks.min() ?? 1))
            let widthStep = size.width / CGFloat(max(1, points.count - 1))

            func y(for rank: Int) -> CGFloat {
                let span = Double(maxRank - minRank)
                guard span > 0 else { return size.height / 2 }
                let progress = Double(rank - minRank) / span
                return CGFloat(progress) * size.height
            }

            for fraction in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = CGFloat(fraction) * size.height
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(AppColors.panelBorder.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            }

            var path = Path()
            for (index, point) in points.enumerated() {
                let cgPoint = CGPoint(x: CGFloat(index) * widthStep, y: y(for: point.rank))
                if index == 0 {
                    path.move(to: cgPoint)
                } else {
                    path.addLine(to: cgPoint)
                }
            }

            context.stroke(path, with: .color(AppColors.primaryStrong), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .padding(.vertical, 8)
    }
}
