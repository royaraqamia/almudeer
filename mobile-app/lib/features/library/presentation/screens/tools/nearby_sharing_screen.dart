import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';

import 'package:open_filex/open_filex.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/services/nearby_sharing_service.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';

import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class NearbySharingScreen extends StatefulWidget {
  const NearbySharingScreen({super.key});

  @override
  State<NearbySharingScreen> createState() => _NearbySharingScreenState();
}

class _NearbySharingScreenState extends State<NearbySharingScreen> {
  final NearbySharingService _service = NearbySharingService();
  final Map<String, String> _discoveredEndpoints = {};
  final Map<String, double> _transferProgress = {};
  String? _connectedEndpointId;
  String? _connectedEndpointName;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  final Map<int, Payload> _incomingPayloads = {};

  @override
  void initState() {
    super.initState();
    _initService();
  }

  void _initService() {
    _service.onEndpointFound = (id, name) {
      if (mounted) {
        setState(() {
          _discoveredEndpoints[id] = name;
        });
      }
    };
    _service.onEndpointLost = (id) {
      if (mounted) {
        setState(() {
          _discoveredEndpoints.remove(id);
        });
      }
    };
    _service.onConnectionInitiated = (id, info) {
      if (mounted) {
        _showConnectionDialog(id, info);
      }
    };
    _service.onDisconnected = (id) {
      if (mounted && _connectedEndpointId == id) {
        setState(() {
          _connectedEndpointId = null;
          _connectedEndpointName = null;
        });
        AnimatedToast.error(context, 'طھظ… ظ‚ط·ط¹ ط§ظ„ط§طھطµط§ظ„');
      }
    };
    _service.onPayloadReceived = (id, payload) async {
      if (payload.type == PayloadType.FILE) {
        _incomingPayloads[payload.id] = payload;
        if (mounted) {
          AnimatedToast.success(context, 'ط¨ط¯ط£ ط§ط³طھظ‚ط¨ط§ظ„ ظ…ظ„ظپ...');
        }
      }
    };
    _service.onPayloadTransferUpdate = (id, update) {
      if (mounted) {
        if (update.status == PayloadStatus.IN_PROGRESS) {
          setState(() {
            _transferProgress[update.id.toString()] =
                (update.bytesTransferred / update.totalBytes);
          });
        } else if (update.status == PayloadStatus.SUCCESS) {
          setState(() {
            _transferProgress.remove(update.id.toString());
          });
          AnimatedToast.success(context, 'ط§ظƒطھظ…ظ„ ظ†ظ‚ظ„ ط§ظ„ظ…ظ„ظپ');

          // Open the file if we have the payload info
          if (_incomingPayloads.containsKey(update.id)) {
            final payload = _incomingPayloads[update.id];
            // payload.filePath is deprecated on Android 10+
            final path = payload?.uri;
            if (path != null) {
              OpenFilex.open(path);
            }
            _incomingPayloads.remove(update.id);
          }
        } else if (update.status == PayloadStatus.FAILURE) {
          setState(() {
            _transferProgress.remove(update.id.toString());
            _incomingPayloads.remove(update.id);
          });
          AnimatedToast.error(context, 'ظپط´ظ„ ظ†ظ‚ظ„ ط§ظ„ظ…ظ„ظپ');
        }
      }
    };
  }

  @override
  void dispose() {
    _service.stopAll();
    super.dispose();
  }

  Future<void> _startAdvertising() async {
    if (!mounted) return;
    final userName =
        context.read<AuthProvider>().userInfo?.username ?? 'ظ…ط³طھط®ط¯ظ… ط§ظ„ظ…ط¯ظٹ';
    if (await _service.checkPermissions()) {
      if (!mounted) return;
      final bool success = await _service.startAdvertising(userName);
      if (success && mounted) {
        setState(() {
          _isAdvertising = true;
          _isDiscovering = false;
        });
        AnimatedToast.success(context, 'ظˆط¶ط¹ ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„ ظ†ط´ط·');
      }
    } else {
      final error = await _service.getHardwareErrorMessage();
      if (mounted) {
        AnimatedToast.error(context, error ?? 'ظٹط±ط¬ظ‰ ظ…ظ†ط­ ط§ظ„ط£ط°ظˆظ†ط§طھ ط§ظ„ظ…ط·ظ„ظˆط¨ط©');
      }
    }
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;
    final userName =
        context.read<AuthProvider>().userInfo?.username ?? 'ظ…ط³طھط®ط¯ظ… ط§ظ„ظ…ط¯ظٹ';
    if (await _service.checkPermissions()) {
      if (!mounted) return;
      final bool success = await _service.startDiscovery(userName);
      if (success && mounted) {
        setState(() {
          _isDiscovering = true;
          _isAdvertising = false;
        });
        AnimatedToast.success(context, 'ط¨ط¯ط£ ط§ظ„ط¨ط­ط« ط¹ظ† ط£ط¬ظ‡ط²ط© ظ‚ط±ظٹط¨ط©');
      }
    } else {
      final error = await _service.getHardwareErrorMessage();
      if (mounted) {
        AnimatedToast.error(context, error ?? 'ظٹط±ط¬ظ‰ ظ…ظ†ط­ ط§ظ„ط£ط°ظˆظ†ط§طھ ط§ظ„ظ…ط·ظ„ظˆط¨ط©');
      }
    }
  }

