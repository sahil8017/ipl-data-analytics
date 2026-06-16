-- IPL Data Analytics KPI Views and Queries
-- Database: ipl_db

--------------------------------------------------------------------------------
-- FOCUS AREA 1: TEAM PERFORMANCE ANALYSIS
--------------------------------------------------------------------------------

-- View 1: Team overall performance (matches played, won, lost, and win percentage)
CREATE OR REPLACE VIEW vw_team_performance AS
WITH team_matches AS (
    -- Get count of matches played by each team (either as team1 or team2)
    SELECT team, COUNT(*) AS matches_played
    FROM (
        SELECT team1 AS team FROM matches
        UNION ALL
        SELECT team2 AS team FROM matches
    ) t
    GROUP BY team
),
team_wins AS (
    -- Get count of matches won by each team
    SELECT winner AS team, COUNT(*) AS matches_won
    FROM matches
    WHERE winner IS NOT NULL
    GROUP BY winner
)
SELECT 
    tm.team,
    tm.matches_played,
    COALESCE(tw.matches_won, 0) AS matches_won,
    (tm.matches_played - COALESCE(tw.matches_won, 0)) AS matches_lost,
    ROUND((COALESCE(tw.matches_won, 0)::NUMERIC / tm.matches_played::NUMERIC) * 100, 2) AS win_percentage
FROM team_matches tm
LEFT JOIN team_wins tw ON tm.team = tw.team
ORDER BY win_percentage DESC;

-- View 2: Toss Decision Impact (toss winner win rate and choices)
CREATE OR REPLACE VIEW vw_toss_impact AS
SELECT 
    toss_decision,
    COUNT(*) AS total_matches,
    SUM(CASE WHEN toss_winner = winner THEN 1 ELSE 0 END) AS toss_winner_wins,
    ROUND((SUM(CASE WHEN toss_winner = winner THEN 1 ELSE 0 END)::NUMERIC / COUNT(*)) * 100, 2) AS toss_winner_win_percentage
FROM matches
GROUP BY toss_decision;


--------------------------------------------------------------------------------
-- FOCUS AREA 2: PLAYER PERFORMANCE ANALYSIS
--------------------------------------------------------------------------------

-- View 3: Orange Cap (Top 15 Run Scorers overall)
CREATE OR REPLACE VIEW vw_orange_cap AS
SELECT 
    batter,
    COUNT(DISTINCT match_id) AS matches_played,
    SUM(batsman_runs) AS total_runs,
    SUM(CASE WHEN batsman_runs = 4 THEN 1 ELSE 0 END) AS fours,
    SUM(CASE WHEN batsman_runs = 6 THEN 1 ELSE 0 END) AS sixes,
    ROUND((SUM(batsman_runs)::NUMERIC / COUNT(ball)::NUMERIC) * 100, 2) AS strike_rate
FROM deliveries
GROUP BY batter
HAVING SUM(batsman_runs) >= 1000
ORDER BY total_runs DESC;

-- View 4: Purple Cap (Top 15 Wicket Takers overall)
-- Note: Excludes run-outs and retired hurt as they are not credited to the bowler
CREATE OR REPLACE VIEW vw_purple_cap AS
SELECT 
    bowler,
    COUNT(DISTINCT match_id) AS matches_played,
    COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) AS wickets,
    ROUND((SUM(total_runs - extra_runs)::NUMERIC / (COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0)), 2) AS economy_rate
FROM deliveries
GROUP BY bowler
HAVING COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) >= 50
ORDER BY wickets DESC;


--------------------------------------------------------------------------------
-- FOCUS AREA 3: VENUE-BASED INSIGHTS
--------------------------------------------------------------------------------

-- View 5: Venue Insights (Average scores and chasing vs batting first bias)
CREATE OR REPLACE VIEW vw_venue_insights AS
WITH venue_stats AS (
    SELECT 
        venue,
        city,
        COUNT(*) AS total_matches,
        SUM(CASE WHEN result = 'runs' THEN 1 ELSE 0 END) AS won_batting_first,
        SUM(CASE WHEN result = 'wickets' THEN 1 ELSE 0 END) AS won_chasing
    FROM matches
    GROUP BY venue, city
),
innings_avg AS (
    SELECT 
        m.venue,
        m.city,
        ROUND(AVG(CASE WHEN d.inning = 1 THEN inning_runs END), 1) AS avg_1st_innings_score,
        ROUND(AVG(CASE WHEN d.inning = 2 THEN inning_runs END), 1) AS avg_2nd_innings_score
    FROM matches m
    JOIN (
        SELECT match_id, inning, SUM(total_runs) AS inning_runs
        FROM deliveries
        WHERE inning IN (1, 2)
        GROUP BY match_id, inning
    ) d ON m.match_id = d.match_id
    GROUP BY m.venue, m.city
)
SELECT 
    vs.venue,
    vs.city,
    vs.total_matches,
    vs.won_batting_first,
    vs.won_chasing,
    ROUND((vs.won_batting_first::NUMERIC / vs.total_matches) * 100, 2) AS bat_first_win_pct,
    ROUND((vs.won_chasing::NUMERIC / vs.total_matches) * 100, 2) AS chase_win_pct,
    ia.avg_1st_innings_score,
    ia.avg_2nd_innings_score
