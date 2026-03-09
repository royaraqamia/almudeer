import json
import requests
import time
import os

def fetch_full_tafsir():
    # ID 1 is Tafsir Al-Muyassar
    # Endpoint: http://api.quran-tafseer.com/tafseer/1/{surah_number}/{ayah_number}
    
    base_url = "http://api.quran-tafseer.com/tafseer/1"
    full_tafsir = {}
    
    print("Starting download of Tafsir Al-Muyassar (Verse by Verse)...")

    # Surah verse counts (0-indexed for 1-114)
    verse_counts = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
        111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
        54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
        49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52,
        44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19,
        26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
        5, 4, 5, 6
    ]

    for surah_idx, total_ayahs in enumerate(verse_counts):
        surah_num = surah_idx + 1
        print(f"Fetching Surah {surah_num} ({total_ayahs} ayahs)... ", end="", flush=True)
        
        surah_map = {}
        # Try to fetch the WHOLE surah first if API supports it, otherwise fallback
        # API documentation says /tafseer/{tafseer_id}/{sura_number}/{ayah_number} for single
        # But commonly /tafseer/{tafseer_id}/{sura_number} might work for list?
        # My previous attempt failed. Let's try fetching range or just 1 by 1.
        
        # Actually, let's try fetching range 1-{total}
        range_url = f"{base_url}/{surah_num}/1/{total_ayahs}"
        
        try:
            response = requests.get(range_url, timeout=15)
            if response.status_code == 200:
                data = response.json()
                # Data should be a list of ayah objects
                if isinstance(data, list):
                    for item in data:
                        ayah = str(item['aya'])
                        text = item['text']
                        surah_map[ayah] = text
                    print("Done (Range).")
                else:
                    # Single object?
                    print("Unexpected format.")
            else:
                 print(f"Range failed ({response.status_code}), trying 1 by 1...", end="")
                 # Fallback to loop? (Too slow for 6236 verses, but let's see if range works first)
                 pass

        except Exception as e:
            print(f"Error: {e}")
        
        if surah_map:
            full_tafsir[str(surah_num)] = surah_map
        
        # time.sleep(0.1)

    output_path = "assets/json/tafsir_mukhtasar.json"
    
    if len(full_tafsir) > 0:
         with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(full_tafsir, f, ensure_ascii=False, indent=2)
         print(f"Successfully saved {len(full_tafsir)} Surahs to {output_path}")

if __name__ == "__main__":
    fetch_full_tafsir()
