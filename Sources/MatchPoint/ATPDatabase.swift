import Foundation

enum ATPDatabaseError: LocalizedError {
    case missingWinFactor

    var errorDescription: String? {
        switch self {
        case .missingWinFactor:
            return "Modellen kunde inte beräkna vinstfaktor för den här matchen."
        }
    }
}

struct ATPDatabase {
    let settings: APISettings

    func loadSnapshot() async throws -> (matches: [TennisMatch], rankings: [RankedPlayer]) {
        try await withConnection { connection in
            async let matches = loadRecentMatches(on: connection)
            async let rankings = loadRankings(on: connection)
            return try await (matches, rankings)
        }
    }

    func loadIntelligence(match: TennisMatch, surface: TennisSurface) async throws -> MatchIntelligence {
        let playerA = match.playerA.id ?? match.playerA.name
        let playerB = match.playerB.id ?? match.playerB.name

        let resolved = try await withConnection { connection in
            let rows = try await connection.query(
                """
                SELECT
                    pa.id AS player_a,
                    pa.name AS name_a,
                    pb.id AS player_b,
                    pb.name AS name_b
                FROM players pa
                JOIN players pb
                WHERE pa.id = PLAYER_LOOKUP(?)
                  AND pb.id = PLAYER_LOOKUP(?)
                  AND pa.id <> pb.id
                LIMIT 1
                """,
                [
                    MySQLData(string: playerA),
                    MySQLData(string: playerB)
                ]
            ).get()

            guard let row = rows.first else {
                throw TennisAbstractOddsError.playerNotFound("\(playerA) / \(playerB)")
            }

            return (
                playerA: row.string("name_a") ?? match.playerA.name,
                playerB: row.string("name_b") ?? match.playerB.name
            )
        }

        let odds = try await loadTennisAbstractOdds(playerA: resolved.playerA, playerB: resolved.playerB, surface: surface)

        return MatchIntelligence(
            matchID: match.id,
            surface: surface,
            playerA: resolved.playerA,
            playerB: resolved.playerB,
            modelA: odds.oddsA,
            modelB: odds.oddsB,
            winFactorA: odds.probabilityA
        )
    }

    func loadDashboard(match: OddsetMatch, surface: TennisSurface) async throws -> MatchDashboard {
        let dashboard = try await withConnection { connection in
            let playerA = try await loadPlayerStats(name: match.playerA.name, surface: surface, on: connection)
            let playerB = try await loadPlayerStats(name: match.playerB.name, surface: surface, on: connection)
            let rankingHistoryA = try await loadRankingHistory(name: match.playerA.name, on: connection)
            let rankingHistoryB = try await loadRankingHistory(name: match.playerB.name, on: connection)
            let headToHead = try await loadHeadToHead(playerA: match.playerA.name, playerB: match.playerB.name, on: connection)
            let headToHeadMatches = try await loadHeadToHeadMatches(playerA: match.playerA.name, playerB: match.playerB.name, on: connection)

            return MatchDashboard(
                matchID: match.id,
                surface: surface,
                playerA: playerA,
                playerB: playerB,
                rankingHistoryA: rankingHistoryA,
                rankingHistoryB: rankingHistoryB,
                headToHeadWinsA: headToHead.playerAWins,
                headToHeadWinsB: headToHead.playerBWins,
                headToHeadMatches: headToHeadMatches,
                modelA: nil,
                modelB: nil,
                winFactorA: nil,
                gptA: nil,
                gptB: nil
            )
        }

        let odds = try? await loadTennisAbstractOdds(
            playerA: dashboard.playerA?.name ?? match.playerA.name,
            playerB: dashboard.playerB?.name ?? match.playerB.name,
            surface: surface
        )
        return dashboard.withModelOdds(odds)
    }

    func loadDashboardOverview(match: OddsetMatch, surface: TennisSurface) async throws -> MatchDashboard {
        let dashboard = try await withConnection { connection in
            let playerA = try await loadPlayerStats(name: match.playerA.name, surface: surface, on: connection)
            let playerB = try await loadPlayerStats(name: match.playerB.name, surface: surface, on: connection)

            return MatchDashboard(
                matchID: match.id,
                surface: surface,
                playerA: playerA,
                playerB: playerB,
                rankingHistoryA: [],
                rankingHistoryB: [],
                headToHeadWinsA: 0,
                headToHeadWinsB: 0,
                headToHeadMatches: [],
                modelA: nil,
                modelB: nil,
                winFactorA: nil,
                gptA: nil,
                gptB: nil
            )
        }

        let odds = try? await loadTennisAbstractOdds(
            playerA: dashboard.playerA?.name ?? match.playerA.name,
            playerB: dashboard.playerB?.name ?? match.playerB.name,
            surface: surface
        )
        return dashboard.withModelOdds(odds)
    }

