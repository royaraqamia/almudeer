#!/usr/bin/env python3
"""
Complete Ibn Kathir Tafsir Fetcher
Fetches the complete Ibn Kathir tafsir from multiple reliable sources
with fallback mechanisms
"""
import requests
import json
import re
import time
from pathlib import Path
from typing import Optional, Dict

# Verse counts for each surah (Hafs narration)
VERSE_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 25, 40,
    135, 128, 129, 77, 88, 85, 93, 88, 69, 60,
    85, 30, 86, 54, 45, 83, 182, 176, 110, 77,
    53, 45, 80, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 14, 45, 37, 46, 18, 8, 8,
    11, 11, 68, 12, 12, 30, 52, 52, 44, 28,
    30, 20, 30, 29, 31, 30, 30, 31, 31, 21,
    46, 40, 30, 31, 30, 30, 29, 28, 29, 29,
    30, 29, 30, 29, 30, 29, 30, 29, 30, 8,
    11, 8, 8, 19, 8, 8, 11, 11, 8, 8,
    8, 8, 8, 8
]

def clean_text(text: str) -> str:
    """Remove HTML tags and clean whitespace"""
    if not text:
        return ""
    # Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)
    # Remove extra whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def fetch_from_quran_com(tafsir_id: int = 169) -> Optional[Dict]:
    """
    Fetch from Quran.com API
    Tafsir IDs:
    - 169: Ibn Kathir (Abridged) - Arabic/English
    - 14: Tafsir Ibn Kathir (Full Arabic)
    """
    print(f"Trying Quran.com API (Tafsir ID: {tafsir_id})...")
    
    all_data = {}
    base_url = "https://api.quran.com/api/v4/quran/tafsirs"
    
    try:
        # Fetch by chapter batches
        for surah in range(1, 115):
            verses_count = VERSE_COUNTS[surah - 1]
            surah_data = {}
            
            # Fetch in batches of 50 verses
            for start in range(1, verses_count + 1, 50):
                end = min(start + 49, verses_count)
                verse_keys = ','.join([f"{surah}:{v}" for v in range(start, end + 1)])
                
                try:
                    url = f"{base_url}/{tafsir_id}"
                    params = {'verses': verse_keys}
                    
                    response = requests.get(url, params=params, timeout=15)
                    
                    if response.status_code == 200:
                        data = response.json()
                        tafsirs = data.get('tafsirs', [])
                        
                        for tafsir in tafsirs:
                            verse_key = tafsir.get('verse_key', '')
                            text = tafsir.get('text', '')
                            
                            if verse_key and text:
                                parts = verse_key.split(':')
                                if len(parts) == 2:
                                    verse_num = parts[1]
                                    surah_data[verse_num] = clean_text(text)
                    
                    time.sleep(0.1)  # Rate limiting
                    
                except Exception as e:
                    print(f"  Error fetching batch {start}-{end}: {e}")
                    continue
            
            if surah_data:
                all_data[str(surah)] = surah_data
                print(f"  Surah {surah}: {len(surah_data)} verses")
        
        if all_data:
            return all_data
            
    except Exception as e:
        print(f"Quran.com API error: {e}")
    
    return None

def fetch_from_github_raw() -> Optional[Dict]:
    """Fetch from GitHub raw repositories"""
    print("Trying GitHub sources...")
    
    sources = [
        "https://raw.githubusercontent.com/semarketir/quran-json/master/data/tafsir/ar-ibnkathir.json",
        "https://raw.githubusercontent.com/riswan/quran-json/master/data/tafsir/ar-ibnkathir.json",
    ]
    
    for url in sources:
        try:
            print(f"  Fetching: {url}")
            response = requests.get(url, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                
                # Normalize structure
                normalized = {}
                for surah, verses in data.items():
                    if isinstance(verses, (dict, list)):
                        normalized[surah] = {}
                        if isinstance(verses, dict):
                            for verse, text in verses.items():
                                normalized[surah][verse] = clean_text(str(text))
                        else:
                            for i, item in enumerate(verses):
                                normalized[surah][str(i + 1)] = clean_text(str(item))
                
                if normalized:
                    print(f"  [OK] Got {len(normalized)} surahs")
                    return normalized
                    
        except Exception as e:
            print(f"  Error: {e}")
            continue
    
    return None

def main():
    print("=" * 70)
    print("Ibn Kathir Tafsir - Complete Fetcher")
    print("=" * 70)
    
    tafsir_data = None
    
    # Try multiple sources
    sources = [
        lambda: fetch_from_quran_com(169),
        lambda: fetch_from_quran_com(14),
        lambda: fetch_from_github_raw(),
    ]
    
    for i, fetch_func in enumerate(sources, 1):
        print(f"\n[Source {i}/{len(sources)}]")
        tafsir_data = fetch_func()
        
        if tafsir_data:
            print(f"\n[SUCCESS] Data fetched successfully!")
            break
        else:
            print(f"[FAILED] Moving to next source...")
    
    if not tafsir_data:
        print("\n[ERROR] All sources failed!")
        print("Creating placeholder file...")
        tafsir_data = {
            "1": {
                "1": "تفسير ابن كثير - سيتم تحميل البيانات الكاملة عند توفر الاتصال بالإنترنت",
                "2": "يرجى تشغيل هذا السكربت مرة أخرى عند توفر اتصال إنترنت مستقر"
            },
            "_note": "Run this script again when internet is available to fetch complete tafsir"
        }
    
    # Save to file
    output_path = Path(__file__).parent.parent / "assets" / "json" / "tafsir_ibn_kathir.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(tafsir_data, f, ensure_ascii=False, indent=2)
    
    print("\n" + "=" * 70)
    print(f"[OK] Saved to: {output_path}")
    print(f"[OK] Total surahs: {len(tafsir_data)}")
    
    total_verses = sum(
        len(verses) for key, verses in tafsir_data.items() 
        if not key.startswith('_')
    )
    print(f"[OK] Total verses: {total_verses}")
    print("=" * 70)

if __name__ == "__main__":
    main()
