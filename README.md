# Al-Mudeer (المدير)

**Al-Mudeer** is a comprehensive B2B communication platform designed for the Syrian and Arab market. It provides a unified solution for managing business communications across multiple channels including email, Telegram, and WhatsApp, with integrated CRM, analytics, and team management capabilities.

## 🌟 Features

### Backend (FastAPI)
- **Unified Inbox**: Manage all communication channels from a single interface
- **CRM Integration**: Customer profiles and relationship management
- **Multi-channel Support**: Email (Gmail OAuth 2.0), Telegram, WhatsApp
- **Analytics & Reporting**: Business intelligence and usage metrics
- **Team Management**: Role-based permissions and team collaboration
- **Smart Notifications**: Real-time alerts via FCM and Web Push (VAPID)
- **License Management**: Secure license key validation with server-side pepper hashing
- **QR Code Generation**: For authentication and sharing
- **Text-to-Speech**: Google Cloud TTS integration for voice messages
- **Delta Updates**: Efficient APK patching using bsdiff (60-80% bandwidth savings)
- **Rate Limiting**: Protection against abuse using SlowAPI
- **Caching**: Redis-backed performance optimization

### Mobile App (Flutter)
- **Cross-Platform**: iOS, Android, and Web support
- **Offline-First**: Local storage with Hive and SQLite
- **Real-time Sync**: WebSocket-based live updates
- **Voice Messages**: Audio recording and playback with proximity sensor
- **Media Sharing**: Images, videos, documents, and QR codes
- **Islamic Content**: Quran, Athkar with reminders, and Hijri calendar
- **Task Management**: Built-in task tracking with alarms
- **Calculator**: Math expressions and calculations
- **Library**: Document and resource management
- **Dark Mode**: Full theme support with Arabic RTL layout
- **Certificate Pinning**: Enhanced security for API communications
- **Background Sync**: Automatic data synchronization

## 🏗️ Architecture

```
almudeer/
├── backend/           # FastAPI Python backend
│   ├── models/       # Database models (SQLAlchemy)
│   ├── routes/       # API endpoints
│   ├── schemas/      # Pydantic schemas
│   ├── services/     # Business logic
│   ├── middleware/   # Security & performance
│   └── tests/        # Test suite
├── mobile-app/       # Flutter mobile application
│   ├── lib/
│   │   ├── core/     # Core services & utilities
│   │   ├── features/ # Feature modules
│   │   ├── data/     # Data layer
│   │   └── presentation/ # UI & state management
│   └── assets/       # App resources
└── .github/          # CI/CD workflows
```

## 🚀 Getting Started

### Prerequisites

- **Python**: 3.11+
- **Flutter**: 3.10.1+
- **PostgreSQL**: 14+
- **Redis**: 7.0+
- **Node.js**: 18+ (for web deployment)

### Backend Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/ayham-alali/almudeer.git
   cd almudeer/backend
   ```

2. **Create virtual environment**:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Generate security keys**:
   ```bash
   # Generate ADMIN_KEY, JWT_SECRET_KEY, DEVICE_SECRET_PEPPER, LICENSE_KEY_PEPPER
   python -c "import secrets; print(secrets.token_hex(32))"
   
   # Generate Fernet encryption key
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
   ```

6. **Run database migrations**:
   ```bash
   alembic upgrade head
   ```

7. **Start the server**:
   ```bash
   # Development
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   
   # Or use Make
   make dev
   ```

### Mobile App Setup

1. **Navigate to mobile app**:
   ```bash
   cd mobile-app
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Configure Firebase** (for push notifications):
   - Add `google-services.json` to `android/app/`
   - Add `GoogleService-Info.plist` to `ios/Runner/`

4. **Run the app**:
   ```bash
   # Android
   flutter run
   
   # iOS
   flutter run -d ios
   
   # Web
   flutter run -d chrome
   ```

## 📦 Deployment

### Railway Deployment

The project is configured for Railway deployment via `railway.toml`:

```toml
[build]
root = "backend"
```

1. Connect your GitHub repository to Railway
2. Set environment variables from `.env.example`
3. Railway will automatically build from the `backend/` folder

### Docker

A `Dockerfile` is included in the backend directory:

```bash
cd backend
docker build -t almudeer-backend .
docker run -p 8000:8000 --env-file .env almudeer-backend
```

## 🧪 Testing

### Backend Tests

```bash
# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest tests/test_api.py

# Run security tests
make test-security
```

### Mobile App Tests

```bash
# Run Flutter tests
flutter test

# Run with coverage
flutter test --coverage
```

## 🛡️ Security

### Key Features

- **License Key Hashing**: Server-side pepper (SHA-256)
- **JWT Authentication**: With device-bound sessions
- **Rate Limiting**: Per-endpoint protection
- **CORS**: Configured for production domains
- **HTTPS Only**: Enforced in production
- **Path Traversal Protection**: Secure file handling
- **File Content Validation**: Magic byte verification
- **Certificate Pinning**: Mobile app API security

### Security Policy

See [SECURITY.md](SECURITY.md) for our security policy and vulnerability reporting process.

## 📝 API Documentation

Once the backend is running, access the interactive API documentation:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Key Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/auth/validate` | POST | Validate license key |
| `/api/inbox/unified` | GET | Retrieve unified inbox messages |
| `/api/customers` | GET/POST | Manage customer profiles |
| `/api/analytics` | GET | Business analytics data |
| `/api/team` | GET/POST | Team management |
| `/api/notifications` | POST | Send notifications |
| `/health` | GET | Health check endpoint |

## 🔧 Development

### Makefile Commands

```bash
make install     # Install dependencies
make dev         # Run development server
make test        # Run tests
make lint        # Run linting
make format      # Format code
make db-migrate  # Create migration
make db-upgrade  # Apply migrations
make clean       # Clean cache files
```

### Code Quality

```bash
# Backend
ruff check .
black .

# Mobile App
flutter analyze
dart format .
```

## 📚 Tech Stack

### Backend
- **Framework**: FastAPI 0.115+
- **Database**: PostgreSQL (asyncpg), SQLite (aiosqlite)
- **ORM**: SQLAlchemy with Alembic migrations
- **Cache**: Redis 5.0+
- **Security**: python-jose, bcrypt, cryptography
- **Validation**: Pydantic 2.5.3
- **Rate Limiting**: SlowAPI
- **Messaging**: Telethon (Telegram), Google Gmail API

### Mobile App
- **Framework**: Flutter 3.10.1+
- **State Management**: Provider
- **Local Storage**: Hive, SQLite, SharedPreferences
- **HTTP**: http, dio
- **Notifications**: Firebase Messaging, flutter_local_notifications
- **Media**: just_audio, video_player, image_picker
- **QR**: mobile_scanner, qr_flutter

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Guidelines

- Follow existing code style and conventions
- Write tests for new features
- Update documentation as needed
- Ensure all tests pass before submitting

## 📄 License

This project is proprietary software. All rights reserved.

## 📞 Support

For support and questions:
- Open an issue on GitHub
- Contact the development team

## 🙏 Acknowledgments

- Built for the Syrian and Arab business community
- Designed with Islamic cultural considerations (Hijri calendar, Quran, Athkar)
- Optimized for low-bandwidth environments

---

**Version**: 1.0.0  
**Last Updated**: March 2026