    func enrichMatches(_ matches: [OddsetMatch]) async throws -> [OddsetMatch] {
        try await withConnection { connection in
            var playersByName: [String: MatchPlayer] = [:]
            let names = Set(matches.flatMap { [$0.playerA.name, $0.playerB.name] })

            for name in names {
                if let player = try await loadMatchPlayer(name: name, fallbackOdds: nil, on: connection) {
                    playersByName[name] = player
                }
            }

            return matches.map { match in
                let playerA = merge(match.playerA, with: playersByName[match.playerA.name])
                let playerB = merge(match.playerB, with: playersByName[match.playerB.name])

                return OddsetMatch(
                    id: match.id,
                    start: match.start,
                    tournament: match.tournament,
                    state: match.state,
                    score: match.score,
                    serve: match.serve,
                    playerA: playerA,
                    playerB: playerB,
                    source: match.source
                )
            }
        }
    }

    func loadPlayerMatches(name: String, limit: Int = 120) async throws -> [TennisMatch] {
        try await withConnection { connection in
            try await loadPlayerMatches(name: name, limit: limit, on: connection)
        }
    }

    func loadPlayerProfile(name: String, surface: TennisSurface) async throws -> (stats: PlayerDashboardStats?, rankingHistory: [RankingHistoryPoint], matchTabs: [PlayerMatchTab]) {
        try await withConnection { connection in
            let stats = try await loadPlayerStats(name: name, surface: surface, on: connection)
            let resolvedName = stats?.name ?? name
            let rankingHistory = try await loadRankingHistory(name: resolvedName, on: connection)
            let matchTabs = try await loadPlayerMatchTabs(name: resolvedName, playerID: stats?.id, on: connection)

            return (stats, rankingHistory, matchTabs)
        }
    }

    func searchPlayers(query: String, limit: Int = 80) async throws -> [RankedPlayer] {
        try await withConnection { connection in
            let pattern = "%\(query.trimmingCharacters(in: .whitespacesAndNewlines))%"
            let rows = try await connection.query(
                """
                SELECT
                    id AS player,
                    name,
                    country,
                    rank,
                    points,
                    elo_rank,
                    elo_rank_hard,
                    elo_rank_clay,
                    elo_rank_grass
                FROM players
                WHERE (? = '' OR name LIKE ? OR id LIKE ?)
                  AND (rank IS NOT NULL OR elo_rank IS NOT NULL)
                ORDER BY
                    CASE WHEN rank IS NULL THEN 1 ELSE 0 END ASC,
                    rank ASC,
                    elo_rank DESC,
                    name ASC
                LIMIT ?
                """,
                [
                    MySQLData(string: query.trimmingCharacters(in: .whitespacesAndNewlines)),
                    MySQLData(string: pattern),
                    MySQLData(string: pattern),
                    MySQLData(int: limit)
                ]
            ).get()

            return rows.compactMap(makeRankedPlayer)
        }
    }

    func loadPlayerComparison(playerA: String, playerB: String, surface: TennisSurface) async throws -> PlayerComparison {
        try await withConnection { connection in
            let statsA = try await loadPlayerStats(name: playerA, surface: surface, on: connection)
            let statsB = try await loadPlayerStats(name: playerB, surface: surface, on: connection)
            let nameA = statsA?.name ?? playerA
            let nameB = statsB?.name ?? playerB
            let rankingHistoryA = try await loadRankingHistory(name: nameA, on: connection)
            let rankingHistoryB = try await loadRankingHistory(name: nameB, on: connection)
            let headToHead = try await loadHeadToHead(playerA: nameA, playerB: nameB, on: connection)
            let headToHeadMatches = try await loadHeadToHeadMatches(playerA: nameA, playerB: nameB, on: connection)
            let taOdds = try? await loadTennisAbstractOdds(playerA: nameA, playerB: nameB, surface: nil)

            return PlayerComparison(
                playerA: statsA,
                playerB: statsB,
                rankingHistoryA: rankingHistoryA,
                rankingHistoryB: rankingHistoryB,
                headToHeadWinsA: headToHead.playerAWins,
                headToHeadWinsB: headToHead.playerBWins,
                headToHeadMatches: headToHeadMatches,
                taA: taOdds?.oddsA,
                taB: taOdds?.oddsB,
                gptA: nil,
                gptB: nil
            )
        }
    }

