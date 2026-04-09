import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _licenseKeyController = TextEditingController();

  bool _isConnecting = false;
  bool _isHealthChecking = false;
  String? _connectionStatus;
  Color? _connectionStatusColor;

  late ApiClient _apiClient;
  late AuthService _authService;

  @override
  void initState() {
    super.initState();
    _apiClient = context.read<ApiClient>();
    _authService = context.read<AuthService>();
    _urlController.text = _apiClient.baseUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _licenseKeyController.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isHealthChecking = true;
      _connectionStatus = null;
    });

    final healthy = await _apiClient.checkHealth();

    setState(() {
      _isHealthChecking = false;
      _connectionStatus = healthy ? 'Backend is reachable' : 'Cannot reach backend';
      _connectionStatusColor = healthy ? Colors.green : Colors.red;
    });
  }

  Future<void> _saveUrlAndCheck() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isConnecting = true;
      _connectionStatus = null;
    });

    await _apiClient.setBaseUrl(url);
    final healthy = await _apiClient.checkHealth();

    // Try to get version info
    String statusMsg;
    if (healthy) {
      final version = await _apiClient.getVersion();
      statusMsg = 'Connected!';
      if (version != null) {
        final ver = version['version'] ?? version['api_version'] ?? '';
        if (ver.toString().isNotEmpty) {
          statusMsg += ' (API v$ver)';
        }
      }
    } else {
      statusMsg = 'Cannot reach backend at $url';
    }

    setState(() {
      _isConnecting = false;
      _connectionStatus = statusMsg;
      _connectionStatusColor = healthy ? Colors.green : Colors.red;
    });
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final licenseKey = _licenseKeyController.text.trim();

    if (username.isEmpty || password.isEmpty) return;

    setState(() => _isConnecting = true);

    final success = await _authService.login(
      username: username,
      password: password,
      licenseKey: licenseKey.isEmpty ? null : licenseKey,
    );

    setState(() {
      _isConnecting = false;
      if (success) {
        _connectionStatus = 'Logged in as $username';
        _connectionStatusColor = Colors.green;
      } else {
        _connectionStatus = 'Login failed. Check credentials.';
        _connectionStatusColor = Colors.red;
      }
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully connected to backend!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    _usernameController.clear();
    _passwordController.clear();
    _licenseKeyController.clear();
    setState(() {
      _connectionStatus = 'Logged out';
      _connectionStatusColor = Colors.grey;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Backend URL Configuration
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Backend Server',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'Backend URL',
                            hintText: 'http://localhost:8000',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isConnecting
                                    ? null
                                    : _saveUrlAndCheck,
                                icon: _isConnecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check),
                                label: Text(_isConnecting ? 'Connecting...' : 'Save & Test'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _isHealthChecking ? null : _checkHealth,
                              icon: _isHealthChecking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.monitor_heart),
                              label: const Text('Ping'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Authentication
                if (!_authService.isAuthenticated)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock, size: 28),
                              const SizedBox(width: 12),
                              const Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.vpn_key),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _licenseKeyController,
                            decoration: const InputDecoration(
                              labelText: 'License Key (optional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.key),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isConnecting ? null : _login,
                              icon: _isConnecting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(_isConnecting ? 'Connecting...' : 'Login'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, size: 28, color: Colors.green),
                              const SizedBox(width: 12),
                              const Text(
                                'Connected',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_authService.userProfile != null)
                            Text(
                              'User: ${_authService.userProfile!['username'] ?? 'Unknown'}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _logout,
                              icon: const Icon(Icons.logout),
                              label: const Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Connection Status
                if (_connectionStatus != null)
                  Card(
                    color: _connectionStatusColor?.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _connectionStatusColor == Colors.green
                                ? Icons.check_circle
                                : _connectionStatusColor == Colors.red
                                    ? Icons.error
                                    : Icons.info,
                            color: _connectionStatusColor,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _connectionStatus!,
                              style: TextStyle(
                                fontSize: 16,
                                color: _connectionStatusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