  void _showConnectionDialog(String endpointId, ConnectionInfo info) {
    CustomDialog.show(
      context,
      title: 'ط·ظ„ط¨ ط§طھطµط§ظ„',
      message: 'ظ‡ظ„ طھط±ظٹط¯ ط§ظ„ط§طھطµط§ظ„ ط¨ظ€ ${info.endpointName}طں',
      type: DialogType.confirm,
      confirmText: 'ظ‚ط¨ظˆظ„',
      cancelText: 'ط±ظپط¶',
      onConfirm: () async {
        final bool success = await _service.acceptConnection(endpointId);
        if (success && mounted) {
          setState(() {
            _connectedEndpointId = endpointId;
            _connectedEndpointName = info.endpointName;
          });
        }
      },
      onCancel: () {
        Nearby().rejectConnection(endpointId);
      },
    );
  }

  Future<void> _pickAndSendFiles() async {
    if (_connectedEndpointId == null) return;

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );
    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          await _service.sendFile(_connectedEndpointId!, File(file.path!));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ط§ظ„ظ…ط´ط§ط±ظƒط© ط§ظ„ظ‚ط±ظٹط¨ط©',
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            if (_connectedEndpointId != null)
              _buildConnectedView()
            else if (_isDiscovering)
              _buildDiscoveryView()
            else if (_isAdvertising)
              _buildAdvertisingView()
            else
              _buildInitialView(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    String status = 'ط¬ط§ظ‡ط²';
    IconData icon = SolarLinearIcons.transferHorizontal;
    Color color = AppColors.primary;

    if (_connectedEndpointId != null) {
      status = 'ظ…طھطµظ„ ط¨ظ€ $_connectedEndpointName';
      icon = SolarBoldIcons.checkCircle;
      color = AppColors.success;
    } else if (_isAdvertising) {
      status = 'ظپظٹ ط§ظ†طھط¸ط§ط± ط§ظ„ط§طھطµط§ظ„...';
      icon = SolarLinearIcons.record;
      color = Colors.orange;
    } else if (_isDiscovering) {
      status = 'ظٹطھظ… ط§ظ„ط¨ط­ط«...';
      icon = SolarLinearIcons.magnifer;
      color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.1),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 24,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'IBM Plex Sans Arabic',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialView() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(
          SolarLinearIcons.transmission,
          size: 100,
          color: Theme.of(context).disabledColor,
        ),
        const SizedBox(height: 24),
        Text(
          'ط´ط§ط±ظƒ ط§ظ„ظ…ظ„ظپط§طھ ظ…ط¹ ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ‚ط±ظٹط¨ط© ط¨ط³ط±ط¹ط© ظˆط³ظ‡ظˆظ„ط© ظˆط¨ط¯ظˆظ† ط¥ظ†طھط±ظ†طھ',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 16,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
        const SizedBox(height: 48),
        Row(
          children: [
            Expanded(
              child: AppGradientButton(
                onPressed: _startDiscovery,
                text: 'ط¥ط±ط³ط§ظ„',
                icon: SolarLinearIcons.upload,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppGradientButton(
                onPressed: _startAdvertising,
                text: 'ط§ط³طھظ‚ط¨ط§ظ„',
                icon: SolarLinearIcons.download,
                gradientColors: const [Colors.orange, Colors.deepOrange],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiscoveryView() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ…ظƒطھط´ظپط©:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_discoveredEndpoints.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _discoveredEndpoints.length,
                itemBuilder: (context, index) {
                  final id = _discoveredEndpoints.keys.elementAt(index);
                  final name = _discoveredEndpoints[id]!;
                  return ListTile(
                    title: Text(name),
                    leading: const CircleAvatar(
                      child: Icon(SolarLinearIcons.user),
                    ),
                    trailing: const Icon(SolarLinearIcons.altArrowLeft),
                    onTap: () async {
                      Haptics.mediumTap();
                      final userName =
                          context.read<AuthProvider>().userInfo?.username ??
                          'ظ…ط³طھط®ط¯ظ… ط§ظ„ظ…ط¯ظٹ';
                      await _service.requestConnection(userName, id);
                    },
                  );
                },
              ),
            ),
          AppGradientButton(
            onPressed: () {
              _service.stopAll();
              setState(() => _isDiscovering = false);
            },
            text: 'ط¥ظ„ط؛ط§ط،',
            gradientColors: const [Colors.grey, Colors.blueGrey],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvertisingView() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text('ط¬ظ‡ط§ط²ظƒ ط§ظ„ط¢ظ† ظ…ط±ط¦ظٹ ظ„ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ‚ط±ظٹط¨ط©'),
        const SizedBox(height: 48),
        AppGradientButton(
          onPressed: () {
            _service.stopAll();
            setState(() => _isAdvertising = false);
          },
          text: 'ط¥ظٹظ‚ط§ظپ ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„',
          gradientColors: const [Colors.grey, Colors.blueGrey],
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(SolarBoldIcons.link, size: 80, color: AppColors.success),
        const SizedBox(height: 24),
        Text('ط£ظ†طھ ظ…طھطµظ„ ط§ظ„ط¢ظ† ظ…ط¹ $_connectedEndpointName'),
        const SizedBox(height: 32),
        if (_transferProgress.isNotEmpty)
          ..._transferProgress.entries.map(
            (e) => Column(
              children: [
                LinearProgressIndicator(value: e.value),
                const SizedBox(height: 8),
                Text('ط¬ط§ط±ظٹ ط§ظ„ظ†ظ‚ظ„... ${(e.value * 100).toInt()}%'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        AppGradientButton(
          onPressed: _pickAndSendFiles,
          text: 'ط¥ط±ط³ط§ظ„ ظ…ظ„ظپط§طھ',
          icon: SolarBoldIcons.file,
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _service.stopAll();
            setState(() {
              _connectedEndpointId = null;
              _connectedEndpointName = null;
              _isAdvertising = false;
              _isDiscovering = false;
            });
          },
          child: Text(
            'ظ‚ط·ط¹ ط§ظ„ط§طھطµط§ظ„',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.error
                  : Colors.red,
            ),
          ),
        ),
      ],
    );
  }
}
