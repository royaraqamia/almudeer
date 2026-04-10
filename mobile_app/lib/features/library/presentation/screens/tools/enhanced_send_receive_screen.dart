import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/transfer/data/models/transfer_models.dart';
import 'package:almudeer_mobile_app/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';

/// Enhanced Send & Receive screen with production-grade reliability
class EnhancedSendReceiveScreen extends StatefulWidget {
  const EnhancedSendReceiveScreen({super.key});

  @override
  State<EnhancedSendReceiveScreen> createState() =>
      _EnhancedSendReceiveScreenState();
}

class _EnhancedSendReceiveScreenState extends State<EnhancedSendReceiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeProvider();
  }

  Future<void> _initializeProvider() async {
    final provider = context.read<TransferProvider>();
    await provider.initialize();

    if (mounted) {
      setState(() => _isInitialized = true);

      // Listen for incoming connection requests
      provider.connectionRequestStream.listen((request) {
        if (mounted) {
          _showConnectionRequestDialog(context, request);
        }
      });

      // Listen for transfer completion/failure for haptics
      provider.onTransferCompleted = (session) {
        Haptics.heavyTap(); // Corrected from successVibration
        if (mounted) {
          AnimatedToast.success(
            context,
            'طھظ… ط§ط³طھظ„ط§ظ… ${session.metadata.fileName}',
          );
        }
      };

      provider.onTransferFailed = (session) {
        Haptics.vibrate(); // Corrected from errorVibration
        if (mounted) {
          AnimatedToast.error(context, 'ظپط´ظ„ ظ†ظ‚ظ„ ${session.metadata.fileName}');
        }
      };
    }
  }

  void _showConnectionRequestDialog(
    BuildContext context,
    PendingConnectionRequest request,
  ) {
    Haptics.mediumTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ConnectionRequestSheet(request: request),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          'ط¥ط±ط³ط§ظ„ ظˆط§ط³طھظ‚ط¨ط§ظ„',
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: theme.hintColor,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
          tabs: const [
            Tab(text: 'ط§ظ„ط£ط¬ظ‡ط²ط©', icon: Icon(SolarLinearIcons.smartphone)),
            Tab(text: 'ط§ظ„ظ†ظ‚ظ„', icon: Icon(SolarLinearIcons.transferHorizontal)),
            Tab(text: 'ط§ظ„ط³ط¬ظ„', icon: Icon(SolarLinearIcons.clockCircle)),
          ],
        ),
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: const [_DevicesTab(), _TransfersTab(), _HistoryTab()],
            ),
    );
  }
}

class _ConnectionRequestSheet extends StatelessWidget {
  final PendingConnectionRequest request;

