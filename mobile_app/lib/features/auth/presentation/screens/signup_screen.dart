import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'dart:async';
import 'package:almudeer_mobile_app/core/app/routes.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'package:almudeer_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:almudeer_mobile_app/features/auth/data/models/username_availability.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/utils/validators.dart';

/// Sign Up screen with email, password, and full name validation
///
/// Flow:
/// 1. User enters full name, email, password
/// 2. Validates all fields
/// 3. Calls /api/auth/signup
/// 4. Navigates to OTP verification screen
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
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
    // Cancel previous timer
    _usernameDebounceTimer?.cancel();
    
    // Clear availability when field is empty
    if (_usernameController.text.trim().isEmpty) {
      if (_usernameAvailability != null) {
        setState(() {
          _usernameAvailability = null;
        });
      }
      return;
    }
    
    // Debounce: wait 500ms before checking
    _usernameDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability();
    });
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();

    // Skip if empty or too short
    if (username.length < 3) {
      if (mounted) {
        setState(() {
          _usernameAvailability = null;
        });
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _isCheckingUsername = true;
    });

    try {
      // Use AuthProvider's repository instead of creating new instance
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
        setState(() {
          _isCheckingUsername = false;
        });
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

    // Username is valid only if format is valid AND it's available
    final usernameAvailable = _usernameAvailability?.available == true;
    final isValid = fullNameValid && usernameValid && usernameAvailable && emailValid && passwordValid && confirmPasswordValid;

    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
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
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    // Sanitize email and username input
    final sanitizedEmail = Validators.sanitizeInput(_emailController.text);
    final sanitizedUsername = Validators.sanitizeInput(_usernameController.text);

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signUp(
      sanitizedEmail,
      _passwordController.text,
      _fullNameController.text.trim(),
      sanitizedUsername,
    );

    if (!mounted) return;

    if (success) {
      Haptics.mediumTap();
      // Navigate to OTP verification
      Navigator.of(context).pushNamed(
        AppRoutes.otpVerification,
        arguments: {'email': sanitizedEmail},
      );
    }
  }

  Widget _buildUsernameStatusIcon() {
    // Show loading spinner while checking
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
    
    // Show status icon if we have availability data
    if (_usernameAvailability != null) {
      if (_usernameAvailability!.available) {
        return const Icon(
          SolarBoldIcons.checkCircle,
          color: AppColors.success,
          size: 20,
        );
      } else {
        // Username is taken or invalid format
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
    // Don't show anything if field is empty or checking is in progress
    if (_usernameController.text.trim().isEmpty || _isCheckingUsername) {
      return const SizedBox.shrink();
    }
    
    // Don't show if username is too short
    if (_usernameController.text.trim().length < 3) {
      return const SizedBox.shrink();
    }
    
    // Show message if we have availability data
    if (_usernameAvailability != null) {
      final isAvailable = _usernameAvailability!.available;
      final color = isAvailable ? AppColors.success : AppColors.error;
      
      return Padding(
        padding: const EdgeInsets.only(top: 8, right: 12),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TapRegion(
      onTapOutside: (_) => _focusNode.unfocus(),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              SolarLinearIcons.arrowRight,
              color: theme.colorScheme.primary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingLarge,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppDimensions.spacing32),

                  // Title
                  Text(
                    'إنشاء حساب جديد',
                    style: TextStyle(
                      fontSize: AppDimensions.loginTitleSize,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.headlineSmall?.color,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // Full Name Input
                  AppTextField(
                    controller: _fullNameController,
                    focusNode: _focusNode,
                    hintText: 'الاسم الكامل',
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الاسم الكامل مطلوب';
                      }
                      final result = Validators.validateName(value);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Username Input
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        controller: _usernameController,
                        focusNode: _focusNode,
                        hintText: 'اسم المستخدم',
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLines: 1,
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
                          // Validate alphanumeric, underscores, and hyphens only
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
                  const SizedBox(height: AppDimensions.spacing16),

                  // Email Input
                  AppTextField(
                    controller: _emailController,
                    focusNode: _focusNode,
                    hintText: 'البريد الإلكتروني',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    validator: (value) {
                      final result = Validators.validateEmail(value);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Password Input
                  AppTextField(
                    controller: _passwordController,
                    focusNode: _focusNode,
                    hintText: 'كلمة المرور',
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showPassword,
                    enableInteractiveSelection: false, // P1-8 FIX
                    maxLines: 1,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? SolarLinearIcons.eye
                            : SolarLinearIcons.eyeClosed,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showPassword = !_showPassword;
                        });
                      },
                    ),
                    validator: (value) {
                      final result = Validators.validatePassword(value);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Confirm Password Input
                  AppTextField(
                    controller: _confirmPasswordController,
                    focusNode: _focusNode,
                    hintText: 'تأكيد كلمة المرور',
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showConfirmPassword,
                    enableInteractiveSelection: false,
                    maxLines: 1,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirmPassword
                            ? SolarLinearIcons.eye
                            : SolarLinearIcons.eyeClosed,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showConfirmPassword = !_showConfirmPassword;
                        });
                      },
                    ),
                    validator: (value) {
                      final result = Validators.validatePasswordConfirmation(value, _passwordController.text);
                      return result.errorMessage;
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing32),

                  // Error Message
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.errorMessage == null) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppDimensions.errorPadding),
                        margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
                        decoration: ShapeDecoration(
                          color: isDark
                              ? AppColors.errorDark.withValues(alpha: 0.20)
                              : AppColors.errorLight.withValues(alpha: 0.20),
                          shape: SmoothRectangleBorder(
                            borderRadius: SmoothBorderRadius(
                              cornerRadius: AppDimensions.radiusLarge,
                              cornerSmoothing: 1.0,
                            ),
                            side: BorderSide(
                              color: isDark
                                  ? AppColors.errorDark.withValues(alpha: 0.6)
                                  : AppColors.error.withValues(alpha: 0.4),
                              width: 1.0,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              SolarLinearIcons.dangerCircle,
                              color: isDark ? AppColors.errorDark : AppColors.error,
                              size: AppDimensions.errorIconSize,
                            ),
                            const SizedBox(width: AppDimensions.errorIconMarginEnd),
                            Expanded(
                              child: Text(
                                auth.errorMessage!,
                                style: TextStyle(
                                  color: isDark ? AppColors.errorDark : AppColors.error,
                                  fontSize: AppDimensions.loginErrorSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Sign Up Button
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return AppGradientButton(
                        text: auth.isLoading ? 'جاري الإنشاء...' : 'إنشاء حساب',
                        onPressed: (auth.isLoading || !_isFormValid) ? null : _handleSignUp,
                        isLoading: auth.isLoading,
                        gradientColors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                        showShadow: true,
                      );
                    },
                  ),
                  const SizedBox(height: AppDimensions.spacing16),

                  // Already have account? Login
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'لديك حساب بالفعل؟ تسجيل الدخول',
                        style: TextStyle(
                          fontSize: AppDimensions.loginHintSize,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
