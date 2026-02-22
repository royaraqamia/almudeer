import secrets
import os
from pathlib import Path

def generate_secrets():
    """Generate JWT_SECRET_KEY and ENCRYPTION_KEY if they don't exist in .env"""
    env_path = Path(".env")
    
    # Ensure .env exists
    if not env_path.exists():
        if Path(".env.example").exists():
            import shutil
            shutil.copy(".env.example", ".env")
            print("Created .env from .env.example")
        else:
            env_path.touch()
            print("Created empty .env file")
            
    with open(env_path, "r") as f:
        content = f.read()
        
    updates = []
    
    if "JWT_SECRET_KEY=" not in content:
        secret = secrets.token_hex(32)
        updates.append(f"\nJWT_SECRET_KEY={secret}")
        print(f"Generated new JWT_SECRET_KEY")
        
    if "ENCRYPTION_KEY=" not in content:
        # Fernet key is 32 bytes base64 encoded
        import base64
        key = base64.urlsafe_b64encode(os.urandom(32)).decode()
        updates.append(f"\nENCRYPTION_KEY={key}")
        print(f"Generated new ENCRYPTION_KEY")
        
    if updates:
        with open(env_path, "a") as f:
            for update in updates:
                f.write(update)
        print(f"Updated {env_path} with new security keys.")
    else:
        print("Security keys already present in .env. No changes made.")

if __name__ == "__main__":
    generate_secrets()
