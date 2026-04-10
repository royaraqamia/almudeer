#!/usr/bin/env python3
"""
Fetch Ibn Kathir tafsir from GitHub raw source
Using the reliable Islamic database repositories
"""
import requests
import json
import re
from pathlib import Path

def fetch_ibn_kathir_from_github():
    """
    Fetch Ibn Kathir tafsir from GitHub raw content
    Source: https://github.com/semarketir/quran-json
    """
    
    print("Fetching Ibn Kathir tafsir from GitHub...")
    
    # Try multiple sources
    sources = [
        # Source 1: Quran JSON repository
        "https://raw.githubusercontent.com/semarketir/quran-json/master/data/tafsir/ar-ibnkathir.json",
        # Source 2: Another repository
        "https://raw.githubusercontent.com/fawazahmed0/quran-api/master/src/data/tafsirs/ibn-kathir.json",
    ]
    
    for url in sources:
        print(f"\nTrying: {url}")
        
        try:
            response = requests.get(url, timeout=30)
            
            if response.status_code == 200:
                print(f"[OK] Downloaded from {url}")
                
                data = response.json()
                
                # Check the structure and normalize it
                if isinstance(data, dict):
                    # Check if it's already in the format we need {surah: {verse: text}}
                    normalized = {}
                    for surah, verses in data.items():
                        if isinstance(verses, dict):
                            normalized[surah] = {}
                            for verse, text in verses.items():
                                if isinstance(text, str):
                                    # Clean HTML tags if any
                                    clean_text = re.sub(r'<[^>]+>', '', text).strip()
                                    normalized[surah][verse] = clean_text
                                elif isinstance(text, dict) and 'text' in text:
                                    clean_text = re.sub(r'<[^>]+>', '', text['text']).strip()
                                    normalized[surah][verse] = clean_text
                    
                    if normalized:
                        print(f"[OK] Normalized: {len(normalized)} surahs")
                        return normalized
                
                return data
                
        except Exception as e:
            print(f"[!] Error: {e}")
            continue
    
    return None

def main():
    print("=" * 60)
    print("Ibn Kathir Tafsir Fetcher (GitHub)")
    print("=" * 60)
    
    tafsir_data = fetch_ibn_kathir_from_github()
    
    if not tafsir_data:
        print("\n[ERROR] Could not fetch from GitHub sources")
        print("Keeping existing tafsir_mukhtasar.json as fallback")
        return
    
    # Save to file
    output_path = Path(__file__).parent.parent / "assets" / "json" / "tafsir_ibn_kathir.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(tafsir_data, f, ensure_ascii=False, indent=2)
    
    print("=" * 60)
    print(f"[OK] Saved to: {output_path}")
    print(f"[OK] Total surahs: {len(tafsir_data)}")
    
    total_verses = sum(len(verses) for verses in tafsir_data.values())
    print(f"[OK] Total verses: {total_verses}")

if __name__ == "__main__":
    main()