    private func loadRankings(on connection: MySQLConnection) async throws -> [RankedPlayer] {
        let rows = try await connection.query(
            """
            SELECT
                id AS player,
                name,
                country,
                rank,
                points,
                elo_rank,
                elo_rank_hard,
                elo_rank_clay,
                elo_rank_grass
            FROM players
            WHERE rank IS NOT NULL
            ORDER BY rank ASC
            LIMIT 30
            """
        ).get()

        return rows.compactMap(makeRankedPlayer)
    }

    private func makeRankedPlayer(row: MySQLRow) -> RankedPlayer? {
        guard let player = row.string("player"), let name = row.string("name") else {
            return nil
        }

        return RankedPlayer(
            player: player,
            name: name,
            country: row.string("country"),
            rank: row.int("rank") ?? 9999,
            points: row.int("points"),
            eloRank: row.int("elo_rank"),
            hardElo: row.int("elo_rank_hard"),
            clayElo: row.int("elo_rank_clay"),
            grassElo: row.int("elo_rank_grass")
        )
    }

    private func loadRecentMatches(on connection: MySQLConnection) async throws -> [TennisMatch] {
        let rows = try await connection.query(
            """
            SELECT
                m.id,
                DATE_FORMAT(e.date, '%Y-%m-%d') AS event_date,
                e.name AS event_name,
                e.type AS event_type,
                e.surface AS event_surface,
                m.round,
                m.score,
                m.status,
                m.duration,
                winner.id AS winner_id,
                winner.name AS winner_name,
                winner.country AS winner_country,
                m.winner_rank,
                loser.id AS loser_id,
                loser.name AS loser_name,
                loser.country AS loser_country,
                m.loser_rank
            FROM matches m
            JOIN events e ON e.id = m.event
            LEFT JOIN players winner ON winner.id = m.winner
            LEFT JOIN players loser ON loser.id = m.loser
            WHERE e.date IS NOT NULL
              AND m.winner IS NOT NULL
              AND m.loser IS NOT NULL
            ORDER BY e.date DESC, e.id DESC, m.id DESC
            LIMIT 80
            """
        ).get()

        return rows.compactMap(makeTennisMatch)
    }

    private func loadPlayerMatches(name: String, limit: Int, on connection: MySQLConnection) async throws -> [TennisMatch] {
        let rows = try await connection.query(
            """
            SELECT
                m.id,
                DATE_FORMAT(e.date, '%Y-%m-%d') AS event_date,
                e.name AS event_name,
                e.type AS event_type,
                e.surface AS event_surface,
                m.round,
                m.score,
                m.status,
                m.duration,
                winner.id AS winner_id,
                winner.name AS winner_name,
                winner.country AS winner_country,
                m.winner_rank,
                loser.id AS loser_id,
                loser.name AS loser_name,
                loser.country AS loser_country,
                m.loser_rank
            FROM matches m
            JOIN events e ON e.id = m.event
            LEFT JOIN players winner ON winner.id = m.winner
            LEFT JOIN players loser ON loser.id = m.loser
            WHERE e.date IS NOT NULL
              AND m.winner IS NOT NULL
              AND m.loser IS NOT NULL
              AND (m.winner = PLAYER_LOOKUP(?) OR m.loser = PLAYER_LOOKUP(?))
            ORDER BY e.date DESC, e.id DESC, m.id DESC
            LIMIT ?
            """,
            [
                MySQLData(string: name),
                MySQLData(string: name),
                MySQLData(int: limit)
            ]
        ).get()

        return rows.compactMap(makeTennisMatch)
    }

