# Al-Mudeer Desktop - Quick Start Guide

## 🚀 Getting Started in 5 Minutes

### Prerequisites Check
Make sure you have:
- ✅ Flutter 3.10.1+ installed
- ✅ Windows: Visual Studio 2019+ with C++ desktop development workload
- ✅ Git (optional, for version control)

### Step 1: Install Dependencies
```bash
cd C:\Projects\almudeer\desktop_app
flutter pub get
```

If this times out, try:
```bash
flutter clean
flutter pub get
```

### Step 2: Run in Development Mode
```bash
flutter run -d windows
```

This will:
- Compile the app
- Open a window with the Al-Mudeer desktop app
- Enable hot reload (press `r` to reload after changes)

### Step 3: Test the Build
Once the app is running, you should see:
- A window titled "Al-Mudeer - المدير"
- A business center icon
- Window size information
- A "Connect to Backend" button

### Step 4: Build for Production

**Option A: Use the build script**
```bash
build.bat
```

**Option B: Manual build**
```bash
flutter build windows --release
```

The built app will be at:
```
build\windows\x64\runner\Release\almudeer_desktop.exe
```

## 🎨 Customization

### Change App Icon
1. Replace `assets\images\logo.png` with your icon
2. Run: `flutter pub run flutter_launcher_icons`
3. Rebuild the app

### Change App Title
Edit `lib\main.dart` and modify:
```dart
title: 'Al-Mudeer - المدير',
```

### Change Window Size
Edit `lib\main.dart` and modify:
```dart
WindowOptions windowOptions = const WindowOptions(
  size: Size(1280, 800),  // Change this
  minimumSize: Size(800, 600),  // And this
  ...
);
```

## 🔌 Next Steps

### 1. Connect to Backend
Update the backend URL in your configuration to point to your Al-Mudeer backend.

### 2. Add Features
Start migrating features from the mobile app:
- Copy needed files from `mobile-app/lib/features`
- Adapt for desktop (remove mobile-specific code)
- Test on desktop

### 3. Add Desktop Features
- **System Tray**: Run in background
- **File Drag & Drop**: Easy file management
- **Keyboard Shortcuts**: Better UX
- **Native File Picker**: Access user files

### 4. Test on Other Platforms
```bash
# Linux (if you have Linux)
flutter run -d linux

# macOS (if you have a Mac)
flutter run -d macos
```

## 🐛 Troubleshooting

### Issue: "flutter pub get" times out
**Solution:**
```bash
flutter clean
flutter pub get
```

### Issue: Build fails with CMake error
**Solution:**
- Install Visual Studio 2019+ 
- Add "Desktop development with C++" workload
- Restart your terminal

### Issue: App window doesn't appear
**Solution:**
```bash
flutter clean
flutter pub get
flutter run -d windows
```

### Issue: Missing plugins
**Solution:**
```bash
flutter clean
flutter pub cache repair
flutter pub get
```

## 📚 Resources

- **Flutter Desktop Docs**: https://docs.flutter.dev/desktop
- **Window Manager**: https://pub.dev/packages/window_manager
- **Al-Mudeer Backend**: `C:\Projects\almudeer\backend`
- **Al-Mudeer Mobile**: `C:\Projects\almudeer\mobile-app`

## 💡 Tips

1. **Hot Reload**: Press `r` in terminal to see changes instantly
2. **Hot Restart**: Press `R` to restart the app
3. **DevTools**: Press `v` to open Flutter DevTools
4. **Performance**: Use `--profile` flag for performance testing
5. **Debugging**: Use `flutter run -d windows --verbose` for detailed logs

## 🎯 Development Workflow

1. Make changes to `lib/main.dart` or other files
2. Press `r` to hot reload
3. Test the changes
4. Repeat until satisfied
5. Build for production
6. Test the built version

## 📞 Need Help?

- Check `PROJECT_STRUCTURE.md` for architecture details
- See `README.md` for general information
- Check Flutter's desktop documentation
- Contact the development team

---

**Happy Coding! 🎉**