  const _ConnectionRequestSheet({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              SolarBoldIcons.smartphone,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ط·ظ„ط¨ ط§طھطµط§ظ„ ظˆط§ط±ط¯',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'IBM Plex Sans Arabic',
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ظٹط±ط؛ط¨ "${request.deviceName}" ظپظٹ ط§ظ„ط§طھطµط§ظ„ ط¨ظƒ ظ„ظ…ط´ط§ط±ظƒط© ط§ظ„ظ…ظ„ظپط§طھ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontFamily: 'IBM Plex Sans Arabic',
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context.read<TransferProvider>().rejectPendingConnection();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ط±ظپط¶',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'IBM Plex Sans Arabic',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    context.read<TransferProvider>().acceptPendingConnection();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ظ‚ط¨ظˆظ„',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'IBM Plex Sans Arabic',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Devices Tab - Discovery and Connection
class _DevicesTab extends StatelessWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransferProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            // Status Card
            _buildStatusCard(context, provider),

            // Action Buttons
            _buildActionButtons(context, provider),

            // Error & Requirements Banners
            if (provider.hasMissingRequirements)
              _buildRequirementsBanner(context, provider)
            else if (provider.hasError)
              _buildErrorBanner(context, provider),

            // Devices List
            Expanded(child: _buildDevicesList(context, provider)),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(BuildContext context, TransferProvider provider) {
    String status = 'ط¬ط§ظ‡ط²';
    IconData icon = SolarLinearIcons.transferHorizontal;
    Color color = Colors.grey;
    String subtitle = 'ط§ط®طھط± ظˆط¶ط¹ ط§ظ„ط¥ط±ط³ط§ظ„ ط£ظˆ ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„';

    if (provider.isScanning) {
      status = 'ط¬ط§ط±ظٹ ط§ظ„ط¨ط­ط«...';
      icon = SolarLinearIcons.magnifer;
      color = AppColors.primary;
      subtitle = 'ظٹط¨ط­ط« ط¹ظ† ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ‚ط±ظٹط¨ط©';
    } else if (provider.isAdvertising) {
      status = 'ظˆط¶ط¹ ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„';
      icon = SolarLinearIcons.download;
      color = Colors.orange;
      subtitle = 'ط¬ظ‡ط§ط²ظƒ ظ…ط±ط¦ظٹ ظ„ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ‚ط±ظٹط¨ط©';
    } else if (provider.selectedDevice != null) {
      status = 'ظ…طھطµظ„';
      icon = SolarBoldIcons.checkCircle;
      color = AppColors.success;
      subtitle = 'ظ…طھطµظ„ ط¨ظ€ ${provider.selectedDevice!.deviceName}';
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'IBM Plex Sans Arabic',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontFamily: 'IBM Plex Sans Arabic',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, TransferProvider provider) {
    final userName =
        context.read<AuthProvider>().userInfo?.username ?? 'ظ…ط³طھط®ط¯ظ… ط§ظ„ظ…ط¯ظٹ';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: SolarLinearIcons.upload,
              label: 'ط¥ط±ط³ط§ظ„',
              color: AppColors.primary,
              isActive: provider.isScanning,
              isLoading:
                  provider.isProcessing &&
                  provider.isScanning == false &&
                  provider.isAdvertising == false &&
                  provider.errorMessage == null,
              onTap: provider.isProcessing
                  ? null
                  : () async {
                      Haptics.mediumTap();
                      if (provider.isScanning) {
                        await provider.stopScanning();
                      } else {
                        final success = await provider.startScanning(userName);
                        if (!success &&
                            !provider.hasMissingRequirements &&
                            context.mounted) {
                          AnimatedToast.error(
                            context,
                            provider.errorMessage ?? 'ظپط´ظ„ ط¨ط¯ط، ط§ظ„ط¨ط­ط«',
                          );
                        }
                      }
                    },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: SolarLinearIcons.download,
              label: 'ط§ط³طھظ‚ط¨ط§ظ„',
              color: Colors.orange,
              isActive: provider.isAdvertising,
              isLoading:
                  provider.isProcessing &&
                  provider.isScanning == false &&
                  provider.isAdvertising == false &&
                  provider.errorMessage == null,
              onTap: provider.isProcessing
                  ? null
                  : () async {
                      Haptics.mediumTap();
                      if (provider.isAdvertising) {
                        await provider.stopAdvertising();
                      } else {
                        final success = await provider.startAdvertising(
                          userName,
                        );
                        if (!success &&
                            !provider.hasMissingRequirements &&
                            context.mounted) {
                          AnimatedToast.error(
                            context,
                            provider.errorMessage ?? 'ظپط´ظ„ ط¨ط¯ط، ط§ظ„ط§ط³طھظ‚ط¨ط§ظ„',
                          );
                        }
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsBanner(
    BuildContext context,
    TransferProvider provider,
  ) {
    return Column(
      children: provider.missingRequirements.map((req) {
        String title;
        final String actionText = 'طھظپط¹ظٹظ„';
        IconData icon = SolarLinearIcons.dangerCircle;

        switch (req) {
          case HardwareRequirement.locationPermission:
            title = 'ط¥ط°ظ† ط§ظ„ظ…ظˆظ‚ط¹ ظ…ط·ظ„ظˆط¨ ظ„ظ„ط¨ط­ط« ط¹ظ† ط§ظ„ط£ط¬ظ‡ط²ط©';
            break;
          case HardwareRequirement.nearbyWifiPermission:
            title = 'ط¥ط°ظ† ط§ظ„ط£ط¬ظ‡ط²ط© ط§ظ„ظ‚ط±ظٹط¨ط© ظ…ط·ظ„ظˆط¨ ظپظٹ ط¥طµط¯ط§ط± ط£ظ†ط¯ط±ظˆظٹط¯ ظ‡ط°ط§';
            break;
          case HardwareRequirement.bluetoothPermission:
            title = 'ط¥ط°ظ† ط§ظ„ط¨ظ„ظˆطھظˆط« ظ…ط·ظ„ظˆط¨ ظ„ظ„ظ…ط´ط§ط±ظƒط©';
            break;
          case HardwareRequirement.locationService:
            title = 'ط®ط¯ظ…ط© ط§ظ„ظ…ظˆظ‚ط¹ (GPS) ظ…ط؛ظ„ظ‚ط©';
            icon = SolarLinearIcons.mapPoint;
            break;
          case HardwareRequirement.bluetoothService:
            title = 'ط§ظ„ط¨ظ„ظˆطھظˆط« ظ…ط؛ظ„ظ‚';
            icon = SolarLinearIcons.bluetooth;
            break;
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'IBM Plex Sans Arabic',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.fixRequirement(req),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  actionText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'IBM Plex Sans Arabic',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorBanner(BuildContext context, TransferProvider provider) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.error.withValues(alpha: 0.1)
            : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.error.withValues(alpha: 0.3)
              : Colors.red[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(SolarLinearIcons.dangerCircle, color: Colors.red[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.errorMessage!,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.error
                    : Colors.red[700],
                fontFamily: 'IBM Plex Sans Arabic',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: provider.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList(BuildContext context, TransferProvider provider) {
    if (provider.isScanning && provider.discoveredDevices.isEmpty) {
      return const _ScanningIndicator();
    }

    if (provider.discoveredDevices.isEmpty && !provider.isScanning) {
      return const _EmptyDevicesState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = provider.discoveredDevices[index];
        // Animated entry
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 100)),
          curve: Curves.easeOutQuart,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: _DeviceCard(
            device: device,
            onTap: () => _onDeviceSelected(context, device),
          ),
        );
      },
    );
  }

  void _onDeviceSelected(BuildContext context, TransferDevice device) async {
    Haptics.mediumTap();
    final provider = context.read<TransferProvider>();

    // Premium Connection Bottom Sheet
    final shouldConnect = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                SolarLinearIcons.smartphone,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ط§ظ„ط§طھطµط§ظ„ ط¨ط§ظ„ط¬ظ‡ط§ط²',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'IBM Plex Sans Arabic',
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ظ‡ظ„ طھط±ظٹط¯ ط§ظ„ط§طھطµط§ظ„ ط¨ظ€ ${device.deviceName}طں',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'IBM Plex Sans Arabic',
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'ط¥ظ„ط؛ط§ط،',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'ط§طھطµط§ظ„',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (shouldConnect == true && context.mounted) {
      final success = await provider.connectToDevice(device);
      if (success && context.mounted) {
        AnimatedToast.success(context, 'طھظ… ط§ظ„ط§طھطµط§ظ„ ط¨ظ†ط¬ط§ط­');
        _showFilePicker(context);
      } // Error is handled by provider setting error message
    }
  }

  Future<void> _showFilePicker(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty && context.mounted) {
      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      if (files.isNotEmpty) {
        final confirmed = await CustomDialog.show<bool>(
          context,
          title: 'طھط£ظƒظٹط¯ ط§ظ„ط¥ط±ط³ط§ظ„',
          message: 'ظ‡ظ„ طھط±ظٹط¯ ط¥ط±ط³ط§ظ„ ${files.length} ظ…ظ„ظپط§طھطں',
          type: DialogType.confirm,
          confirmText: 'ط¥ط±ط³ط§ظ„',
          cancelText: 'ط¥ظ„ط؛ط§ط،',
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length > 3 ? 3 : files.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final size = file.lengthSync();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(SolarLinearIcons.file, size: 20),
                        title: Text(
                          file.uri.pathSegments.last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Sans Arabic',
                          ),
                        ),
                        trailing: Text(
                          _formatBytes(size),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (files.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${files.length - 3} ظ…ظ„ظپط§طھ ط£ط®ط±ظ‰',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        if (confirmed == true && context.mounted) {
          final provider = context.read<TransferProvider>();
          final ids = await provider.sendFiles(files);

          if (ids.isNotEmpty && context.mounted) {
            AnimatedToast.success(
              context,
              'طھظ…طھ ط¥ط¶ط§ظپط© ${files.length} ظ…ظ„ظپ ط¥ظ„ظ‰ ظ‚ط§ط¦ظ…ط© ط§ظ„ط§ظ†طھط¸ط§ط±',
            );

            // Switch to transfers tab?
            // Usually context.read<TabController>().animateTo(1); but we don't have access to it easily here
            // unless we use a global key or callback.
            // For now, toast is enough.
          }
        }
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}

/// Transfers Tab - Active and Queued Transfers

// ==================== WIDGET COMPONENTS ====================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isActive,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              if (isLoading)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isActive ? Colors.white : color,
                    ),
                  ),
                )
              else
                Icon(icon, color: isActive ? Colors.white : color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : color,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningIndicator extends StatefulWidget {
  const _ScanningIndicator();

  @override
  State<_ScanningIndicator> createState() => _ScanningIndicatorState();
}

class _ScanningIndicatorState extends State<_ScanningIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing circles
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final delay = index * 0.5; // Stagger start
                      final value = (_controller.value + delay) % 1.0;
                      final size = 50.0 + (value * 150.0);
                      final opacity = (1.0 - value).clamp(0.0, 1.0);

                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(
                              alpha: opacity * 0.5,
                            ),
                            width: 2,
                          ),
                          color: AppColors.primary.withValues(
                            alpha: opacity * 0.1,
                          ),
                        ),
                      );
                    },
                  );
                }),
                // Center Icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    SolarBoldIcons.magnifer,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ط¬ط§ط±ظٹ ط§ظ„ط¨ط­ط« ط¹ظ† ط§ظ„ط£ط¬ظ‡ط²ط©...',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).hintColor,
              fontFamily: 'IBM Plex Sans Arabic',
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedEmptyState extends StatefulWidget {
  final IconData icon;

  const _AnimatedEmptyState({required this.icon});

  @override
  State<_AnimatedEmptyState> createState() => _AnimatedEmptyStateState();
}

class _AnimatedEmptyStateState extends State<_AnimatedEmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.slow, // Apple standard: 400ms (was 800ms)
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).disabledColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDevicesState extends StatelessWidget {
  const _EmptyDevicesState();

  @override
  Widget build(BuildContext context) {
    return const _AnimatedEmptyState(icon: SolarLinearIcons.transmission);
  }
}

class _EmptyTransfersState extends StatelessWidget {
  const _EmptyTransfersState();

  @override
  Widget build(BuildContext context) {
    return const _AnimatedEmptyState(icon: SolarLinearIcons.folderOpen);
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return const _AnimatedEmptyState(icon: SolarLinearIcons.clockCircle);
  }
}

class _DeviceCard extends StatelessWidget {
  final TransferDevice device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
        ), // Dark mode fix
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  SolarLinearIcons.smartphone,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'IBM Plex Sans Arabic',
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    if (device.model != null)
                      Text(
                        device.model!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                  ],
                ),
              ),
              // Signal indicator placeholder (future polish)
              Icon(
                SolarLinearIcons.altArrowLeft,
                color: Theme.of(context).dividerColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransfersTab extends StatelessWidget {
  const _TransfersTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransferProvider>();

    if (!provider.hasActiveTransfers) {
      return const _EmptyTransfersState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.activeTransfers.length,
      itemBuilder: (context, index) {
        final transfer = provider.activeTransfers[index];
        return _TransferCard(transfer: transfer);
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransferProvider>();

    if (provider.transferHistory.isEmpty) {
      return const _EmptyHistoryState();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ط§ظ„ط³ط¬ظ„',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'IBM Plex Sans Arabic',
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Haptics.mediumTap();
                  provider.clearHistory();
                  AnimatedToast.success(context, 'طھظ… ظ…ط³ط­ ط§ظ„ط³ط¬ظ„');
                },
                icon: const Icon(
                  SolarLinearIcons.trashBinMinimalistic,
                  size: 20,
                ),
                label: const Text(
                  'ظ…ط³ط­ ط§ظ„ظƒظ„',
                  style: TextStyle(fontFamily: 'IBM Plex Sans Arabic'),
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: provider.transferHistory.length,
            itemBuilder: (context, index) {
              final transfer = provider.transferHistory[index];
              return _TransferCard(transfer: transfer);
            },
          ),
        ),
      ],
    );
  }
}

