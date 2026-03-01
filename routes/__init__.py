"""Al-Mudeer Routes Package"""

from .system_routes import router as system_router
from .email_routes import router as email_router
from .telegram_routes import router as telegram_router
from .chat_routes import router as chat_router
from .features import router as features_router
from .whatsapp import router as whatsapp_router
from .export import router as export_router
from .notifications import router as notifications_router
from .library import router as library_router
from .keyboard import router as keyboard_router
from .auth import router as auth_router

# Subscription router is imported directly in main.py to avoid circular imports
# from .subscription import router as subscription_router

__all__ = [
    'system_router',
    'email_router',
    'telegram_router',
    'chat_router',
    'features_router',
    'whatsapp_router',
    'export_router',
    'notifications_router',
    'library_router',
    'keyboard_router',
    'auth_router'
]