FROM venue_stats vs
LEFT JOIN innings_avg ia ON vs.venue = ia.venue AND vs.city = ia.city
WHERE vs.total_matches >= 10
ORDER BY total_matches DESC;


--------------------------------------------------------------------------------
-- FOCUS AREA 4: SEASON-WISE TRENDS
--------------------------------------------------------------------------------

-- View 6: Season Trends (runs scored, boundaries, run rate trends)
CREATE OR REPLACE VIEW vw_season_trends AS
SELECT 
    m.season,
    COUNT(DISTINCT m.match_id) AS total_matches,
    SUM(d.total_runs) AS total_runs,
    SUM(CASE WHEN d.batsman_runs = 4 THEN 1 ELSE 0 END) AS total_fours,
    SUM(CASE WHEN d.batsman_runs = 6 THEN 1 ELSE 0 END) AS total_sixes,
    ROUND(SUM(d.total_runs)::NUMERIC / (COUNT(CASE WHEN d.extra_type IS NULL OR d.extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0), 2) AS season_run_rate
FROM matches m
JOIN deliveries d ON m.match_id = d.match_id
GROUP BY m.season
ORDER BY m.season ASC;


--------------------------------------------------------------------------------
-- FOCUS AREA 5: MATCH OUTCOME PATTERNS
--------------------------------------------------------------------------------

-- Query: Largest victory margins (by runs)
-- SELECT * FROM matches WHERE result = 'runs' ORDER BY result_margin DESC LIMIT 5;

-- Query: Largest victory margins (by wickets)
-- SELECT * FROM matches WHERE result = 'wickets' ORDER BY result_margin DESC LIMIT 5;

-- Query: Close finishes (wins by <= 3 runs or <= 1 wicket)
-- SELECT winner, result, result_margin, venue FROM matches WHERE (result = 'runs' AND result_margin <= 3) OR (result = 'wickets' AND result_margin = 1) LIMIT 10;


--------------------------------------------------------------------------------
-- FOCUS AREA 6: IPL CHAMPIONSHIP & FINALS INSIGHTS
--------------------------------------------------------------------------------

-- View 7: Finals summary (team reached vs won vs lost in finals)
CREATE OR REPLACE VIEW vw_finals_summary AS
WITH finalists AS (
    SELECT season, team1 AS team, CASE WHEN winner = team1 THEN 1 ELSE 0 END AS won FROM matches WHERE stage = 'Final'
    UNION ALL
    SELECT season, team2 AS team, CASE WHEN winner = team2 THEN 1 ELSE 0 END AS won FROM matches WHERE stage = 'Final'
)
SELECT 
    team,
    COUNT(*) AS finals_reached,
    SUM(won) AS finals_won,
    (COUNT(*) - SUM(won)) AS finals_lost,
    ROUND((SUM(won)::NUMERIC / COUNT(*)::NUMERIC) * 100, 2) AS win_percentage
FROM finalists
GROUP BY team
ORDER BY finals_reached DESC, finals_won DESC;

-- View 8: Champion League Stage Standings
CREATE OR REPLACE VIEW vw_champion_league_positions AS
WITH league_match_results AS (
    SELECT 
        season,
        match_id,
        team1 AS team,
        CASE 
            WHEN winner = team1 THEN 2
            WHEN winner IS NULL OR result IN ('tie', 'no result') THEN 1
            ELSE 0
        END AS points,
        CASE WHEN winner = team1 THEN 1 ELSE 0 END AS won
    FROM matches
    WHERE stage IS NULL
    
    UNION ALL
    
    SELECT 
        season,
        match_id,
        team2 AS team,
        CASE 
            WHEN winner = team2 THEN 2
            WHEN winner IS NULL OR result IN ('tie', 'no result') THEN 1
            ELSE 0
        END AS points,
        CASE WHEN winner = team2 THEN 1 ELSE 0 END AS won
    FROM matches
    WHERE stage IS NULL
),
league_standings AS (
    SELECT 
        season,
        team,
        SUM(points) AS total_points,
        SUM(won) AS total_wins,
        ROW_NUMBER() OVER (
            PARTITION BY season 
            ORDER BY SUM(points) DESC, SUM(won) DESC
        ) AS league_position
    FROM league_match_results
    GROUP BY season, team
),
champions AS (
    SELECT season, winner AS champion
    FROM matches
    WHERE stage = 'Final' AND winner IS NOT NULL
)
SELECT 
    c.season,
    c.champion,
    ls.league_position AS champion_league_position,
    ls.total_points AS champion_points,
    ls.total_wins AS champion_wins
FROM champions c
JOIN league_standings ls ON c.season = ls.season AND c.champion = ls.team
ORDER BY c.season DESC;

-- View 9: Orange Cap winner by season
CREATE OR REPLACE VIEW vw_orange_cap_by_season AS
WITH batter_runs AS (
    SELECT 
        m.season,
        d.batter,
        SUM(d.batsman_runs) AS total_runs,
        COUNT(DISTINCT d.match_id) AS matches_played,
        ROUND((SUM(d.batsman_runs)::NUMERIC / COUNT(d.ball)::NUMERIC) * 100, 2) AS strike_rate,
        ROW_NUMBER() OVER (PARTITION BY m.season ORDER BY SUM(d.batsman_runs) DESC) AS rank
    FROM deliveries d
    JOIN matches m ON d.match_id = m.match_id
    GROUP BY m.season, d.batter
)
SELECT season, batter AS orange_cap_winner, total_runs, matches_played, strike_rate
FROM batter_runs
WHERE rank = 1
ORDER BY season DESC;

-- View 10: Purple Cap winner by season
CREATE OR REPLACE VIEW vw_purple_cap_by_season AS
WITH bowler_wickets AS (
    SELECT 
        m.season,
        d.bowler,
        COUNT(CASE WHEN d.is_wicket = 1 AND d.dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) AS wickets,
        COUNT(DISTINCT d.match_id) AS matches_played,
        ROUND((SUM(d.total_runs - d.extra_runs)::NUMERIC / (COUNT(CASE WHEN d.extra_type IS NULL OR d.extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0)), 2) AS economy_rate,
        ROW_NUMBER() OVER (
            PARTITION BY m.season 
            ORDER BY COUNT(CASE WHEN d.is_wicket = 1 AND d.dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) DESC,
                     ROUND((SUM(d.total_runs - d.extra_runs)::NUMERIC / (COUNT(CASE WHEN d.extra_type IS NULL OR d.extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0)), 2) ASC
        ) AS rank
    FROM deliveries d
    JOIN matches m ON d.match_id = m.match_id
    GROUP BY m.season, d.bowler
)
SELECT season, bowler AS purple_cap_winner, wickets, matches_played, economy_rate
FROM bowler_wickets
WHERE rank = 1
ORDER BY season DESC;

-- View 11: Finals targets and chase analysis
CREATE OR REPLACE VIEW vw_finals_target_analysis AS
WITH final_matches AS (
    SELECT match_id, season, date, team1, team2, winner, result, result_margin
    FROM matches
    WHERE stage = 'Final'
),
final_innings_runs AS (
    SELECT 
        fm.match_id,
        fm.season,
        fm.date,
        d.inning,
        d.batting_team,
        d.bowling_team,
        SUM(d.total_runs) AS inning_runs,
        fm.winner,
        fm.result,
        fm.result_margin
    FROM final_matches fm
    JOIN deliveries d ON fm.match_id = d.match_id
    WHERE d.inning IN (1, 2)
    GROUP BY fm.match_id, fm.season, fm.date, d.inning, d.batting_team, d.bowling_team, fm.winner, fm.result, fm.result_margin
)
SELECT 
    season,
    date,
    MAX(CASE WHEN inning = 1 THEN inning_runs END) AS first_innings_score,
    (MAX(CASE WHEN inning = 1 THEN inning_runs END) + 1) AS target_set,
    MAX(CASE WHEN inning = 2 THEN inning_runs END) AS second_innings_score,
    winner,
    result,
    result_margin,
    CASE WHEN winner = (SELECT batting_team FROM final_innings_runs WHERE match_id = fir.match_id AND inning = 2) THEN 'Chased' ELSE 'Defended' END AS chase_status
FROM final_innings_runs fir
GROUP BY match_id, season, date, winner, result, result_margin
ORDER BY season DESC;

--------------------------------------------------------------------------------
-- FOCUS AREA 7: POWERPLAY & DEATH OVERS INSIGHTS (ADVANCED SQL)
--------------------------------------------------------------------------------

-- View 12: Highest Powerplay Scores (overs 0-5)
CREATE OR REPLACE VIEW vw_highest_powerplay_scores AS
SELECT 
    m.season,
    m.date,
    d.match_id,
    d.inning,
    d.batting_team,
    d.bowling_team,
    SUM(d.total_runs) AS powerplay_runs,
    SUM(d.is_wicket) AS powerplay_wickets,
    m.venue,
    m.city
FROM deliveries d
JOIN matches m ON d.match_id = m.match_id
WHERE d.over BETWEEN 0 AND 5
GROUP BY m.season, m.date, d.match_id, d.inning, d.batting_team, d.bowling_team, m.venue, m.city
ORDER BY powerplay_runs DESC;

-- View 13: Powerplay Batting Leaders (minimum 300 runs in overs 0-5)
CREATE OR REPLACE VIEW vw_powerplay_batting_stats AS
SELECT 
    batter,
    COUNT(DISTINCT match_id) AS matches_played,
    SUM(batsman_runs) AS powerplay_runs,
    COUNT(ball) AS powerplay_balls_faced,
    ROUND((SUM(batsman_runs)::NUMERIC / COUNT(ball)::NUMERIC) * 100, 2) AS powerplay_strike_rate,
    COUNT(CASE WHEN player_dismissed = batter THEN 1 END) AS dismissals,
    ROUND(SUM(batsman_runs)::NUMERIC / NULLIF(COUNT(CASE WHEN player_dismissed = batter THEN 1 END), 0), 2) AS powerplay_average
FROM deliveries
WHERE over BETWEEN 0 AND 5
GROUP BY batter
HAVING SUM(batsman_runs) >= 300
ORDER BY powerplay_runs DESC;

-- View 14: Powerplay Bowling Leaders (minimum 15 wickets in overs 0-5)
CREATE OR REPLACE VIEW vw_powerplay_bowling_stats AS
SELECT 
    bowler,
    COUNT(DISTINCT match_id) AS matches_played,
    COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) AS powerplay_wickets,
    COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END) AS powerplay_balls_bowled,
    SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END) AS powerplay_runs_conceded,
    ROUND((SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END)::NUMERIC / (COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0)), 2) AS powerplay_economy,
    ROUND(SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END)::NUMERIC / NULLIF(COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END), 0), 2) AS powerplay_bowling_average,
    ROUND(COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / NULLIF(COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END), 0), 2) AS powerplay_strike_rate
