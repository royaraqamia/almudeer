import 'package:flutter/material.dart';
import 'dart:async';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/validators.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/auth/data/models/username_availability.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';

/// Login form widget for existing accounts with email/password
class LoginWithExistingAccount extends StatefulWidget {
  final AuthProvider authProvider;

  const LoginWithExistingAccount({super.key, required this.authProvider});

  @override
  State<LoginWithExistingAccount> createState() =>
      _LoginWithExistingAccountState();
}

class _LoginWithExistingAccountState extends State<LoginWithExistingAccount> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  bool _obscurePassword = true;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  void _validateForm() {
    final emailValid = _emailController.text.trim().isNotEmpty;
    final passwordValid = _passwordController.text.isNotEmpty;
    final isValid = emailValid && passwordValid;
    
    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_validateForm);
    _passwordController.removeListener(_validateForm);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }

    Haptics.mediumTap();
    setState(() => _isLoggingIn = true);

    try {
      final success = await widget.authProvider.loginWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        Navigator.pop(context);
        AnimatedToast.success(context, 'تم تسجيل الدخول بنجاح');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          widget.authProvider.errorMessage ??
              'البريد الإلكتروني أو كلمة المرور غير صحيحة',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _emailController,
          hintText: 'البريد الإلكتروني',
          enabled: !_isLoggingIn,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _passwordController,
          hintText: 'كلمة المرور',
          enabled: !_isLoggingIn,
          obscureText: _obscurePassword,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 24),
        AppGradientButton(
          onPressed: (_isFormValid && !_isLoggingIn) ? _handleLogin : null,
          text: 'تسجيل الدخول',
          isLoading: _isLoggingIn,
          gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
        ),
      ],
    );
  }
}

/// Inline signup form with real-time username validation
class CreateNewAccount extends StatefulWidget {
  const CreateNewAccount({super.key});

  @override
  State<CreateNewAccount> createState() => _CreateNewAccountState();
}

