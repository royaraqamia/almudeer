import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/app_config.dart';
import 'package:almudeer_mobile_app/features/qr/presentation/widgets/scanner_overlay.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/loading_overlay.dart';
import 'package:almudeer_mobile_app/features/qr/presentation/widgets/qr_generator.dart';
import 'package:almudeer_mobile_app/features/qr/data/services/qr_action_handler.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/qr/presentation/providers/qr_scanner_provider.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  bool _isFlashOn = false;
  bool _isHandlingResult = false;
  bool _isCameraInitialized = false;
  DateTime? _lastScanTime;
  
  // Provider reference for history
  QrScannerProvider? _provider;

  // Debounce duration from app config
  static final _debounceDuration = AppConfig.qrScanDebounceDuration;

  // Tab controller
  late TabController _tabController;

  // Generate tab state
  final TextEditingController _qrDataController = TextEditingController();
  String _generatedQrData = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    // Initialize camera after permission check
    _initializeCamera();
    // Load persisted flash state
    _loadFlashState();
    // Get provider and set up history callback after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _provider = context.read<QrScannerProvider?>();
        // Set static callback for QRActionHandler
        if (_provider != null) {
          QRActionHandler.setHistoryCallback(_provider!.addToHistory);
        }
      }
    });
  }

  /// Initialize camera with proper permission handling
  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.status;

      if (status.isDenied) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (mounted) {
            if (result.isPermanentlyDenied) {
              AnimatedToast.error(
                context,
                'ظٹط±ط¬ظ‰ طھظپط¹ظٹظ„ طµظ„ط§ط­ظٹط© ط§ظ„ظƒط§ظ…ظٹط±ط§ ظ…ظ† ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
              );
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) {
                await openAppSettings();
              }
            } else {
              AnimatedToast.error(context, 'طھظ… ط±ظپط¶ طµظ„ط§ط­ظٹط© ط§ظ„ظƒط§ظ…ظٹط±ط§');
            }
          }
          return;
        }
      }

      // Only create controller after permission is granted
      if (mounted) {
        setState(() {
          _controller = MobileScannerController(
            detectionSpeed: DetectionSpeed.noDuplicates,
            returnImage: false,
            facing: CameraFacing.back,
            autoStart: true,
          );
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, 'ظپط´ظ„ طھظ‡ظٹط¦ط© ط§ظ„ظƒط§ظ…ظٹط±ط§: ${e.toString()}');
      }
    }
  }

  /// Load persisted flash state
  Future<void> _loadFlashState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFlashOn = prefs.getBool(AppConfig.qrFlashEnabledKey) ?? false;
      if (mounted && isFlashOn) {
        setState(() {
          _isFlashOn = isFlashOn;
        });
        // Turn on flash only after controller is fully initialized
        // Wait for next frame to ensure controller is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Double-check controller state before toggling
          final controller = _controller;
          if (controller == null || !controller.value.isInitialized) {
            debugPrint('Flash toggle skipped: controller not initialized');
            return;
          }
          // Check if device has torch capability
          if (controller.value.torchState != TorchState.off &&
              controller.value.torchState != TorchState.on) {
            debugPrint('Flash toggle skipped: torch not available');
            return;
          }
          try {
            controller.toggleTorch();
          } catch (e) {
            // Handle camera-specific errors gracefully
            debugPrint('Failed to toggle torch: $e');
          }
        });
      }
    } catch (e) {
      // Ignore errors loading flash state (non-critical feature)
      debugPrint('Error loading flash state: $e');
    }
  }

  /// Persist flash state
  Future<void> _saveFlashState(bool isFlashOn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.qrFlashEnabledKey, isFlashOn);
    } catch (e) {
      // Ignore errors saving flash state
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    // Pause camera when app goes to background to save battery
    // Resume when app comes to foreground
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller?.stop();
        break;
      case AppLifecycleState.resumed:
        _controller?.start();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _qrDataController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    _isCameraInitialized = false;
    // Clear static callback to prevent memory leak
    QRActionHandler.clearHistoryCallback();
    super.dispose();
  }

  /// Handle barcode detection with proper error handling and haptic feedback
  Future<void> _handleBarcode(BarcodeCapture capture) async {
    // Prevent duplicate rapid scans
    if (_isHandlingResult) return;

    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!) < _debounceDuration) {
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;

    // Handle empty barcodes with user feedback
    if (barcodes.isEmpty) {
      if (mounted) {
        Haptics.vibrate();
        AnimatedToast.error(context, 'ظ„ظ… ظٹطھظ… ط§ظ„طھط¹ط±ظپ ط¹ظ„ظ‰ ط§ظ„ط±ظ…ط²');
      }
      return;
    }

    final code = barcodes.first.rawValue;

    // Handle null or empty code with user feedback
    if (code == null || code.isEmpty) {
      if (mounted) {
        Haptics.vibrate();
        AnimatedToast.error(context, 'ط§ظ„ط±ظ…ط² ط§ظ„ظ…ظ…ط³ظˆط­ ظپط§ط±ط؛');
      }
      return;
    }

    // Mark as handling to prevent duplicate scans
    setState(() {
      _isHandlingResult = true;
      _lastScanTime = now;
    });

    // Provide haptic feedback on successful scan
    Haptics.lightTap();

    // Stop camera to prevent multiple detections
    await _controller?.stop();

    if (!mounted) return;

    try {
      // Note: handleResult now saves history via the static callback set in initState
      // and AnimatedToast checks mounted internally
      await QRActionHandler.handleResult(context, code);
    } catch (e) {
      // Error handling is done by AnimatedToast internally
    } finally {
      // Restart camera only if still mounted and controller is valid
      if (mounted && _controller?.value.isInitialized == true) {
        setState(() {
          _isHandlingResult = false;
        });
        try {
          await _controller?.start();
        } catch (e) {
          // Controller may have been disposed, ignore
        }
      }
    }
  }

  /// Pick image from gallery with proper cleanup and error handling
  Future<void> _pickImageFromGallery() async {
    // Check photos permission first (iOS 14+)
    try {
      final photosStatus = await Permission.photos.status;
      if (photosStatus.isDenied) {
        final result = await Permission.photos.request();
        if (!result.isGranted) {
          if (mounted) {
            if (result.isPermanentlyDenied) {
              AnimatedToast.error(
                context,
                'ظٹط±ط¬ظ‰ طھظپط¹ظٹظ„ طµظ„ط§ط­ظٹط© ط§ظ„ظˆطµظˆظ„ ظ„ظ„ظ…ط¹ط±ط¶ ظ…ظ† ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
              );
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) {
                await openAppSettings();
              }
            } else {
              AnimatedToast.error(context, 'طھظ… ط±ظپط¶ طµظ„ط§ط­ظٹط© ط§ظ„ظˆطµظˆظ„ ظ„ظ„ظ…ط¹ط±ط¶');
            }
          }
          return;
        }
      }
    } catch (e) {
      // Permission check failed - continue anyway, may fail later
      debugPrint('Photo permission check failed: $e');
    }
    
    final ImagePicker picker = ImagePicker();
    XFile? image;

    try {
      image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, // Compress for faster processing
      );

      if (image == null) return;

      if (!mounted) return;

      // Show loading overlay
      LoadingOverlay.show(
        context: context,
        message: 'ط¬ط§ط±ظٹ طھط­ظ„ظٹظ„ ط§ظ„طµظڈظ‘ظˆط±ط©...',
      );

      try {
        // image is guaranteed non-null here because we checked above
        final BarcodeCapture? capture =
            await _controller?.analyzeImage(image.path);

        if (mounted) {
          // Hide loading overlay
          Navigator.pop(context);

          if (capture != null && capture.barcodes.isNotEmpty) {
            await _handleBarcode(capture);
          } else {
            Haptics.vibrate();
            AnimatedToast.error(context, 'ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط±ظ…ط² QR ظپظٹ ط§ظ„طµظڈظ‘ظˆط±ط©');
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          Haptics.vibrate();
          AnimatedToast.error(context, 'ط­ط¯ط« ط®ط·ط£ ط£ط«ظ†ط§ط، ظ‚ط±ط§ط،ط© ط§ظ„طµظڈظ‘ظˆط±ط©');
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
        Haptics.vibrate();
        AnimatedToast.error(context, 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„طµظڈظ‘ظˆط±ط©');
      }
    } finally {
      // Note: XFile doesn't have delete() method
      // Image is temporary and will be cleaned by the system
    }
  }

  /// Generate QR code from input
  void _generateQrCode() {
    final data = _qrDataController.text.trim();
    if (data.isEmpty) {
      AnimatedToast.error(context, 'ط§ظ„ط±ط¬ط§ط، ط¥ط¯ط®ط§ظ„ ظ†طµ ط£ظˆ ط±ط§ط¨ط·');
      return;
    }

    if (!QRGenerator.isValidData(data)) {
      AnimatedToast.error(context, 'ط§ظ„ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط¯ط®ظ„ط© ط؛ظٹط± طµط§ظ„ط­ط©');
      return;
    }

    setState(() {
      _generatedQrData = data;
    });

    // Show QR code in bottom sheet
    QRGeneratorBottomSheet.show(
      context,
      title: 'ط±ظ…ط² QR',
      data: data,
      size: 250,
      subtitle: 'ظٹظ…ظƒظ†ظƒ ظ…ط´ط§ط±ظƒط© ظ‡ط°ط§ ط§ظ„ط±ظ…ط² ط£ظˆ ط­ظپط¸ظ‡',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'ظ…ط§ط³ط­ ظˆظ…ظˆظ„ط¯ QR',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        leading: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.5),
          child: IconButton(
            icon: const Icon(
              SolarLinearIcons.arrowRight,
              color: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(
              icon: Icon(SolarLinearIcons.qrCode),
              text: 'ظ…ط³ط­',
            ),
            Tab(
              icon: Icon(SolarLinearIcons.addSquare),
              text: 'ط¥ظ†ط´ط§ط،',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Scan Tab
          _buildScanTab(),
          // Generate Tab
          _buildGenerateTab(),
        ],
      ),
    );
  }

  /// Build Scan Tab
  Widget _buildScanTab() {
    return Stack(
      children: [
        // Camera view with error handling
        if (_isCameraInitialized && _controller != null)
          MobileScanner(
            controller: _controller!,
            onDetect: _handleBarcode,
            errorBuilder: (context, error) {
              return _buildCameraErrorWidget(error);
            },
          )
        else
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),

        // Scanner overlay
        const ScannerOverlay(),

        // Bottom Controls
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Gallery Button
              _buildControlButton(
                icon: SolarLinearIcons.gallery,
                label: 'ط§ظ„ظ…ط¹ط±ط¶',
                onTap: _pickImageFromGallery,
              ),

              // Flash Button
              _buildControlButton(
                icon: _isFlashOn
                    ? SolarLinearIcons.flashlight
                    : Icons.flashlight_off_outlined,
                label: 'ط§ظ„ط¥ط¶ط§ط،ط©',
                isActive: _isFlashOn,
                onTap: _toggleFlash,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build Generate Tab
  Widget _buildGenerateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),

          // Title
          const Text(
            'ط¥ظ†ط´ط§ط، ط±ظ…ط² QR',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Subtitle
          Text(
            'ط£ط¯ط®ظ„ ط§ظ„ظ†طµ ط£ظˆ ط§ظ„ط±ط§ط¨ط· ظ„ط¥ظ†ط´ط§ط، ط±ظ…ط² QR',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Input Field
          TextField(
            controller: _qrDataController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'ط£ط¯ط®ظ„ ط§ظ„ظ†طµ ط£ظˆ ط§ظ„ط±ط§ط¨ط· ظ‡ظ†ط§...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              prefixIcon: const Icon(
                Icons.text_fields,
                color: AppColors.primary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            maxLines: 4,
            minLines: 3,
            keyboardType: TextInputType.multiline,
          ),

          const SizedBox(height: 24),

          // Generate Button
          ElevatedButton(
            onPressed: _generateQrCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'ط¥ظ†ط´ط§ط، ط±ظ…ط² QR',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // QR Code Preview (if generated)
          if (_generatedQrData.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 32),

            const SizedBox(height: 16),

            const Text(
              'ظ…ط¹ط§ظٹظ†ط© ط§ظ„ط±ظ…ط²',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // QR Code with white background for better contrast
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QRGenerator(
                data: _generatedQrData,
                size: 200,
                semanticLabel: 'ظ…ط¹ط§ظٹظ†ط© ط±ظ…ط² QR',
              ),
            ),

            const SizedBox(height: 24),

            // Quick Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    if (_generatedQrData.isNotEmpty) {
                      QRGeneratorBottomSheet.show(
                        context,
                        title: 'ط±ظ…ط² QR',
                        data: _generatedQrData,
                        size: 250,
                      );
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('ظ…ط´ط§ط±ظƒط©'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _qrDataController.clear();
                      _generatedQrData = '';
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('ط¬ط¯ظٹط¯'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  /// Build camera error widget with comprehensive error handling
  Widget _buildCameraErrorWidget(dynamic error) {
    String errorMessage = 'ظپط´ظ„ ط§ظ„ظˆطµظˆظ„ ظ„ظ„ظƒط§ظ…ظٹط±ط§';
    IconData errorIcon = SolarLinearIcons.cameraMinimalistic;

    // Handle different error types
    if (error is MobileScannerException) {
      switch (error.errorCode) {
        case MobileScannerErrorCode.permissionDenied:
          errorMessage = 'طµظ„ط§ط­ظٹط© ط§ظ„ظƒط§ظ…ظٹط±ط§ ظ…ط±ظپظˆط¶ط©';
          errorIcon = Icons.lock_outline;
          break;
        case MobileScannerErrorCode.controllerUninitialized:
          errorMessage = 'ط§ظ„ظƒط§ظ…ظٹط±ط§ ط؛ظٹط± ظ…ظ‡ظٹط¦ط©';
          break;
        default:
          // Handle other error codes generically
          errorMessage = 'ط®ط·ط£ ظپظٹ ط§ظ„ظƒط§ظ…ظٹط±ط§';
      }
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            errorIcon,
            color: Colors.white.withValues(alpha: 0.7),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            errorMessage,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings, color: Colors.white),
            label: const Text(
              'ظپطھط­ ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Toggle flash with state persistence and error handling
  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      debugPrint('Flash toggle skipped: controller not initialized');
      return;
    }

    // Check if torch is available
    if (controller.value.torchState != TorchState.off &&
        controller.value.torchState != TorchState.on) {
      if (mounted) {
        AnimatedToast.error(context, 'ط§ظ„ط¥ط¶ط§ط،ط© ط؛ظٹط± ظ…طھط§ط­ط© ظپظٹ ظ‡ط°ط§ ط§ظ„ط¬ظ‡ط§ط²');
      }
      return;
    }

    try {
      await controller.toggleTorch();
      final newState = !_isFlashOn;
      setState(() {
        _isFlashOn = newState;
      });
      // Persist flash state
      await _saveFlashState(newState);
    } catch (e) {
      debugPrint('Failed to toggle torch: $e');
      if (mounted) {
        AnimatedToast.error(context, 'ظپط´ظ„ طھط؛ظٹظٹط± ط§ظ„ط¥ط¶ط§ط،ط©');
      }
    }
  }

  /// Build control button with consistent styling
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
