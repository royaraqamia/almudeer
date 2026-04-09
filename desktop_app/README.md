# Al-Mudeer Desktop (المدير - نسخة سطح المكتب)

Desktop application for Al-Mudeer B2B communication platform, built with Flutter for Windows, Linux, and macOS.

## Features

- **Cross-Platform**: Native apps for Windows, Linux, and macOS
- **Unified Inbox**: Manage all communication channels
- **CRM Integration**: Customer relationship management
- **Multi-channel Support**: Telegram, WhatsApp
- **Library**: Document and media management
- **Dark Mode**: Full theme support with Arabic RTL layout
- **Offline Support**: Local storage with sync capabilities

## Prerequisites

- **Flutter**: 3.10.1+
- **Windows**: Visual Studio 2019+ with C++ desktop development
- **Linux**: GCC, CMake, GTK3/4 development libraries
- **macOS**: Xcode 14+

## Getting Started

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the app**:
   ```bash
   # Windows
   flutter run -d windows
   
   # Linux
   flutter run -d linux
   
   # macOS
   flutter run -d macos
   ```

3. **Build for release**:
   ```bash
   # Windows
   flutter build windows --release
   
   # Linux
   flutter build linux --release
   
   # macOS
   flutter build macos --release
   ```

## Architecture

The desktop app shares core functionality with the mobile app but uses desktop-specific features:

- **Window Management**: Resizable windows with proper controls
- **System Tray**: Background operation support
- **File System**: Native file picker and drag-and-drop
- **Keyboard Shortcuts**: Desktop-optimized navigation

## Development

### Code Quality
```bash
flutter analyze
dart format .
```

### Testing
```bash
flutter test
```

## Distribution

### Windows
- MSIX package for Microsoft Store
- EXE installer for direct download

### Linux
- Snap package
- AppImage for direct download

### macOS
- DMG installer
- Mac App Store (if needed)

## Backend Connection

The app connects to the Al-Mudeer backend API. Configure the backend URL in your environment or settings.

## License

Proprietary software. All rights reserved.

## Support

For support and questions, open an issue on GitHub or contact the development team.