    private func loadPlayerMatchTabs(name: String, playerID: String?, on connection: MySQLConnection) async throws -> [PlayerMatchTab] {
        let matches = try await loadPlayerCareerMatches(name: playerID ?? name, on: connection)

        return PlayerMatchFilter.allCases.compactMap { filter in
            let filteredMatches = filter.matches(from: matches, playerID: playerID, playerName: name)
            guard !filteredMatches.isEmpty else {
                return nil
            }

            return PlayerMatchTab(id: filter.rawValue, title: filter.title, matches: filteredMatches)
        }
    }

    private func loadPlayerCareerMatches(name: String, on connection: MySQLConnection) async throws -> [TennisMatch] {
        let rows = try await connection.query(
            """
            SELECT
                m.id,
                DATE_FORMAT(e.date, '%Y-%m-%d') AS event_date,
                e.name AS event_name,
                e.type AS event_type,
                e.surface AS event_surface,
                m.round,
                m.score,
                m.status,
                m.duration,
                winner.id AS winner_id,
                winner.name AS winner_name,
                winner.country AS winner_country,
                m.winner_rank,
                loser.id AS loser_id,
                loser.name AS loser_name,
                loser.country AS loser_country,
                m.loser_rank
            FROM matches m
            JOIN events e ON e.id = m.event
            LEFT JOIN players winner ON winner.id = m.winner
            LEFT JOIN players loser ON loser.id = m.loser
            WHERE e.date IS NOT NULL
              AND m.winner IS NOT NULL
              AND m.loser IS NOT NULL
              AND (m.winner = PLAYER_LOOKUP(?) OR m.loser = PLAYER_LOOKUP(?))
            ORDER BY e.date DESC,
              FIELD(m.round, 'F', 'SF', 'QF', 'R16', 'R32', 'R64', 'R128', 'Q3', 'Q2', 'Q1', 'RR', 'RR2', 'RR3', 'RR4', 'RR5', 'RR6', 'BR') ASC,
              e.id DESC,
              m.id DESC
            """,
            [
                MySQLData(string: name),
                MySQLData(string: name)
            ]
        ).get()

        return rows.compactMap(makeTennisMatch)
    }

    private func makeTennisMatch(row: MySQLRow) -> TennisMatch? {
        guard
            let id = row.string("id"),
            let eventDate = row.string("event_date"),
            let eventName = row.string("event_name"),
            let winnerName = row.string("winner_name"),
            let loserName = row.string("loser_name")
        else {
            return nil
        }

        return TennisMatch(
            id: id,
            date: eventDate,
            tournament: eventName,
            eventType: row.string("event_type"),
            surface: row.string("event_surface"),
            round: row.string("round"),
            score: row.string("score"),
            status: row.string("status"),
            duration: row.string("duration"),
            playerA: MatchPlayer(
                id: row.string("winner_id"),
                name: winnerName,
                country: row.string("winner_country"),
                rank: row.int("winner_rank"),
                odds: nil
            ),
            playerB: MatchPlayer(
                id: row.string("loser_id"),
                name: loserName,
                country: row.string("loser_country"),
                rank: row.int("loser_rank"),
                odds: nil
            )
        )
    }

