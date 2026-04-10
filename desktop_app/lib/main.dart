import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'المدير',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize services
  final apiClient = ApiClient();
  await apiClient.init();

  final authService = AuthService(apiClient);
  await authService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<AuthService>.value(value: authService),
      ],
      child: const AlmudeerDesktop(),
    ),
  );
}

class AlmudeerDesktop extends StatelessWidget {
  const AlmudeerDesktop({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Al-Mudeer - المدير',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2E42),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'IBM Plex Sans Arabic',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2E42),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'IBM Plex Sans Arabic',
      ),
      themeMode: ThemeMode.system,
      home: const DesktopHomePage(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', ''), // Arabic
        Locale('en', ''), // English
      ],
    );
  }
}

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> with WindowListener {
  String _windowInfo = 'Window ready';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResize() {
    _updateWindowInfo();
    super.onWindowResize();
  }

  void _updateWindowInfo() async {
    final size = await windowManager.getSize();
    setState(() {
      _windowInfo = 'Window size: ${size.width.toInt()}x${size.height.toInt()}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Al-Mudeer'),
            SizedBox(width: 8),
            Text('المدير', style: TextStyle(fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.minimize),
            onPressed: () => windowManager.minimize(),
            tooltip: 'Minimize',
          ),
          IconButton(
            icon: const Icon(Icons.crop_square),
            onPressed: () async {
              final isMaximized = await windowManager.isMaximized();
              if (isMaximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: 'Maximize/Restore',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => windowManager.close(),
            tooltip: 'Close',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.business_center,
              size: 100,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              'Al-Mudeer Desktop',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'المدير - نسخة سطح المكتب',
              style: TextStyle(fontSize: 20, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Text(
              _windowInfo,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
              label: const Text('Backend Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
