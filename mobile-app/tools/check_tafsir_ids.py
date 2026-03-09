#!/usr/bin/env python3
import requests
import json

# Get all Arabic tafsirs
r = requests.get('https://api.quran.com/api/v4/resources/tafsirs?language=ar')
data = r.json()

print("Available Arabic Tafsirs:")
print("=" * 60)

for tafsir in data.get('tafsirs', []):
    tafsir_name = tafsir.get('name', 'Unknown')
    author = tafsir.get('author_name', 'Unknown')
    tafsir_id = tafsir.get('id', 'Unknown')
    
    print(f"ID: {tafsir_id}")
    print(f"  Name: {tafsir_name}")
    print(f"  Author: {author}")
    print()

# Also test fetching Ibn Kathir (ID 169)
print("\n" + "=" * 60)
print("Testing Ibn Kathir (ID: 169) for Surah 1:")
r2 = requests.get('https://api.quran.com/api/v4/quran/tafsirs/169?chapter_id=1')
data2 = r2.json()
print(f"Status: {r2.status_code}")
print(f"Response: {json.dumps(data2, indent=2, ensure_ascii=False)[:1000]}")