    private func loadPlayerStats(name: String, surface: TennisSurface, on connection: MySQLConnection) async throws -> PlayerDashboardStats? {
        let surfaceName = surface.rawValue.capitalized
        let rows = try await connection.query(
            """
            SELECT
                p.id,
                p.name,
                p.country,
                p.age,
                p.pro,
                p.height,
                p.weight,
                p.rank,
                p.points,
                p.highest_rank,
                DATE_FORMAT(p.highest_rank_date, '%Y-%m-%d') AS highest_rank_date,
                p.career_titles,
                p.career_prize,
                p.ytd_wins AS player_ytd_wins,
                p.ytd_losses AS player_ytd_losses,
                p.ytd_titles,
                p.ytd_prize,
                p.serve_rating,
                p.return_rating,
                p.pressure_rating,
                p.elo_rank,
                p.elo_rank_hard,
                p.elo_rank_clay,
                p.elo_rank_grass,
                CAST(SUM(CASE WHEN e.type = 'Grand Slam' AND m.round = 'F' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS grand_slam_titles,
                CAST(SUM(CASE WHEN e.type = 'Masters' AND m.round = 'F' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS masters_titles,
                CAST(SUM(CASE WHEN e.type = 'ATP-500' AND m.round = 'F' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS atp500_titles,
                CAST(SUM(CASE WHEN e.type = 'ATP-250' AND m.round = 'F' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS atp250_titles,
                CAST(SUM(CASE WHEN e.type IN ('Grand Slam', 'Masters', 'ATP-500', 'ATP-250') THEN 1 ELSE 0 END) AS SIGNED) AS total_matches,
                CAST(SUM(CASE WHEN e.type IN ('Grand Slam', 'Masters', 'ATP-500', 'ATP-250') AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS total_wins,
                CAST(SUM(CASE WHEN e.type IN ('Grand Slam', 'Masters', 'ATP-500', 'ATP-250') AND YEAR(e.date) = YEAR(CURDATE()) THEN 1 ELSE 0 END) AS SIGNED) AS ytd_matches,
                CAST(SUM(CASE WHEN e.type IN ('Grand Slam', 'Masters', 'ATP-500', 'ATP-250') AND YEAR(e.date) = YEAR(CURDATE()) AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS ytd_wins,
                CAST(SUM(CASE WHEN e.date >= CURDATE() - INTERVAL 365 DAY THEN 1 ELSE 0 END) AS SIGNED) AS recent_matches,
                CAST(SUM(CASE WHEN e.date >= CURDATE() - INTERVAL 365 DAY AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS recent_wins,
                CAST(SUM(CASE WHEN e.surface = ? THEN 1 ELSE 0 END) AS SIGNED) AS surface_matches,
                CAST(SUM(CASE WHEN e.surface = ? AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS surface_wins,
                CAST(SUM(CASE WHEN e.surface = 'Hard' THEN 1 ELSE 0 END) AS SIGNED) AS hard_matches,
                CAST(SUM(CASE WHEN e.surface = 'Hard' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS hard_wins,
                CAST(SUM(CASE WHEN e.surface = 'Clay' THEN 1 ELSE 0 END) AS SIGNED) AS clay_matches,
                CAST(SUM(CASE WHEN e.surface = 'Clay' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS clay_wins,
                CAST(SUM(CASE WHEN e.surface = 'Grass' THEN 1 ELSE 0 END) AS SIGNED) AS grass_matches,
                CAST(SUM(CASE WHEN e.surface = 'Grass' AND m.winner = p.id THEN 1 ELSE 0 END) AS SIGNED) AS grass_wins
            FROM players p
            LEFT JOIN matches m ON (m.winner = p.id OR m.loser = p.id)
              AND m.winner IS NOT NULL
              AND m.loser IS NOT NULL
            LEFT JOIN events e ON e.id = m.event
            WHERE p.id = PLAYER_LOOKUP(?)
            GROUP BY
                p.id,
                p.name,
                p.country,
                p.age,
                p.pro,
                p.height,
                p.weight,
                p.rank,
                p.points,
                p.highest_rank,
                p.highest_rank_date,
                p.career_titles,
                p.career_prize,
                p.ytd_wins,
                p.ytd_losses,
                p.ytd_titles,
                p.ytd_prize,
                p.serve_rating,
                p.return_rating,
                p.pressure_rating,
                p.elo_rank,
                p.elo_rank_hard,
                p.elo_rank_clay,
                p.elo_rank_grass
            LIMIT 1
            """,
            [
                MySQLData(string: surfaceName),
                MySQLData(string: surfaceName),
                MySQLData(string: name)
            ]
        ).get()

        guard let row = rows.first, let id = row.string("id"), let playerName = row.string("name") else {
            return nil
        }

        let form = try await loadRecentForm(playerID: id, limit: 12, on: connection)

        return PlayerDashboardStats(
            id: id,
            name: playerName,
            country: row.string("country"),
            age: row.int("age"),
            pro: row.int("pro"),
            height: row.int("height"),
            weight: row.int("weight"),
            rank: row.int("rank"),
            points: row.int("points"),
            highestRank: row.int("highest_rank"),
            highestRankDate: row.string("highest_rank_date"),
            careerTitles: row.int("career_titles"),
            grandSlamTitles: row.int("grand_slam_titles") ?? 0,
            mastersTitles: row.int("masters_titles") ?? 0,
            atp500Titles: row.int("atp500_titles") ?? 0,
            atp250Titles: row.int("atp250_titles") ?? 0,
            careerPrize: row.int("career_prize"),
            ytdWins: row.int("ytd_wins"),
            ytdLosses: (row.int("ytd_matches") ?? 0) - (row.int("ytd_wins") ?? 0),
            ytdTitles: row.int("ytd_titles"),
            ytdPrize: row.int("ytd_prize"),
            serveRating: row.double("serve_rating"),
            returnRating: row.double("return_rating"),
            pressureRating: row.double("pressure_rating"),
            eloRank: row.int("elo_rank"),
            hardElo: row.int("elo_rank_hard"),
            clayElo: row.int("elo_rank_clay"),
            grassElo: row.int("elo_rank_grass"),
            totalMatches: row.int("total_matches") ?? 0,
            totalWins: row.int("total_wins") ?? 0,
            formMatches: form.matches,
            formWins: form.wins,
            recentMatches: row.int("recent_matches") ?? 0,
            recentWins: row.int("recent_wins") ?? 0,
            surfaceMatches: row.int("surface_matches") ?? 0,
            surfaceWins: row.int("surface_wins") ?? 0,
            hardMatches: row.int("hard_matches") ?? 0,
            hardWins: row.int("hard_wins") ?? 0,
            clayMatches: row.int("clay_matches") ?? 0,
            clayWins: row.int("clay_wins") ?? 0,
            grassMatches: row.int("grass_matches") ?? 0,
            grassWins: row.int("grass_wins") ?? 0
        )
    }