class _CreateNewAccountState extends State<CreateNewAccount> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSigningUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isFormValid = false;
  
  // Username availability state
  UsernameAvailability? _usernameAvailability;
  Timer? _usernameDebounceTimer;
  bool _isCheckingUsername = false;

  @override
  void initState() {
    super.initState();
    _fullNameController.addListener(_validateForm);
    _usernameController.addListener(_onUsernameChanged);
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
    _confirmPasswordController.addListener(_validateForm);
  }

  void _onUsernameChanged() {
    _usernameDebounceTimer?.cancel();
    
    if (_usernameController.text.trim().isEmpty) {
      if (_usernameAvailability != null) {
        setState(() => _usernameAvailability = null);
      }
      return;
    }
    
    _usernameDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability();
    });
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();

    if (username.length < 3) {
      if (mounted) {
        setState(() => _usernameAvailability = null);
      }
      return;
    }

    if (!mounted) return;

    setState(() => _isCheckingUsername = true);

    try {
      // Use AuthProvider instead of creating new AuthRepository
      final authProvider = context.read<AuthProvider>();
      final availability = await authProvider.checkUsernameAvailability(username);

      if (mounted) {
        setState(() {
          _usernameAvailability = availability;
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUsername = false);
      }
    }
  }

  void _validateForm() {
    final fullNameValid = _fullNameController.text.trim().length >= 2;
    final usernameValid = _usernameController.text.trim().length >= 3;
    final emailValid = Validators.email.hasMatch(_emailController.text.trim());
    final passwordResult = Validators.validatePassword(_passwordController.text);
    final passwordValid = passwordResult.isValid;
    final confirmPasswordValid = _confirmPasswordController.text == _passwordController.text &&
        _confirmPasswordController.text.isNotEmpty;

    final usernameAvailable = _usernameAvailability?.available == true;
    final isValid = fullNameValid && usernameValid && usernameAvailable && emailValid && passwordValid && confirmPasswordValid;

    if (isValid != _isFormValid) {
      setState(() => _isFormValid = isValid);
    }
  }

  @override
  void dispose() {
    _usernameDebounceTimer?.cancel();
    _fullNameController.removeListener(_validateForm);
    _usernameController.removeListener(_onUsernameChanged);
    _emailController.removeListener(_validateForm);
    _passwordController.removeListener(_validateForm);
    _confirmPasswordController.removeListener(_validateForm);
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usernameAvailability?.available != true) return;

    final authProvider = context.read<AuthProvider>();
    final sanitizedEmail = Validators.sanitizeInput(_emailController.text);
    final sanitizedUsername = Validators.sanitizeInput(_usernameController.text);

    Haptics.mediumTap();
    setState(() => _isSigningUp = true);

    try {
      final success = await authProvider.signUp(
        sanitizedEmail,
        _passwordController.text,
        _fullNameController.text.trim(),
        sanitizedUsername,
      );

      if (success && mounted) {
        Navigator.pop(context);
        AnimatedToast.success(context, 'تم إنشاء الحساب. يرجى التحقق من بريدك الإلكتروني.');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          authProvider.errorMessage ?? 'فشل في إنشاء الحساب',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningUp = false);
      }
    }
  }

  Widget _buildUsernameStatusIcon() {
    if (_isCheckingUsername) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    
    if (_usernameAvailability != null) {
      if (_usernameAvailability!.available) {
        return const Icon(
          SolarBoldIcons.checkCircle,
          color: AppColors.success,
          size: 20,
        );
      } else {
        return const Icon(
          SolarBoldIcons.dangerCircle,
          color: AppColors.error,
          size: 20,
        );
      }
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildUsernameAvailabilityMessage() {
    if (_usernameController.text.trim().isEmpty || 
        _isCheckingUsername || 
        _usernameController.text.trim().length < 3) {
      return const SizedBox.shrink();
    }
    
    if (_usernameAvailability != null) {
      final isAvailable = _usernameAvailability!.available;
      final color = isAvailable ? AppColors.success : AppColors.error;
      
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _usernameAvailability!.message,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full Name
          AppTextField(
            controller: _fullNameController,
            hintText: 'الاسم الكامل',
            enabled: !_isSigningUp,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'الاسم الكامل مطلوب';
              }
              if (value.trim().length < 2) {
                return 'الاسم يجب أن يكون حرفين على الأقل';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Username
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _usernameController,
                hintText: 'اسم المستخدم',
                enabled: !_isSigningUp,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
                suffixIcon: _buildUsernameStatusIcon(),
                validator: (value) {
                  final result = Validators.validateUsername(value);
                  return result.errorMessage;
                },
              ),
              _buildUsernameAvailabilityMessage(),
            ],
          ),
          const SizedBox(height: 16),
          
          // Email
          AppTextField(
            controller: _emailController,
            hintText: 'البريد الإلكتروني',
            enabled: !_isSigningUp,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (value) {
              final result = Validators.validateEmail(value);
              return result.errorMessage;
            },
          ),
          const SizedBox(height: 16),
          
          // Password
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _passwordController,
                hintText: 'كلمة المرور',
                enabled: !_isSigningUp,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  final result = Validators.validatePassword(value);
                  return result.errorMessage;
                },
              ),
              const SizedBox(height: 16),
              
              // Confirm Password
              AppTextField(
                controller: _confirmPasswordController,
                hintText: 'تأكيد كلمة المرور',
                enabled: !_isSigningUp,
                obscureText: _obscureConfirmPassword,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
                validator: (value) {
                  final result = Validators.validatePasswordConfirmation(value, _passwordController.text);
                  return result.errorMessage;
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Sign Up Button
          AppGradientButton(
            onPressed: (_isFormValid && !_isSigningUp) ? _handleSignUp : null,
            text: 'إنشاء حساب',
            isLoading: _isSigningUp,
            gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
          ),
        ],
      ),
    );
  }
}
