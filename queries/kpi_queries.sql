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
