import 'dart:async';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_outline_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/utils/auth_strings.dart';

/// Waiting for Approval screen
///
/// Shown after email verification while waiting for admin approval.
/// Polls approval status every 30 seconds.
/// Auto-navigates to dashboard once approved.
class WaitingForApprovalScreen extends StatefulWidget {
  const WaitingForApprovalScreen({super.key, required this.email});

  final String email;

  @override
  State<WaitingForApprovalScreen> createState() => _WaitingForApprovalScreenState();
}

class _WaitingForApprovalScreenState extends State<WaitingForApprovalScreen> {
  Timer? _pollTimer;
  int _elapsedSeconds = 0;
  bool _isChecking = false;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    // Check immediately
    _checkApprovalStatus();
    // Poll every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkApprovalStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkApprovalStatus() async {
    if (!mounted || _isChecking) return;

    setState(() => _isChecking = true);
    final authProvider = context.read<AuthProvider>();
    final status = await authProvider.checkApprovalStatus();
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      // FIX: Calculate elapsed from actual start time instead of incrementing
      if (_startTime != null) {
        _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
      }
    });

    if (status != null) {
      if (status['is_approved_by_admin'] == true) {
        // Approved! Navigate to dashboard
        Haptics.mediumTap();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthStrings.t('تمت الموافقة على حسابك! مرحباً بك', 'Your account has been approved! Welcome')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.dashboard,
          (route) => false,
        );
      } else if (status['approval_status'] == 'rejected') {
        // Rejected
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('عذراً، تم رفض طلبك. يرجى التواصل مع الدعم'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
        _pollTimer?.cancel();
      }
    }
  }

  Future<void> _handleLogout() async {
    Haptics.mediumTap();
    final authProvider = context.read<AuthProvider>();
    await authProvider.logout(reason: 'تم تسجيل الخروج');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  String get _formattedElapsed {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Animated Icon
              RepaintBoundary(
                child: Container(
                  width: 100,
                  height: 100,
                  margin: const EdgeInsets.only(bottom: AppDimensions.spacing32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.warningLight.withValues(alpha: 0.8),
                        AppColors.warningLight,
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warningLight.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Spinning ring
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, _) {
                          return CircularProgressIndicator(
                            value: value,
                            strokeWidth: 3,
                            color: Colors.white.withValues(alpha: 0.5),
                          );
                        },
                      ),
                      const Icon(SolarLinearIcons.clockCircle, color: Colors.white, size: 48),
                    ],
                  ),
                ),
              ),

              // Title
              Text(
                'حسابك قيد المراجعة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.headlineSmall?.color,
                ),
              ),
              const SizedBox(height: AppDimensions.spacing16),

              // Description
              Text(
                'تم التحقق من بريدك الإلكتروني بنجاح.\n'
                'سيتم مراجعة حسابك والموافقة عليه من قبل المسؤول.\n'
                'ستتم إشعارك فور الموافقة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: theme.textTheme.bodySmall?.color,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: AppDimensions.spacing16),

              // Email
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: ShapeDecoration(
                  color: theme.colorScheme.surface,
                  shape: SmoothRectangleBorder(
                    borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 1.0),
                    side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mail_outline, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spacing32),

              // Polling indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isChecking)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    'جاري التحقق تلقائياً كل 30 ثانية',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacing8),
              Text(
                'وقت الانتظار: $_formattedElapsed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: AppDimensions.spacing16),

              // Manual check button
              TextButton.icon(
                onPressed: _isChecking ? null : _checkApprovalStatus,
                icon: const Icon(SolarLinearIcons.refresh, size: 18),
                label: const Text('تحقق يدوياً الآن'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
              ),

              const Spacer(),

              // Logout button
              AppOutlineButton(
                text: 'تسجيل الخروج والعودة',
                onPressed: _handleLogout,
                gradientColors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                showShadow: false,
              ),
              const SizedBox(height: AppDimensions.spacing24),
            ],
          ),
        ),
      ),
    );
  }
}
