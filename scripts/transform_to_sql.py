import os
import sys
from dotenv import load_dotenv
import pymongo
import psycopg2
from psycopg2.extras import execute_values
from tqdm import tqdm

# Mapping for normalizing team names (handling rebrands and format inconsistencies)
TEAM_NAME_MAPPING = {
    "Kings XI Punjab": "Punjab Kings",
    "Delhi Daredevils": "Delhi Capitals",
    "Rising Pune Supergiants": "Rising Pune Supergiant",
    "Royal Challengers Bangalore": "Royal Challengers Bengaluru"
}

def normalize_team(team_name):
    if not team_name:
        return None
    return TEAM_NAME_MAPPING.get(team_name, team_name)

def setup_database():
    load_dotenv()
    
    db_host = os.getenv("DB_HOST", "localhost")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME", "ipl_db")
    db_user = os.getenv("DB_USER", "postgres")
    db_password = os.getenv("DB_PASSWORD")
    
    print("Connecting to PostgreSQL to check database existence...")
    # Connect to default postgres DB first to create the database if it doesn't exist
    conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        database="postgres",
        user=db_user,
        password=db_password
    )
    conn.autocommit = True
    cur = conn.cursor()
    
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s;", (db_name,))
    exists = cur.fetchone()
    
    if not exists:
        print(f"Creating database '{db_name}'...")
        cur.execute(f"CREATE DATABASE {db_name};")
    else:
        print(f"Database '{db_name}' already exists.")
        
    cur.close()
    conn.close()
    
    # Connect to the target database to establish the schema
    conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        database=db_name,
        user=db_user,
        password=db_password
    )
    conn.autocommit = True
    cur = conn.cursor()
    
    # Drop existing tables to start with a clean slate
    print("Creating tables (dropping old ones if exist)...")
    cur.execute("DROP TABLE IF EXISTS deliveries CASCADE;")
    cur.execute("DROP TABLE IF EXISTS matches CASCADE;")
    
    # Create matches table
    cur.execute("""
        CREATE TABLE matches (
            match_id INT PRIMARY KEY,
            season VARCHAR(20),
            date DATE,
            team1 VARCHAR(100),
            team2 VARCHAR(100),
            toss_winner VARCHAR(100),
            toss_decision VARCHAR(20),
            winner VARCHAR(100),
            result VARCHAR(50),
            result_margin INT,
            player_of_match VARCHAR(100),
            venue VARCHAR(200),
            city VARCHAR(100),
            match_number INT,
            stage VARCHAR(50)
        );
    """)
    
    # Create deliveries table
    cur.execute("""
        CREATE TABLE deliveries (
            delivery_id SERIAL PRIMARY KEY,
            match_id INT REFERENCES matches(match_id) ON DELETE CASCADE,
            inning INT,
            batting_team VARCHAR(100),
            bowling_team VARCHAR(100),
            over INT,
            ball INT,
            batter VARCHAR(100),
            bowler VARCHAR(100),
            non_striker VARCHAR(100),
            batsman_runs INT,
            extra_runs INT,
            total_runs INT,
            is_wicket INT,
            dismissal_kind VARCHAR(50),
            player_dismissed VARCHAR(100),
            fielder VARCHAR(100),
            extra_type VARCHAR(50)
        );
    """)
    
    print("Schema created successfully!")
    cur.close()
    conn.close()

