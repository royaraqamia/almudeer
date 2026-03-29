import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/features/integrations/data/repositories/integrations_repository.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// Dedicated screen for Telegram Phone setup with multi-step flow
class TelegramPhoneSetupScreen extends StatefulWidget {
  const TelegramPhoneSetupScreen({super.key});

  @override
  State<TelegramPhoneSetupScreen> createState() =>
      _TelegramPhoneSetupScreenState();
}

class _TelegramPhoneSetupScreenState extends State<TelegramPhoneSetupScreen> {
  final IntegrationsRepository _repository = IntegrationsRepository();

  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State
  int _currentStep = 1; // 1: Phone, 2: Code, 3: 2FA Password
  bool _isLoading = false;
  String? _errorMessage;
  String? _sessionId;
  String? _phoneNumber;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _repository.startTelegramPhoneLogin(phone);
      _sessionId = response['session_id'];
      _phoneNumber = phone;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = 2;
        });
        AnimatedToast.success(context, 'طھظ… ط¥ط±ط³ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _repository.verifyTelegramPhoneCode(
        _phoneNumber!,
        code,
        sessionId: _sessionId,
      );

      if (mounted) {
        AnimatedToast.success(context, 'طھظ… ط±ط¨ط· Telegram ط¨ظ†ط¬ط§ط­!');
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      final errorMsg = e.toString();

      // Check for 2FA error
      if (errorMsg.contains('2FA') || errorMsg.contains('ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±')) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _currentStep = 3;
            _errorMessage = null;
          });
          AnimatedToast.info(context, 'ط­ط³ط§ط¨ظƒ ظ…ط­ظ…ظٹ ط¨ظƒظ„ظ…ط© ظ…ط±ظˆط± ط«ظ†ط§ط¦ظٹط©');
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = errorMsg.replaceAll('Exception:', '').trim();
          });
        }
      }
    }
  }

  Future<void> _verifyPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _repository.verifyTelegramPhoneCode(
        _phoneNumber!,
        _codeController.text.trim(),
        sessionId: _sessionId,
        password: password,
      );

      if (mounted) {
        AnimatedToast.success(context, 'طھظ… ط±ط¨ط· Telegram ط¨ظ†ط¬ط§ط­!');
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  void _goBack() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            SolarLinearIcons.altArrowRight,
            color: theme.iconTheme.color,
          ),
          onPressed: _goBack,
        ),
        title: Text(
          'ط±ط¨ط· Telegram',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.telegramBlue.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.telegramBlue.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: const SizedBox(),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  // Step indicator
                  _buildStepIndicator(theme),
                  const SizedBox(height: 32),

                  // Icon
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.telegramBlue.withValues(alpha: 0.2),
                            AppColors.telegramBlue.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.telegramBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        _currentStep == 1
                            ? SolarLinearIcons.phone
                            : _currentStep == 2
                            ? SolarLinearIcons.letter
                            : SolarLinearIcons.lockKeyhole,
                        color: AppColors.telegramBlue,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    _getStepTitle(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    _getStepSubtitle(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Input card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withValues(
                        alpha: isDark ? 0.6 : 0.8,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Input field
                        _buildInputField(theme),
                        const SizedBox(height: 16),

                        // Error message
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  SolarLinearIcons.dangerTriangle,
                                  color: AppColors.error,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Action button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _getActionCallback(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.telegramBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 4,
                              shadowColor: AppColors.telegramBlue.withValues(
                                alpha: 0.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _getButtonText(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Help text
                  if (_currentStep == 1) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                SolarLinearIcons.infoCircle,
                                color: AppColors.telegramBlue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ظ…ظ„ط§ط­ط¸ط§طھ ظ‡ط§ظ…ط©',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.telegramBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildHelpItem(
                            'ط£ط¯ط®ظ„ ط§ظ„ط±ظ‚ظ… ظ…ط¹ ط§ظ„ط±ظ…ط² ط§ظ„ط¯ظˆظ„ظٹ (ظ…ط«ط§ظ„: +966)',
                            theme,
                          ),
                          _buildHelpItem(
                            'ط³ظٹطھظ… ط¥ط±ط³ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚ ط¥ظ„ظ‰ طھط·ط¨ظٹظ‚ Telegram',
                            theme,
                          ),
                          _buildHelpItem(
                            'طھط£ظƒط¯ ظ…ظ† طھط«ط¨ظٹطھ طھط·ط¨ظٹظ‚ Telegram ط¹ظ„ظ‰ ظ‡ط§طھظپظƒ',
                            theme,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepDot(1, theme),
        _buildStepLine(1, theme),
        _buildStepDot(2, theme),
        _buildStepLine(2, theme),
        _buildStepDot(3, theme),
      ],
    );
  }

  Widget _buildStepDot(int step, ThemeData theme) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isCurrent ? 40 : 32,
      height: isCurrent ? 40 : 32,
      decoration: BoxDecoration(
        color: isActive ? AppColors.telegramBlue : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.telegramBlue : theme.dividerColor,
          width: 2,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.telegramBlue.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Center(
        child: step < _currentStep
            ? const Icon(
                SolarLinearIcons.checkCircle,
                color: Colors.white,
                size: 16,
              )
            : Text(
                '$step',
                style: TextStyle(
                  color: isActive ? Colors.white : theme.hintColor,
                  fontWeight: FontWeight.bold,
                  fontSize: isCurrent ? 16 : 14,
                ),
              ),
      ),
    );
  }

  Widget _buildStepLine(int afterStep, ThemeData theme) {
    final isActive = _currentStep > afterStep;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 40,
      height: 3,
      decoration: BoxDecoration(
        color: isActive ? AppColors.telegramBlue : theme.dividerColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildInputField(ThemeData theme) {
    switch (_currentStep) {
      case 1:
        return AppTextField(
          key: const ValueKey('phone_field'),
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textAlign: TextAlign.left,
          hintText: '+966512345678',
          prefixIcon: const Icon(SolarLinearIcons.phone),
        );

      case 2:
        return AppTextField(
          key: const ValueKey('code_field'),
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          hintText: 'â€¢ â€¢ â€¢ â€¢ â€¢ â€¢',
        );

      case 3:
        return AppTextField(
          key: const ValueKey('password_field'),
          controller: _passwordController,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          textAlign: TextAlign.left,
          hintText: 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
          prefixIcon: const Icon(SolarLinearIcons.lockKeyhole),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHelpItem(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'â€¢',
            style: TextStyle(
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return 'ط£ط¯ط®ظ„ ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ';
      case 2:
        return 'ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚';
      case 3:
        return 'ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ط«ظ†ط§ط¦ظٹط©';
      default:
        return '';
    }
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case 1:
        return 'ط£ط¯ط®ظ„ ط±ظ‚ظ… ظ‡ط§طھظپظƒ ط§ظ„ظ…ط³ط¬ظ„ ظپظٹ Telegram ظ„ط¥ط±ط³ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚';
      case 2:
        return 'طھظ… ط¥ط±ط³ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚ ط¥ظ„ظ‰ طھط·ط¨ظٹظ‚ Telegram ط§ظ„ط®ط§طµ ط¨ظƒ';
      case 3:
        return 'ط­ط³ط§ط¨ظƒ ظ…ط­ظ…ظٹ ط¨ظƒظ„ظ…ط© ظ…ط±ظˆط± ط«ظ†ط§ط¦ظٹط©. ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ظ‡ط§ ظ„ظ„ظ…طھط§ط¨ط¹ط©';
      default:
        return '';
    }
  }

  String _getButtonText() {
    switch (_currentStep) {
      case 1:
        return 'ط¥ط±ط³ط§ظ„ ط±ظ…ط² ط§ظ„طھط­ظ‚ظ‚';
      case 2:
        return 'طھط­ظ‚ظ‚ ظ…ظ† ط§ظ„ط±ظ…ط²';
      case 3:
        return 'طھط£ظƒظٹط¯';
      default:
        return '';
    }
  }

  VoidCallback? _getActionCallback() {
    switch (_currentStep) {
      case 1:
        return _sendCode;
      case 2:
        return _verifyCode;
      case 3:
        return _verifyPassword;
      default:
        return null;
    }
  }
}
