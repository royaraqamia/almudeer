"""
Verification script for Google Cloud TTS Service.
Uses Service Account authentication.
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

async def test_tts():
    print("=== Google Cloud TTS Verification ===\n")
    
    from services.tts_service import generate_speech, generate_speech_to_file, SERVICE_ACCOUNT_PATH
    
    # Check config
    print(f"Service Account: {SERVICE_ACCOUNT_PATH}")
    print(f"File exists: {os.path.exists(SERVICE_ACCOUNT_PATH)}")
    
    if not os.path.exists(SERVICE_ACCOUNT_PATH):
        print("\n❌ Service account file not found. Cannot test TTS.")
        return False
    
    test_text = "مرحباً! هذا اختبار لخدمة النطق من جوجل."
    
    # Test in-memory generation
    print(f"\n1. Testing in-memory generation...")
    print(f"   Text: '{test_text}'")
    
    try:
        audio_bytes = await generate_speech(test_text)
        
        if audio_bytes and len(audio_bytes) > 0:
            print(f"   ✅ Generated {len(audio_bytes)} bytes of audio")
        else:
            print(f"   ❌ Failed to generate audio bytes (empty response)")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False
    
    # Test file-based generation
    print(f"\n2. Testing file-based generation...")
    
    try:
        audio_path = await generate_speech_to_file(test_text, output_dir="static/audio_test")
        
        if audio_path and os.path.exists(audio_path):
            file_size = os.path.getsize(audio_path)
            print(f"   ✅ Generated file: {audio_path} ({file_size} bytes)")
            
            # Cleanup
            os.remove(audio_path)
            print(f"   ✅ Cleaned up test file")
        else:
            print(f"   ❌ Failed to generate audio file")
            return False
    except Exception as e:
        print(f"   ❌ Error: {e}")
        return False
    
    print("\n=== All TTS Tests Passed ===")
    return True

if __name__ == "__main__":
    success = asyncio.run(test_tts())
    sys.exit(0 if success else 1)