    private func loadRecentForm(playerID: String, limit: Int, on connection: MySQLConnection) async throws -> (matches: Int, wins: Int) {
        let rows = try await connection.query(
            """
            SELECT
                CAST(COUNT(*) AS SIGNED) AS form_matches,
                CAST(SUM(CASE WHEN recent.winner = ? THEN 1 ELSE 0 END) AS SIGNED) AS form_wins
            FROM (
                SELECT
                    m.winner
                FROM matches m
                JOIN events e ON e.id = m.event
                WHERE e.date IS NOT NULL
                  AND e.type IN ('Grand Slam', 'Masters', 'ATP-500', 'ATP-250')
                  AND m.winner IS NOT NULL
                  AND m.loser IS NOT NULL
                  AND (m.winner = ? OR m.loser = ?)
                ORDER BY e.date DESC, e.id DESC, m.id DESC
                LIMIT ?
            ) recent
            """,
            [
                MySQLData(string: playerID),
                MySQLData(string: playerID),
                MySQLData(string: playerID),
                MySQLData(int: limit)
            ]
        ).get()

        guard let row = rows.first else {
            return (0, 0)
        }

        return (
            matches: row.int("form_matches") ?? 0,
            wins: row.int("form_wins") ?? 0
        )
    }

    private func loadMatchPlayer(name: String, fallbackOdds: Double?, on connection: MySQLConnection) async throws -> MatchPlayer? {
        let rows = try await connection.query(
            """
            SELECT
                id,
                name,
                country,
                rank
            FROM players
            WHERE id = PLAYER_LOOKUP(?)
            LIMIT 1
            """,
            [
                MySQLData(string: name)
            ]
        ).get()

        guard let row = rows.first, let resolvedName = row.string("name") else {
            return nil
        }

        return MatchPlayer(
            id: row.string("id"),
            name: resolvedName,
            country: row.string("country"),
            rank: row.int("rank"),
            odds: fallbackOdds
        )
    }

    private func merge(_ original: MatchPlayer, with resolved: MatchPlayer?) -> MatchPlayer {
        guard let resolved else {
            return original
        }

        return MatchPlayer(
            id: resolved.id ?? original.id,
            name: resolved.name,
            country: resolved.country ?? original.country,
            rank: resolved.rank ?? original.rank,
            odds: original.odds
        )
    }

    private func loadHeadToHead(playerA: String, playerB: String, on connection: MySQLConnection) async throws -> (playerAWins: Int, playerBWins: Int) {
        let rows = try await connection.query(
            """
            SELECT
                CAST(SUM(CASE WHEN m.winner = PLAYER_LOOKUP(?) THEN 1 ELSE 0 END) AS SIGNED) AS player_a_wins,
                CAST(SUM(CASE WHEN m.winner = PLAYER_LOOKUP(?) THEN 1 ELSE 0 END) AS SIGNED) AS player_b_wins
            FROM matches m
            WHERE m.winner IS NOT NULL
              AND m.loser IS NOT NULL
              AND (
                (m.winner = PLAYER_LOOKUP(?) AND m.loser = PLAYER_LOOKUP(?))
                OR
                (m.winner = PLAYER_LOOKUP(?) AND m.loser = PLAYER_LOOKUP(?))
              )
            """,
            [
                MySQLData(string: playerA),
                MySQLData(string: playerB),
                MySQLData(string: playerA),
                MySQLData(string: playerB),
                MySQLData(string: playerB),
                MySQLData(string: playerA)
            ]
        ).get()

        guard let row = rows.first else {
            return (0, 0)
        }

        return (
            playerAWins: row.int("player_a_wins") ?? 0,
            playerBWins: row.int("player_b_wins") ?? 0
        )
    }

