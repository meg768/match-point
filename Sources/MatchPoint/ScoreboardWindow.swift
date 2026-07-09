import SwiftUI

struct ScoreboardWindow: View {
    @StateObject private var store = ScoreboardStore()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        FieldLabel("Livepoäng")
                        Spacer()
                        PillLabel("\(store.liveMatches.count) live", isActive: true)
                    }

                    if store.liveMatches.isEmpty {
                        EmptyState(text: store.isLoading ? "Läser live-matcher..." : "Inga live-matcher just nu.", systemImage: "tennisball")
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.liveMatches) { match in
                                ScoreboardCard(match: match)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)

            ScoreboardStatusLine(status: store.status, matchCount: store.liveMatches.count)
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(AppColors.pageBackground)
        .onAppear {
            store.refresh()
        }
        .onReceive(refreshTimer) { _ in
            store.refresh()
        }
    }
}

private struct ScoreboardStatusLine: View {
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
        .font(.system(size: 12, weight: .semibold))
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

@MainActor
final class ScoreboardStore: ObservableObject {
    @Published var liveMatches: [OddsetMatch] = []
    @Published var isLoading = false
    @Published var status: MatchPointStatus = .idle

    private let databaseSettings = SettingsStore.loadDatabaseSettings()

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
        status = .loading("Läser livepoäng...")

        do {
            let matches = try await OddsetClient().loadMatches()
            let enrichedMatches = (try? await ATPDatabase(settings: databaseSettings).enrichMatches(matches)) ?? matches
            liveMatches = enrichedMatches
                .filter { $0.state == .live }
                .sorted { lhs, rhs in
                    (lhs.start ?? .distantPast) < (rhs.start ?? .distantPast)
                }
            status = .ready("Laddade \(liveMatches.count) live-matcher.")
        } catch {
            liveMatches = []
            status = .failed("Livepoäng är inte tillgängligt.")
        }

        isLoading = false
    }
}

struct ScoreboardCard: View {
    let match: OddsetMatch

    private var parsedScore: ParsedScore {
        ParsedScore(score: match.score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PillLabel("Live", isActive: true)
                Text(match.tournament ?? "Match")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.caption)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer()
                Text(match.startTitleWithOdds)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
            }

            HStack(alignment: .center, spacing: 18) {
                ScoreboardPlayerLine(player: match.playerA, isServing: match.serve == "playerA", side: .leading)
                    .frame(width: 170)

                ScoreboardScoreCell(score: parsedScore, serve: match.serve)
                    .frame(maxWidth: .infinity)

                ScoreboardPlayerLine(player: match.playerB, isServing: match.serve == "playerB", side: .trailing)
                    .frame(width: 170)
            }
            .frame(minHeight: 190)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tableRowBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.panelBorder.opacity(0.85), lineWidth: 1)
        }
    }
}

private struct ScoreboardScoreCell: View {
    let score: ParsedScore
    let serve: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text("Ställning")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(AppColors.primaryStrong.opacity(0.78))
                    .frame(height: 28)
                    .padding(.top, 10)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    serveBall(for: "playerA")

                    Text(score.point)
                        .font(.custom("DINCondensed-Bold", size: 76))
                        .tracking(2)
                        .foregroundStyle(AppColors.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    serveBall(for: "playerB")
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                Text(score.sets ?? "")
                    .font(.custom("DINCondensed-Bold", size: 34))
                    .tracking(2)
                    .foregroundStyle(AppColors.primaryStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(height: 38)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.panelBackground.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.primary.opacity(0.36), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func serveBall(for server: String) -> some View {
        if serve == server {
            Text("🎾")
                .font(.system(size: 25))
                .frame(width: 32, height: 76, alignment: .center)
                .offset(y: -4)
        } else {
            Color.clear
                .frame(width: 32, height: 76)
        }
    }
}

struct ScoreboardPlayerLine: View {
    enum Side {
        case leading
        case trailing
    }

    let player: MatchPlayer
    let isServing: Bool
    let side: Side

    var body: some View {
        HStack(spacing: 7) {
            if side == .leading {
                countryBadge
            }

            VStack(alignment: side == .leading ? .leading : .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    playerName
                }

                Text(playerMeta)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.badgeText)
                    .lineLimit(1)
            }

            if side == .trailing {
                countryBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : .trailing)
    }

    private var countryBadge: some View {
        CountryBadge(country: player.country)
            .frame(width: 22, height: 22)
    }

    private var playerName: some View {
        Text(player.name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppColors.heading)
            .lineLimit(1)
    }

    private var playerMeta: String {
        [player.country, player.rank.map { "#\($0)" }]
            .compactMap { $0 }
            .joined(separator: " ")
            .nonEmpty ?? "--"
    }
}

private struct ParsedScore {
    let sets: String?
    let point: String

    init(score: String?) {
        let scoreValue = score?.nonEmpty ?? "-"

        guard
            let openBracket = scoreValue.firstIndex(of: "["),
            let closeBracket = scoreValue.firstIndex(of: "]"),
            openBracket < closeBracket
        else {
            sets = nil
            point = scoreValue
            return
        }

        let setText = scoreValue[..<openBracket].trimmingCharacters(in: .whitespacesAndNewlines)
        let pointStart = scoreValue.index(after: openBracket)
        sets = setText.nonEmpty
        point = String(scoreValue[pointStart..<closeBracket])
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

        return "(\(formatScoreboardOdds(oddsA))-\(formatScoreboardOdds(oddsB)))"
    }
}

private func formatScoreboardOdds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
