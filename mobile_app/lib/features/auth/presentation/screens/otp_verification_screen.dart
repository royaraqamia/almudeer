import 'dart:async';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';

/// OTP Verification screen
///
/// Flow:
/// 1. Shows 6-digit input boxes
/// 2. Countdown timer (10 minutes)
/// 3. Resend button with 60-second cooldown
/// 4. On success: navigates to WaitingForApprovalScreen
class OTPVerificationScreen extends StatefulWidget {
  const OTPVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _remainingSeconds = 600; // 10 minutes
  int _resendCooldown = 0;
  Timer? _timer;
  Timer? _resendTimer;
  bool _isVerifying = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _handleVerify() async {
    // Prevent verification if widget is disposed or already verifying
    if (_isDisposed || _isVerifying) return;

    final otpCode = _controllers.map((c) => c.text).join();
    if (otpCode.length != 6) {
      _showError('يرجى إدخال رمز التحقق كاملاً');
      return;
    }

    setState(() => _isVerifying = true);
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.verifyOTP(widget.email, otpCode);
    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (success) {
      Haptics.mediumTap();
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.waitingForApproval,
        arguments: {
          'email': widget.email,
        },
        (route) => false,
      );
    }
  }

  Future<void> _handleResendOTP() async {
    if (_resendCooldown > 0) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resendOTP(widget.email);
    if (!mounted) return;

    if (success) {
      Haptics.lightTap();
      _showSuccess('تم إرسال رمز التحقق بنجاح');
      setState(() {
        _resendCooldown = 60;
        _remainingSeconds = 600;
      });
      _startResendCooldown();
      _startTimer();
      // Clear all inputs
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TapRegion(
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(SolarLinearIcons.arrowLeft, color: theme.colorScheme.primary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.spacing24),

                // Icon
                RepaintBoundary(
                  child: Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(bottom: AppDimensions.spacing24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(SolarLinearIcons.shieldCheck, color: Colors.white, size: 40),
                  ),
                ),

                // Title
                Text(
                  'التحقق من البريد الإلكتروني',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineSmall?.color,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing8),
                Text(
                  'تم إرسال رمز مكون من 6 أرقام إلى\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodySmall?.color,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing32),

                // OTP Input Boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                          ),
                        ),
                        onChanged: (value) {
                          if (_isDisposed) return; // Prevent auto-verify during disposal
                          if (value.isNotEmpty) {
                            if (index < 5) {
                              _focusNodes[index + 1].requestFocus();
                            }
                            // Auto-submit when last box is filled
                            if (index == 5) {
                              _handleVerify();
                            }
                          } else if (value.isEmpty) {
                            if (index > 0) {
                              _focusNodes[index - 1].requestFocus();
                            }
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppDimensions.spacing16),

                // Timer
                Text(
                  _formattedTime,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _remainingSeconds < 60 ? AppColors.error : theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing8),
                Text(
                  'ينتهي الرمز بعد هذا الوقت',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing32),

                // Error Message
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    if (auth.errorMessage == null) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                      decoration: ShapeDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 1.0),
                          side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                        ),
                      ),
                      child: Text(
                        auth.errorMessage!,
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),

                // Verify Button
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return AppGradientButton(
                      text: _isVerifying ? 'جاري التحقق...' : 'تحقق',
                      onPressed: _isVerifying || auth.isLoading ? null : _handleVerify,
                      isLoading: _isVerifying || auth.isLoading,
                      gradientColors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                      showShadow: true,
                    );
                  },
                ),
                const SizedBox(height: AppDimensions.spacing16),

                // Resend OTP
                Center(
                  child: TextButton(
                    onPressed: _resendCooldown > 0 ? null : _handleResendOTP,
                    child: Text(
                      _resendCooldown > 0
                          ? 'إعادة الإرسال بعد $_resendCooldown ثانية'
                          : 'إعادة إرسال الرمز',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _resendCooldown > 0
                            ? theme.textTheme.bodySmall?.color
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
