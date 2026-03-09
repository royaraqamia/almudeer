"""
Text-to-Speech Service using Google Cloud Text-to-Speech.
Uses Service Account authentication (same as other Google Cloud services).
"""
import os
import logging

logger = logging.getLogger(__name__)

# Arabic WaveNet Voices (high quality):
# ar-XA-Wavenet-A (Female), ar-XA-Wavenet-B (Male), ar-XA-Wavenet-C (Male), ar-XA-Wavenet-D (Female)
DEFAULT_VOICE = "ar-XA-Wavenet-B"  # Male, natural sounding
DEFAULT_LANGUAGE = "ar-XA"

# Path to service account JSON (same as used for other Google services)
SERVICE_ACCOUNT_PATH = os.environ.get(
    "GOOGLE_APPLICATION_CREDENTIALS", 
    os.path.join(os.path.dirname(__file__), "..", "service_account.json")
)


async def generate_speech(text: str) -> bytes:
    """
    Generates audio from text using Google Cloud Text-to-Speech.
    Uses Service Account authentication.
    Returns raw audio bytes (MP3 format) for direct streaming.
    """
    import httpx
    import json
    import time
    import jwt
    
    if not os.path.exists(SERVICE_ACCOUNT_PATH):
        logger.error(f"Service account file not found: {SERVICE_ACCOUNT_PATH}")
        return b""
    
    try:
        # Load service account credentials
        with open(SERVICE_ACCOUNT_PATH) as f:
            creds = json.load(f)
        
        # Create JWT token for authentication
        now = int(time.time())
        payload = {
            "iss": creds["client_email"],
            "sub": creds["client_email"],
            "aud": "https://texttospeech.googleapis.com/",
            "iat": now,
            "exp": now + 3600,  # 1 hour expiry
        }
        
        # Sign the JWT with the private key
        token = jwt.encode(payload, creds["private_key"], algorithm="RS256")
        
        # Call TTS API
        url = "https://texttospeech.googleapis.com/v1/text:synthesize"
        
        request_body = {
            "input": {"text": text},
            "voice": {
                "languageCode": DEFAULT_LANGUAGE,
                "name": DEFAULT_VOICE,
            },
            "audioConfig": {
                "audioEncoding": "MP3",
                "speakingRate": 1.0,
                "pitch": 0.0,
            }
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                url,
                json=request_body,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                }
            )
            
            if response.status_code == 200:
                data = response.json()
                import base64
                audio_content = base64.b64decode(data["audioContent"])
                logger.info(f"Google TTS generated {len(audio_content)} bytes")
                return audio_content
            else:
                logger.error(f"Google TTS API error: {response.status_code} - {response.text}")
                return b""
                
    except Exception as e:
        logger.error(f"Google TTS exception: {e}")
        return b""


async def generate_speech_to_file(text: str, output_dir: str = "static/audio") -> str:
    """
    Generates audio and saves to file.
    Returns file path for WhatsApp media upload compatibility.
    """
    import uuid
    
    audio_bytes = await generate_speech(text)
    
    if not audio_bytes:
        return ""
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)
    
    filename = f"{uuid.uuid4()}.mp3"
    output_path = os.path.join(output_dir, filename)
    
    with open(output_path, "wb") as f:
        f.write(audio_bytes)
    
    logger.info(f"Saved TTS audio to {output_path}")
    return output_path