    private func loadHeadToHeadMatches(playerA: String, playerB: String, on connection: MySQLConnection) async throws -> [HeadToHeadMatch] {
        let rows = try await connection.query(
            """
            SELECT
                m.id,
                DATE_FORMAT(e.date, '%Y-%m-%d') AS event_date,
                e.name AS event_name,
                e.surface AS event_surface,
                winner.name AS winner_name,
                m.winner_rank,
                loser.name AS loser_name,
                m.loser_rank,
                m.score
            FROM matches m
            JOIN events e ON e.id = m.event
            JOIN players winner ON winner.id = m.winner
            JOIN players loser ON loser.id = m.loser
            WHERE e.date IS NOT NULL
              AND m.winner IS NOT NULL
              AND m.loser IS NOT NULL
              AND (
                (m.winner = PLAYER_LOOKUP(?) AND m.loser = PLAYER_LOOKUP(?))
                OR
                (m.winner = PLAYER_LOOKUP(?) AND m.loser = PLAYER_LOOKUP(?))
              )
            ORDER BY e.date DESC, e.id DESC, m.id DESC
            LIMIT 20
            """,
            [
                MySQLData(string: playerA),
                MySQLData(string: playerB),
                MySQLData(string: playerB),
                MySQLData(string: playerA)
            ]
        ).get()

        return rows.compactMap { row in
            guard
                let id = row.string("id"),
                let date = row.string("event_date"),
                let event = row.string("event_name"),
                let winner = row.string("winner_name"),
                let loser = row.string("loser_name")
            else {
                return nil
            }

            return HeadToHeadMatch(
                id: id,
                date: date,
                tournament: event,
                surface: row.string("event_surface"),
                winnerName: winner,
                winnerRank: row.int("winner_rank"),
                loserName: loser,
                loserRank: row.int("loser_rank"),
                score: row.string("score")
            )
        }
    }

    private func loadRankingHistory(name: String, on connection: MySQLConnection) async throws -> [RankingHistoryPoint] {
        let rows = try await connection.query(
            """
            SELECT
                month,
                CAST(MIN(rank_value) AS SIGNED) AS rank_value
            FROM (
                SELECT
                    DATE_FORMAT(e.date, '%Y-%m') AS month,
                    m.winner_rank AS rank_value
                FROM matches m
                JOIN events e ON e.id = m.event
                WHERE m.winner = PLAYER_LOOKUP(?)
                  AND m.winner_rank IS NOT NULL
                  AND m.winner_rank > 0
                  AND e.date >= CURDATE() - INTERVAL 60 MONTH

                UNION ALL

                SELECT
                    DATE_FORMAT(e.date, '%Y-%m') AS month,
                    m.loser_rank AS rank_value
                FROM matches m
                JOIN events e ON e.id = m.event
                WHERE m.loser = PLAYER_LOOKUP(?)
                  AND m.loser_rank IS NOT NULL
                  AND m.loser_rank > 0
                  AND e.date >= CURDATE() - INTERVAL 60 MONTH
            ) ranks
            GROUP BY month
            ORDER BY month ASC
            """,
            [
                MySQLData(string: name),
                MySQLData(string: name)
            ]
        ).get()

        return rows.compactMap { row in
            guard let month = row.string("month"), let rank = row.int("rank_value") else {
                return nil
            }

            return RankingHistoryPoint(id: "\(name)-\(month)", month: month, rank: rank)
        }
    }

    private func loadTennisAbstractOdds(playerA: String, playerB: String, surface: TennisSurface?) async throws -> TennisAbstractOdds {
        try await TennisAbstractOddsClient.shared.loadOdds(playerA: playerA, playerB: playerB, surface: surface)
    }