FROM deliveries
WHERE over BETWEEN 0 AND 5
GROUP BY bowler
HAVING COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) >= 15
ORDER BY powerplay_wickets DESC;

-- View 15: Death Overs Batting Leaders (overs 15-19, minimum 300 runs)
CREATE OR REPLACE VIEW vw_death_overs_batting_stats AS
SELECT 
    batter,
    COUNT(DISTINCT match_id) AS matches_played,
    SUM(batsman_runs) AS death_runs,
    COUNT(ball) AS death_balls_faced,
    ROUND((SUM(batsman_runs)::NUMERIC / COUNT(ball)::NUMERIC) * 100, 2) AS death_strike_rate,
    COUNT(CASE WHEN player_dismissed = batter THEN 1 END) AS dismissals,
    ROUND(SUM(batsman_runs)::NUMERIC / NULLIF(COUNT(CASE WHEN player_dismissed = batter THEN 1 END), 0), 2) AS death_average
FROM deliveries
WHERE over BETWEEN 15 AND 19
GROUP BY batter
HAVING SUM(batsman_runs) >= 300
ORDER BY death_runs DESC;

-- View 16: Death Overs Bowling Leaders (overs 15-19, minimum 20 wickets)
CREATE OR REPLACE VIEW vw_death_overs_bowling_stats AS
SELECT 
    bowler,
    COUNT(DISTINCT match_id) AS matches_played,
    COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) AS death_wickets,
    COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END) AS death_balls_bowled,
    SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END) AS death_runs_conceded,
    ROUND((SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END)::NUMERIC / (COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / 6.0)), 2) AS death_economy,
    ROUND(SUM(batsman_runs + CASE WHEN extra_type IN ('wides', 'noballs') THEN extra_runs ELSE 0 END)::NUMERIC / NULLIF(COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END), 0), 2) AS death_bowling_average,
    ROUND(COUNT(CASE WHEN extra_type IS NULL OR extra_type NOT IN ('wides', 'noballs') THEN 1 END)::NUMERIC / NULLIF(COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END), 0), 2) AS death_strike_rate
FROM deliveries
WHERE over BETWEEN 15 AND 19
GROUP BY bowler
HAVING COUNT(CASE WHEN is_wicket = 1 AND dismissal_kind NOT IN ('run out', 'retired hurt', 'obstructing the field') THEN 1 END) >= 20
ORDER BY death_wickets DESC;

