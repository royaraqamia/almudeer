import json
import sys

def convert_tafsir():
    input_file = "assets/json/tafsir_siraj.json"
    output_file = "assets/json/tafsir_mukhtasar.json"
    
    print(f"Loading {input_file}...")
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    quran_data = data.get('quran', [])
    print(f"Loaded {len(quran_data)} verses")
    
    result = {}
    
    for item in quran_data:
        chapter = str(item['chapter'])
        verse = str(item['verse'])
        text = item['text']
        
        if chapter not in result:
            result[chapter] = {}
        
        result[chapter][verse] = text
    
    print(f"Converted {len(result)} surahs")
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    
    print(f"Saved to {output_file}")
    
    import os
    size = os.path.getsize(output_file)
    print(f"File size: {size / 1024:.1f} KB")

if __name__ == "__main__":
    convert_tafsir()