    private func withConnection<T>(_ work: (MySQLConnection) async throws -> T) async throws -> T {
        try await work(MySQLConnection(client: TennisAPIClient(settings: settings)))
    }
}

private enum PlayerMatchFilter: String, CaseIterable {
    case career
    case wins
    case finals
    case grandSlams
    case masters
    case atp500
    case atp250
    case upsets
    case warnings

    var title: String {
        switch self {
        case .career:
            return "Karriär"
        case .wins:
            return "Vinster"
        case .finals:
            return "Finaler"
        case .grandSlams:
            return "Grand Slams"
        case .masters:
            return "Masters"
        case .atp500:
            return "ATP-500"
        case .atp250:
            return "ATP-250"
        case .upsets:
            return "Skrällar"
        case .warnings:
            return "Varningsflaggor"
        }
    }

    func matches(from matches: [TennisMatch], playerID: String?, playerName: String) -> [TennisMatch] {
        switch self {
        case .career:
            return matches
        case .wins:
            return matches.filter { didWin($0, playerID: playerID, playerName: playerName) }
        case .finals:
            return matches.filter { $0.round == "F" }
        case .grandSlams:
            return titleMatches(matches, eventType: "Grand Slam", playerID: playerID, playerName: playerName)
        case .masters:
            return titleMatches(matches, eventType: "Masters", playerID: playerID, playerName: playerName)
        case .atp500:
            return titleMatches(matches, eventType: "ATP-500", playerID: playerID, playerName: playerName)
        case .atp250:
            return titleMatches(matches, eventType: "ATP-250", playerID: playerID, playerName: playerName)
        case .upsets:
            return matches.filter { match in
                guard
                    match.date >= Self.recentCutoffDate,
                    didWin(match, playerID: playerID, playerName: playerName),
                    let ownRank = playerRank(in: match, playerID: playerID, playerName: playerName),
                    let opponentRank = opponentRank(in: match, playerID: playerID, playerName: playerName)
                else {
                    return false
                }

                return opponentRank < ownRank && ownRank - opponentRank >= 15
            }
        case .warnings:
            return matches.filter { match in
                guard
                    match.date >= Self.recentCutoffDate,
                    !didWin(match, playerID: playerID, playerName: playerName),
                    let ownRank = playerRank(in: match, playerID: playerID, playerName: playerName),
                    let opponentRank = opponentRank(in: match, playerID: playerID, playerName: playerName)
                else {
                    return false
                }

                return opponentRank > ownRank && opponentRank - ownRank >= 20
            }
        }
    }

    private func titleMatches(_ matches: [TennisMatch], eventType: String, playerID: String?, playerName: String) -> [TennisMatch] {
        matches.filter { match in
            match.round == "F"
                && match.eventType == eventType
                && didWin(match, playerID: playerID, playerName: playerName)
        }
    }

    private func didWin(_ match: TennisMatch, playerID: String?, playerName: String) -> Bool {
        isPlayer(match.playerA, playerID: playerID, playerName: playerName)
    }

    private func playerRank(in match: TennisMatch, playerID: String?, playerName: String) -> Int? {
        if isPlayer(match.playerA, playerID: playerID, playerName: playerName) {
            return match.playerA.rank
        }

        if isPlayer(match.playerB, playerID: playerID, playerName: playerName) {
            return match.playerB.rank
        }

        return nil
    }

    private func opponentRank(in match: TennisMatch, playerID: String?, playerName: String) -> Int? {
        if isPlayer(match.playerA, playerID: playerID, playerName: playerName) {
            return match.playerB.rank
        }

        if isPlayer(match.playerB, playerID: playerID, playerName: playerName) {
            return match.playerA.rank
        }

        return nil
    }

    private func isPlayer(_ player: MatchPlayer, playerID: String?, playerName: String) -> Bool {
        if let playerID, player.id == playerID {
            return true
        }

        return player.name.caseInsensitiveCompare(playerName) == .orderedSame
    }

    private static let recentCutoffDate: String = {
        let calendar = Calendar(identifier: .gregorian)
        let cutoff = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: cutoff)
    }()
}

private func roundOdds(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

private extension MySQLRow {
    func string(_ column: String) -> String? {
        self.column(column)?.string
    }

    func int(_ column: String) -> Int? {
        self.column(column)?.int
    }

    func double(_ column: String) -> Double? {
        self.column(column)?.double
    }
}
