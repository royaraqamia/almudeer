import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/colors.dart';
import '../../widgets/scanner_overlay.dart';
import '../../widgets/animated_toast.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/qr_generator.dart';
import '../../../services/qr_action_handler.dart';
import '../../../core/utils/haptics.dart';

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

  // Debounce duration
  static const _debounceDuration = Duration(seconds: 2);

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
                'يرجى تفعيل صلاحية الكاميرا من الإعدادات',
              );
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) {
                await openAppSettings();
              }
            } else {
              AnimatedToast.error(context, 'تم رفض صلاحية الكاميرا');
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
        AnimatedToast.error(context, 'فشل تهيئة الكاميرا: ${e.toString()}');
      }
    }
  }

  /// Load persisted flash state
  Future<void> _loadFlashState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFlashOn = prefs.getBool('qr_flash_enabled') ?? false;
      if (mounted && isFlashOn) {
        setState(() {
          _isFlashOn = isFlashOn;
        });
        // Turn on flash after controller is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _controller?.value.isInitialized == true) {
            _controller?.toggleTorch();
          }
        });
      }
    } catch (e) {
      // Ignore errors loading flash state
    }
  }

  /// Persist flash state
  Future<void> _saveFlashState(bool isFlashOn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('qr_flash_enabled', isFlashOn);
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
        AnimatedToast.error(context, 'لم يتم التعرف على الرمز');
      }
      return;
    }

    final code = barcodes.first.rawValue;

    // Handle null or empty code with user feedback
    if (code == null || code.isEmpty) {
      if (mounted) {
        Haptics.vibrate();
        AnimatedToast.error(context, 'الرمز الممسوح فارغ');
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
      // Note: handleResult may use context, but we've checked mounted above
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
        message: 'جاري تحليل الصُّورة...',
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
            AnimatedToast.error(context, 'لم يتم العثور على رمز QR في الصُّورة');
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          Haptics.vibrate();
          AnimatedToast.error(context, 'حدث خطأ أثناء قراءة الصُّورة');
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
        Haptics.vibrate();
        AnimatedToast.error(context, 'فشل تحميل الصُّورة');
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
      AnimatedToast.error(context, 'الرجاء إدخال نص أو رابط');
      return;
    }

    if (!QRGenerator.isValidData(data)) {
      AnimatedToast.error(context, 'البيانات المدخلة غير صالحة');
      return;
    }

    setState(() {
      _generatedQrData = data;
    });

    // Show QR code in bottom sheet
    QRGeneratorBottomSheet.show(
      context,
      title: 'رمز QR',
      data: data,
      size: 250,
      subtitle: 'يمكنك مشاركة هذا الرمز أو حفظه',
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
          'ماسح ومولد QR',
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
              text: 'مسح',
            ),
            Tab(
              icon: Icon(SolarLinearIcons.addSquare),
              text: 'إنشاء',
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
                label: 'المعرض',
                onTap: _pickImageFromGallery,
              ),

              // Flash Button
              _buildControlButton(
                icon: _isFlashOn
                    ? SolarLinearIcons.flashlight
                    : Icons.flashlight_off_outlined,
                label: 'الإضاءة',
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
            'إنشاء رمز QR',
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
            'أدخل النص أو الرابط لإنشاء رمز QR',
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
              hintText: 'أدخل النص أو الرابط هنا...',
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
              'إنشاء رمز QR',
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
              'معاينة الرمز',
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
                semanticLabel: 'معاينة رمز QR',
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
                        title: 'رمز QR',
                        data: _generatedQrData,
                        size: 250,
                      );
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
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
                  label: const Text('جديد'),
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
    String errorMessage = 'فشل الوصول للكاميرا';
    IconData errorIcon = SolarLinearIcons.cameraMinimalistic;

    // Handle different error types
    if (error is MobileScannerException) {
      switch (error.errorCode) {
        case MobileScannerErrorCode.permissionDenied:
          errorMessage = 'صلاحية الكاميرا مرفوضة';
          errorIcon = Icons.lock_outline;
          break;
        case MobileScannerErrorCode.controllerUninitialized:
          errorMessage = 'الكاميرا غير مهيئة';
          break;
        default:
          // Handle other error codes generically
          errorMessage = 'خطأ في الكاميرا';
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
              'فتح الإعدادات',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Toggle flash with state persistence and error handling
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      await _controller!.toggleTorch();
      final newState = !_isFlashOn;
      setState(() {
        _isFlashOn = newState;
      });
      // Persist flash state
      await _saveFlashState(newState);
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, 'فشل تغيير الإضاءة');
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
