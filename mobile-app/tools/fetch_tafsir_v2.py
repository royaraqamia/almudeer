import json
import requests
import time
import os

def fetch_full_tafsir():
    base_url = "https://api.quran-tafseer.com/tafseer/1"
    full_tafsir = {}
    
    verse_counts = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
        111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
        54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
        49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52,
        44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19,
        26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
        5, 4, 5, 6
    ]
    
    print("Fetching Tafsir Al-Muyassar (Arabic) for all 114 surahs...")
    
    for surah_idx, total_ayahs in enumerate(verse_counts):
        surah_num = surah_idx + 1
        print(f"Surah {surah_num}/{114} ({total_ayahs} verses)... ", end="", flush=True)
        
        surah_map = {}
        
        for ayah in range(1, total_ayahs + 1):
            try:
                url = f"{base_url}/{surah_num}/{ayah}"
                response = requests.get(url, timeout=10)
                
                if response.status_code == 200:
                    data = response.json()
                    if 'text' in data:
                        surah_map[str(ayah)] = data['text']
                
                time.sleep(0.05)
                
            except Exception as e:
                print(f"\nError at Surah {surah_num}, Ayah {ayah}: {e}")
                continue
        
        if surah_map:
            full_tafsir[str(surah_num)] = surah_map
            print(f"Done ({len(surah_map)} verses)")
        else:
            print("Failed")
        
        time.sleep(0.2)
    
    output_path = "assets/json/tafsir_mukhtasar.json"
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(full_tafsir, f, ensure_ascii=False, indent=2)
    
    print(f"\nComplete! Saved {len(full_tafsir)} surahs to {output_path}")

if __name__ == "__main__":
    fetch_full_tafsir()