class _TransferCard extends StatelessWidget {
  final TransferSession transfer;

  const _TransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final isIncoming = transfer.isIncoming;
    final isCompleted = transfer.state == TransferState.completed;
    final isFailed = transfer.state == TransferState.failed;
    final inProgress =
        transfer.state == TransferState.transferring ||
        transfer.state == TransferState.connecting;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
        ), // Dark mode fix
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (isFailed
                                ? Colors.red
                                : isCompleted
                                ? Colors.green
                                : AppColors.primary)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isIncoming
                        ? SolarLinearIcons.download
                        : SolarLinearIcons.upload,
                    color: isFailed
                        ? Colors.red
                        : isCompleted
                        ? Colors.green
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transfer.metadata.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'IBM Plex Sans Arabic',
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatBytes(transfer.bytesTransferred),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                          Text(
                            ' / ${_formatBytes(transfer.metadata.fileSize)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (inProgress) ...[
                  IconButton(
                    icon: Icon(
                      transfer.state == TransferState.paused
                          ? SolarBoldIcons.playCircle
                          : SolarBoldIcons.pauseCircle,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      Haptics.mediumTap();
                      final provider = context.read<TransferProvider>();
                      if (transfer.state == TransferState.paused) {
                        provider.resumeTransfer(transfer.sessionId);
                      } else {
                        provider.pauseTransfer(transfer.sessionId);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      SolarLinearIcons.closeCircle,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      Haptics.mediumTap();
                      context.read<TransferProvider>().cancelTransfer(
                        transfer.sessionId,
                      );
                    },
                  ),
                ] else if (isFailed)
                  IconButton(
                    icon: const Icon(
                      SolarLinearIcons.refreshCircle,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      Haptics.mediumTap();
                      context.read<TransferProvider>().retryTransfer(
                        transfer.sessionId,
                      );
                    },
                  ),
              ],
            ),
            if (inProgress) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: transfer.progress,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(transfer.progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    _formatSpeed(transfer.scSpeed),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ],
            if (isFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  transfer.error ?? 'ظپط´ظ„ ط§ظ„ظ†ظ‚ظ„',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            if (isCompleted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      SolarBoldIcons.checkCircle,
                      size: 14,
                      color: Colors.green,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'طھظ… ط¨ظ†ط¬ط§ط­',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatSpeed(double speed) {
    if (speed < 0.1) return 'ط¬ط§ط±ظٹ ط§ظ„ط§طھطµط§ظ„...';
    return '${_formatBytes(speed.toInt())}/s';
  }
}
