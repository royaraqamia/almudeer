import 'package:flutter/material.dart';
import 'dart:async';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/auth/data/repositories/auth_repository.dart';
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
    
    final repository = AuthRepository();
    final availability = await repository.checkUsernameAvailability(username);
    
    if (mounted) {
      setState(() {
        _usernameAvailability = availability;
        _isCheckingUsername = false;
      });
    }
  }

  void _validateForm() {
    final fullNameValid = _fullNameController.text.trim().length >= 2;
    final usernameValid = _usernameController.text.trim().length >= 3;
    final emailValid = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(_emailController.text.trim());
    final passwordValid = _passwordController.text.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(_passwordController.text) &&
        RegExp(r'[a-z]').hasMatch(_passwordController.text) &&
        RegExp(r'\d').hasMatch(_passwordController.text) &&
        RegExp(r"""[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~]""").hasMatch(_passwordController.text);
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
    final sanitizedEmail = _emailController.text.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');
    final sanitizedUsername = _usernameController.text.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');

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
                  if (value == null || value.trim().isEmpty) {
                    return 'اسم المستخدم مطلوب';
                  }
                  if (value.trim().length < 3) {
                    return 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل';
                  }
                  if (value.trim().length > 50) {
                    return 'اسم المستخدم يجب أن يكون 50 حرفًا كحد أقصى';
                  }
                  final usernameRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
                  if (!usernameRegex.hasMatch(value.trim())) {
                    return 'اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام وشرطات فقط';
                  }
                  return null;
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
              if (value == null || value.isEmpty) {
                return 'البريد الإلكتروني مطلوب';
              }
              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(value)) {
                return 'بريد إلكتروني غير صالح';
              }
              return null;
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
                  if (value == null || value.isEmpty) {
                    return 'كلمة المرور مطلوبة';
                  }
                  if (value.length < 8) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                  if (!RegExp(r'[A-Z]').hasMatch(value)) return 'يجب أن تحتوي على حرف كبير واحد على الأقل';
                  if (!RegExp(r'[a-z]').hasMatch(value)) return 'يجب أن تحتوي على حرف صغير واحد على الأقل';
                  if (!RegExp(r'\d').hasMatch(value)) return 'يجب أن تحتوي على رقم واحد على الأقل';
                  if (!RegExp(r"""[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~]""").hasMatch(value)) {
                    return 'يجب أن تحتوي على رمز خاص واحد على الأقل';
                  }
                  return null;
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
                  if (value == null || value.isEmpty) {
                    return 'تأكيد كلمة المرور مطلوب';
                  }
                  if (value != _passwordController.text) {
                    return 'كلمتا المرور غير متطابقتين';
                  }
                  return null;
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