def run_etl():
    load_dotenv()
    
    mongo_uri = os.getenv("MONGO_URI")
    mongo_db_name = os.getenv("MONGO_DB_NAME", "ipl")
    mongo_coll_name = os.getenv("MONGO_COLLECTION", "raw_matches")
    
    db_host = os.getenv("DB_HOST", "localhost")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME", "ipl_db")
    db_user = os.getenv("DB_USER", "postgres")
    db_password = os.getenv("DB_PASSWORD")
    
    print("Fetching raw data from MongoDB Atlas...")
    mongo_client = pymongo.MongoClient(mongo_uri)
    mongo_db = mongo_client[mongo_db_name]
    collection = mongo_db[mongo_coll_name]
    
    raw_matches = list(collection.find({}))
    print(f"Retrieved {len(raw_matches)} raw match documents.")
    
    postgres_conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        database=db_name,
        user=db_user,
        password=db_password
    )
    postgres_conn.autocommit = False  # Use transactions for bulk writes
    cur = postgres_conn.cursor()
    
    match_records = []
    delivery_records = []
    
    for doc in tqdm(raw_matches, desc="Transforming data"):
        match_id = doc["match_id"]
        info = doc.get("info", {})
        
        # 1. Extract and clean match details
        dates = info.get("dates", [])
        date_str = dates[0] if dates else None
        
        # Normalize season to a consistent 4-digit calendar year from the match date
        if date_str:
            season = date_str.split("-")[0]
        else:
            season = info.get("season")
        
        teams = info.get("teams", [])
        team1 = normalize_team(teams[0] if len(teams) > 0 else None)
        team2 = normalize_team(teams[1] if len(teams) > 1 else None)
        
        toss = info.get("toss", {})
        toss_winner = normalize_team(toss.get("winner"))
        toss_decision = toss.get("decision")
        
        outcome = info.get("outcome", {})
        winner = normalize_team(outcome.get("winner"))
        
        # Determine outcome type and margin
        result = "normal" if winner else "no result"
        result_margin = None
        
        by_info = outcome.get("by", {})
        if "runs" in by_info:
            result = "runs"
            result_margin = by_info["runs"]
        elif "wickets" in by_info:
            result = "wickets"
            result_margin = by_info["wickets"]
        elif "result" in outcome:
            result = outcome["result"]  # e.g., tie, no result
            
        player_of_match = info.get("player_of_match", [None])[0]
        venue = info.get("venue")
        city = info.get("city")
        
        # Fallback city calculation from venue if missing
        if not city and venue:
            # Common venue-city mapping
            if "M Chinnaswamy" in venue or "Chinnaswamy" in venue:
                city = "Bangalore"
            elif "Wankhede" in venue:
                city = "Mumbai"
            elif "Eden Gardens" in venue:
                city = "Kolkata"
            elif "Feroz Shah Kotla" in venue or "Arun Jaitley" in venue:
                city = "Delhi"
            elif "Chidambaram" in venue or "Chepauk" in venue:
                city = "Chennai"
            elif "Rajiv Gandhi" in venue:
                city = "Hyderabad"
            elif "Punjab Cricket Association" in venue or "IS Bindra" in venue:
                city = "Chandigarh"
            else:
                city = "Unknown"
                
        # Extract match_number and stage
        event = info.get("event", {})
        match_number = event.get("match_number")
        if match_number is not None:
            try:
                match_number = int(match_number)
            except ValueError:
                match_number = None
        stage = event.get("stage")

        match_records.append((
            match_id, season, date_str, team1, team2,
            toss_winner, toss_decision, winner, result,
            result_margin, player_of_match, venue, city,
            match_number, stage
        ))
        
        # 2. Extract and clean delivery details
        innings = doc.get("innings", [])
        for inn_idx, inning in enumerate(innings):
            batting_team = normalize_team(inning.get("team"))
            bowling_team = team2 if batting_team == team1 else team1
            
            overs = inning.get("overs", [])
            for over_dict in overs:
                over_num = over_dict.get("over")
                deliveries = over_dict.get("deliveries", [])
                
                for ball_idx, delivery in enumerate(deliveries):
                    ball_num = ball_idx + 1
                    
                    batter = delivery.get("batter")
                    bowler = delivery.get("bowler")
                    non_striker = delivery.get("non_striker")
                    
                    runs_dict = delivery.get("runs", {})
                    batsman_runs = runs_dict.get("batter", 0)
                    extra_runs = runs_dict.get("extras", 0)
                    total_runs = runs_dict.get("total", 0)
                    
                    # Extras details
                    extras = delivery.get("extras", {})
                    extra_type = list(extras.keys())[0] if extras else None
                    
                    # Wickets details
                    wickets = delivery.get("wickets", [])
                    is_wicket = 1 if wickets else 0
                    
                    dismissal_kind = None
                    player_dismissed = None
                    fielder_name = None
                    
                    if wickets:
                        w = wickets[0]
                        dismissal_kind = w.get("kind")
                        player_dismissed = w.get("player_out")
                        
                        fielders = w.get("fielders", [])
                        if fielders:
                            # Concat multiple fielders if run out or multi-fielder catches
                            fielder_name = ", ".join([f.get("name") for f in fielders if f.get("name")])
                            
                    delivery_records.append((
                        match_id, inn_idx + 1, batting_team, bowling_team,
                        over_num, ball_num, batter, bowler, non_striker,
                        batsman_runs, extra_runs, total_runs, is_wicket,
                        dismissal_kind, player_dismissed, fielder_name, extra_type
                    ))

    print(f"Loading {len(match_records)} matches into PostgreSQL matches table...")
    insert_matches_query = """
        INSERT INTO matches (
            match_id, season, date, team1, team2,
            toss_winner, toss_decision, winner, result,
            result_margin, player_of_match, venue, city,
            match_number, stage
        ) VALUES %s;
    """
    execute_values(cur, insert_matches_query, match_records)
    
    print(f"Loading {len(delivery_records)} deliveries into PostgreSQL deliveries table...")
    insert_deliveries_query = """
        INSERT INTO deliveries (
            match_id, inning, batting_team, bowling_team,
            over, ball, batter, bowler, non_striker,
            batsman_runs, extra_runs, total_runs, is_wicket,
            dismissal_kind, player_dismissed, fielder, extra_type
        ) VALUES %s;
    """
    # Using batches for executing values to avoid huge memory/query buffer issues
    batch_size = 50000
    for i in range(0, len(delivery_records), batch_size):
        batch = delivery_records[i:i+batch_size]
        execute_values(cur, insert_deliveries_query, batch)
        
    print("Committing transaction...")
    postgres_conn.commit()
    
    # Verify counts
    cur.execute("SELECT COUNT(*) FROM matches;")
    m_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM deliveries;")
    d_count = cur.fetchone()[0]
    
    print("\nETL Pipeline completed successfully!")
    print(f"  PostgreSQL matches table count: {m_count}")
    print(f"  PostgreSQL deliveries table count: {d_count}")
    
    cur.close()
    postgres_conn.close()

if __name__ == "__main__":
    setup_database()
    print("-" * 50)
    run_etl()
