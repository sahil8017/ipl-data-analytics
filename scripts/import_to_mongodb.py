import os
import json
import glob
from dotenv import load_dotenv
import pymongo
from pymongo import ReplaceOne
from tqdm import tqdm

def main():
    # Load environment variables
    load_dotenv()
    
    mongo_uri = os.getenv("MONGO_URI")
    db_name = os.getenv("MONGO_DB_NAME", "ipl")
    collection_name = os.getenv("MONGO_COLLECTION", "raw_matches")
    
    if not mongo_uri:
        print("Error: MONGO_URI is not set in .env file.")
        return
        
    print(f"Connecting to MongoDB Atlas...")
    client = pymongo.MongoClient(mongo_uri)
    db = client[db_name]
    collection = db[collection_name]
    
    # Locate raw data files
    raw_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "raw")
    json_pattern = os.path.join(raw_dir, "*.json")
    json_files = glob.glob(json_pattern)
    
    if not json_files:
        print(f"Error: No JSON files found in {raw_dir}")
        return
        
    print(f"Found {len(json_files)} JSON files in {raw_dir}")
    print(f"Ingesting raw matches into MongoDB collection '{db_name}.{collection_name}'...")
    
    operations = []
    batch_size = 100
    total_inserted = 0
    
    for file_path in tqdm(json_files, desc="Parsing JSON files"):
        try:
            # Extract match ID from filename
            file_name = os.path.basename(file_path)
            match_id_str = os.path.splitext(file_name)[0]
            match_id = int(match_id_str)
            
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                
            # Set the _id to match_id for natural uniqueness
            data["_id"] = match_id
            data["match_id"] = match_id
            
            # Prepare replace operation (upsert)
            operations.append(
                ReplaceOne({"_id": match_id}, data, upsert=True)
            )
            
            # Execute in batches
            if len(operations) >= batch_size:
                result = collection.bulk_write(operations, ordered=False)
                total_inserted += result.upserted_count + result.modified_count + result.matched_count
                operations = []
                
        except Exception as e:
            print(f"Error parsing file {file_path}: {e}")
            
    # Write remaining operations
    if operations:
        result = collection.bulk_write(operations, ordered=False)
        total_inserted += result.upserted_count + result.modified_count + result.matched_count
        
    print(f"\nIngestion completed!")
    print(f"Total processed/upserted documents in MongoDB: {total_inserted}")
    
    # Print total documents currently in collection
    current_count = collection.count_documents({})
    print(f"Total documents in '{db_name}.{collection_name}': {current_count}")

if __name__ == "__main__":
    main()
