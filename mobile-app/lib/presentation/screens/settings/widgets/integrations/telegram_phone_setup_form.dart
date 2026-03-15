import 'dart:async';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/constants/dimensions.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../core/widgets/app_gradient_button.dart';
import '../../../../../data/repositories/integrations_repository.dart';

class TelegramPhoneSetupForm extends StatefulWidget {
  final VoidCallback onComplete;
  final Function(String)? onError;

  const TelegramPhoneSetupForm({
    super.key,
    required this.onComplete,
    this.onError,
  });

  @override
  State<TelegramPhoneSetupForm> createState() => _TelegramPhoneSetupFormState();
}

class _TelegramPhoneSetupFormState extends State<TelegramPhoneSetupForm> {
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
      setState(() => _errorMessage = 'يرجى إدخال رقم الهاتف');
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
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
        widget.onError?.call(_errorMessage!);
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رمز التحقق');
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
        widget.onComplete();
      }
    } catch (e) {
      final errorMsg = e.toString();

      // Check for 2FA error
      if (errorMsg.contains('2FA') || errorMsg.contains('كلمة المرور')) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _currentStep = 3;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = errorMsg.replaceAll('Exception:', '').trim();
          });
          widget.onError?.call(_errorMessage!);
        }
      }
    }
  }

  Future<void> _verifyPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كلمة المرور');
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
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
        widget.onError?.call(_errorMessage!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step indicator
          _buildStepIndicator(theme),
          const SizedBox(height: AppDimensions.spacing24),

          // Icon
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.telegramBlue.withValues(alpha: 0.2),
                    AppColors.telegramBlue.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
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
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacing16),

          // Title
          Text(
            _getStepTitle(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.telegramBlue,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimensions.spacing8),

          // Subtitle
          Text(
            _getStepSubtitle(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimensions.spacing24),

          // Input field
          _buildInputField(theme),
          const SizedBox(height: AppDimensions.spacing16),

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
            const SizedBox(height: AppDimensions.spacing16),
          ],

          // Help text for step 1
          if (_currentStep == 1) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: ShapeDecoration(
                color: theme.cardColor.withValues(alpha: 0.5),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusLarge,
                    cornerSmoothing: 1.0,
                  ),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
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
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ملاحظات هامة',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.telegramBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildHelpItem(
                    'أدخل الرقم مع الرمز الدولي (مثال: +966)',
                    theme,
                  ),
                  _buildHelpItem(
                    'سيتم إرسال رمز التحقق إلى تطبيق Telegram',
                    theme,
                  ),
                  _buildHelpItem(
                    'تأكد من تثبيت تطبيق Telegram على هاتفك',
                    theme,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacing24),
          ],

          // Action button
          SizedBox(
            width: double.infinity,
            child: AppGradientButton(
              onPressed: _isLoading ? null : _getActionCallback(),
              text: _getButtonText(),
              gradientColors: const [
                AppColors.telegramBlue,
                Color(0xFF0891B2),
              ],
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
      width: isCurrent ? 32 : 28,
      height: isCurrent ? 32 : 28,
      decoration: BoxDecoration(
        color: isActive ? AppColors.telegramBlue : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.telegramBlue : theme.dividerColor,
          width: 2,
        ),
      ),
      child: Center(
        child: step < _currentStep
            ? const Icon(
                SolarLinearIcons.checkCircle,
                color: Colors.white,
                size: 14,
              )
            : Text(
                '$step',
                style: TextStyle(
                  color: isActive ? Colors.white : theme.hintColor,
                  fontWeight: FontWeight.bold,
                  fontSize: isCurrent ? 14 : 12,
                ),
              ),
      ),
    );
  }

  Widget _buildStepLine(int afterStep, ThemeData theme) {
    final isActive = _currentStep > afterStep;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 32,
      height: 2,
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
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textAlign: TextAlign.left,
          hintText: '+966512345678',
          prefixIcon: const Icon(SolarLinearIcons.phone),
        );

      case 2:
        return AppTextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          hintText: '• • • • • •',
        );

      case 3:
        return AppTextField(
          controller: _passwordController,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          textAlign: TextAlign.left,
          hintText: '••••••••',
          prefixIcon: const Icon(SolarLinearIcons.lockKeyhole),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHelpItem(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: TextStyle(
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                height: 1.4,
                fontSize: 11,
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
        return 'أدخل رقم الهاتف';
      case 2:
        return 'رمز التحقق';
      case 3:
        return 'كلمة المرور الثنائية';
      default:
        return '';
    }
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case 1:
        return 'أدخل رقم هاتفك المسجل في Telegram';
      case 2:
        return 'تم إرسال الرمز إلى تطبيق Telegram';
      case 3:
        return 'حسابك محمي بكلمة مرور ثنائية';
      default:
        return '';
    }
  }

  String _getButtonText() {
    switch (_currentStep) {
      case 1:
        return 'إرسال رمز التحقق';
      case 2:
        return 'تحقق من الرمز';
      case 3:
        return 'تأكيد';
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
