# IPL Data Analytics: Power BI Dashboard Creation Guide

This guide details how to build a premium, professional 4-page interactive dashboard in Power BI using the pre-compiled PostgreSQL database views.

---

## 🎨 Theme & Design Aesthetics

For an IPL/Sports dashboard, a **Premium Dark Theme** works best (mirroring night matches and broadcast graphics).

*   **Background**: Very dark grey/navy (e.g., `#0F172A` or `#1E293B`).
*   **Card Backgrounds**: Slightly lighter grey/blue (e.g., `#1E293B` or `#334155`) with rounded corners (8px–12px) and subtle white borders (10%-20% opacity).
*   **Primary Accent (Vibrancy)**: Neon Blue (`#38BDF8`) or Gold (`#F59E0B`).
*   **Secondary Accents**: Purple/Indigo (`#6366F1`) or Cricket Green (`#10B981`).
*   **Typography**: Inter or Segoe UI (clean, high legibility).

---

## 📑 Dashboard Layout & Structure

We will divide the dashboard into **4 clean pages**:
1. **Overview & Season Trends**
2. **Team Performance & Toss Impact**
3. **Player Statistics (Orange & Purple Caps)**
4. **Venue Analysis**

---

### Page 1: Overview & Season Trends
*Focus: Overall tournament health, boundaries, and year-on-year trends.*

#### 1. Header & Global Filters
*   **Title**: `IPL Tournament Overview (2008 - 2026)`
*   **Season Slicer**: Add a **Slicer** visual using the `season` column from `vw_season_trends`. Format it as a **Dropdown** or **Horizontal tile list** placed in the top right corner.

#### 2. KPI Cards (Top Row)
Add 4 **Card** (or Multi-row Card) visuals at the top:
*   **Total Matches**: `SUM(total_matches)` from `vw_season_trends`.
*   **Total Runs Scored**: `SUM(total_runs)` from `vw_season_trends` (Format display units as Millions/Thousands).
*   **Total Fours**: `SUM(total_fours)` from `vw_season_trends`.
*   **Total Sixes**: `SUM(total_sixes)` from `vw_season_trends`.

#### 3. Visualizations (Body)
*   **Visual A: Season-on-Season Scoring & Run Rate** (Combined Line & Clustered Column Chart)
    *   *X-Axis*: `season`
    *   *Column Y-Axis*: `total_runs`
    *   *Line Y-Axis*: `season_run_rate`
    *   *Insight*: Shows if the tournament is becoming higher scoring over time.
*   **Visual B: Sixes vs Fours Trend** (Area Chart or Line Chart)
    *   *X-Axis*: `season`
    *   *Y-Axis*: `total_fours` and `total_sixes` (two lines)
    *   *Insight*: Tracks boundary habits year-over-year.

---

### Page 2: Team Performance & Toss Impact
*Focus: Which teams dominate, and how much does winning the toss help?*

#### 1. Header & Slicers
*   **Title**: `Team Performance & Toss Analytics`
*   **Season Slicer**: Synergize/Sync the season slicer from Page 1.

#### 2. Visualizations
*   **Visual A: Team Win Leaderboard** (Clustered Bar Chart)
    *   *Y-Axis*: `team` (from `vw_team_performance`)
    *   *X-Axis*: `win_percentage`
    *   *Tooltip*: `matches_played`, `matches_won`
    *   *Formatting*: Sort descending by win percentage. Highlight top teams with an accent color.
*   **Visual B: Wins vs Losses** (Stacked Bar Chart or Clustered Column Chart)
    *   *X-Axis*: `team`
    *   *Y-Axis*: `matches_won` and `matches_lost`
*   **Visual C: Toss Winner Win Bias** (Donut Chart)
    *   *Legend / Details*: Create a field or measure for "Toss Winner Won Match" vs "Toss Winner Lost Match" from `vw_toss_impact`.
    *   *Values*: `toss_winner_wins` vs (`total_matches` - `toss_winner_wins`).
    *   *Insight*: Clearly displays the statistical percentage of matches won by the team that won the toss.
*   **Visual D: Toss Decision Impact** (Clustered Column Chart)
    *   *X-Axis*: `toss_decision` (Bat vs Field)
    *   *Y-Axis*: `total_matches` and `toss_winner_wins`

---

### Page 3: Player Statistics
*Focus: Individual batting and bowling achievements.*

#### 1. Header & Slicers
*   **Title**: `Player Performance (Orange & Purple Caps)`
*   **Batter/Bowler Search Box**: Add a **Text Search Slicer** or dropdown for filtering specific players.

#### 2. Visualizations
*   **Visual A: Orange Cap Leaderboard** (Table or Horizontal Bar Chart)
    *   *Data Source*: `vw_orange_cap`
    *   *Columns / Y-Axis*: `batter`
    *   *Values / X-Axis*: `total_runs`
    *   *Tooltips / Columns*: `matches_played`, `strike_rate`, `fours`, `sixes`
    *   *Style*: Add conditional formatting data bars to the `total_runs` column if using a Table.
*   **Visual B: Purple Cap Leaderboard** (Table or Horizontal Bar Chart)
    *   *Data Source*: `vw_purple_cap`
    *   *Columns / Y-Axis*: `bowler`
    *   *Values / X-Axis*: `wickets`
    *   *Tooltips / Columns*: `matches_played`, `economy_rate`
*   **Visual C: Batting Efficiency** (Scatter Plot)
    *   *Details/Legend*: `batter`
    *   *X-Axis*: `total_runs`
    *   *Y-Axis*: `strike_rate`
    *   *Insight*: Quadrant analysis showing high-run/high-strike-rate players (top-right are elite, fast-scoring batsmen).

---

### Page 4: Venue Analysis
*Focus: How do stadiums influence match outcomes?*

#### 1. Header & Slicers
*   **Title**: `Venue & Stadium Insights`

#### 2. Visualizations
*   **Visual A: Average Inning Score per Venue** (Clustered Bar Chart)
    *   *Y-Axis*: `venue` (from `vw_venue_insights`)
    *   *X-Axis*: `avg_1st_innings_score` and `avg_2nd_innings_score` (side-by-side)
    *   *Insight*: Shows which pitches are batting-friendly and which are slower.
*   **Visual B: Chasing vs Defending Success Rate** (100% Stacked Bar Chart)
    *   *Y-Axis*: `venue`
    *   *X-Axis*: `bat_first_win_pct` and `chase_win_pct`
    *   *Formatting*: Set `bat_first` to one color (e.g. Gold) and `chase` to another (e.g. Blue).
    *   *Insight*: Helps users visually identify "chasing grounds" vs "defending grounds".
*   **Visual C: Top Venues by Matches Played** (Treemap or Table)
    *   *Category*: `venue` (and `city`)
    *   *Size / Value*: `total_matches`

---

## ⚡ Interactivity & Polish Tips
1. **Edit Interactions**: By default, clicking a visual filters all other visuals. Select a chart, go to **Format > Edit Interactions**, and ensure the season slicer filters everything, but selecting a batter in the Orange Cap list doesn't blank out the Purple Cap chart.
2. **Page Navigation**: Create a left or top sidebar pane containing 4 buttons/icons for navigating pages. Set the button action to **Page Navigation** and bind it to each sheet.
3. **Format tooltips**: Keep tooltips clean, use proper labels (e.g. rename columns in the visual values pane so they show as "Strike Rate" instead of "strike_rate").
