/// Input validation utilities for form fields
///
/// Provides validation for phone, username, and other common fields.
library;

/// Regular expression patterns for validation
class _Patterns {
  _Patterns._();

  /// Phone number pattern (international format, digits, +, -, spaces, parentheses)
  static final RegExp phone = RegExp(r'^[\d\s\-\+\(\)]{8,20}$');

  /// Username pattern (alphanumeric, underscores, 3-30 chars)
  static final RegExp username = RegExp(r'^[a-zA-Z0-9_]{3,30}$');

  /// Name pattern (letters, spaces, hyphens, apostrophes, 2-100 chars)
  static final RegExp name = RegExp(r"^[\p{L}\p{M}'\-\s]{2,100}$", unicode: true);
}

/// Validation result containing success status and error message
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult.valid()
      : isValid = true,
        errorMessage = null;

  const ValidationResult.invalid(this.errorMessage)
      : isValid = false;
}

/// Input validation utilities
class Validators {
  Validators._();

  /// Validate phone number format
  static ValidationResult validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.valid(); // Optional field
    }

    final trimmed = value.trim();
    if (!_Patterns.phone.hasMatch(trimmed)) {
      return const ValidationResult.invalid('رقم الهاتف غير صالح');
    }

    return const ValidationResult.valid();
  }

  /// Validate username format (Almudeer username)
  static ValidationResult validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.valid(); // Optional field
    }

    final trimmed = value.trim().replaceAll('@', '');
    if (trimmed.length < 3) {
      return const ValidationResult.invalid('يجب أن يكون المعرِّف ٣ أحرف على الأقل');
    }

    if (trimmed.length > 30) {
      return const ValidationResult.invalid('يجب ألا يتجاوز المعرِّف ٣٠ حرفاً');
    }

    if (!_Patterns.username.hasMatch(trimmed)) {
      return const ValidationResult.invalid(
        'يجب أن يحتوي المعرِّف على أحرف إنجليزية وأرقام وشرطات سفلية فقط',
      );
    }

    return const ValidationResult.valid();
  }

  /// Validate name format
  static ValidationResult validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.invalid('الاسم مطلوب');
    }

    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return const ValidationResult.invalid('يجب أن يكون الاسم حرفين على الأقل');
    }

    if (trimmed.length > 100) {
      return const ValidationResult.invalid('يجب ألا يتجاوز الاسم ١٠٠ حرف');
    }

    if (!_Patterns.name.hasMatch(trimmed)) {
      return const ValidationResult.invalid('الاسم يحتوي على أحرف غير صالحة');
    }

    return const ValidationResult.valid();
  }

  /// Validate required field
  static ValidationResult validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return ValidationResult.invalid('$fieldName مطلوب');
    }

    return const ValidationResult.valid();
  }

  /// Sanitize username (remove @ and trim)
  static String sanitizeUsername(String username) {
    return username.trim().replaceAll('@', '');
  }

  /// Sanitize phone number (keep only digits, +, -)
  static String sanitizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+\-]'), '');
  }

  /// Special characters allowed in passwords (consistent across all screens)
  static final RegExp _passwordSpecialChar = RegExp(
    r"""[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~]""",
  );

  /// Validate password strength
  ///
  /// Requirements:
  /// - At least 8 characters
  /// - At least one uppercase letter
  /// - At least one lowercase letter
  /// - At least one digit
  /// - At least one special character
  static ValidationResult validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return const ValidationResult.invalid('كلمة المرور مطلوبة');
    }

    if (value.length < 8) {
      return const ValidationResult.invalid('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return const ValidationResult.invalid('يجب أن تحتوي على حرف كبير واحد على الأقل');
    }

    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return const ValidationResult.invalid('يجب أن تحتوي على حرف صغير واحد على الأقل');
    }

    if (!RegExp(r'\d').hasMatch(value)) {
      return const ValidationResult.invalid('يجب أن تحتوي على رقم واحد على الأقل');
    }

    if (!_passwordSpecialChar.hasMatch(value)) {
      return const ValidationResult.invalid('يجب أن تحتوي على رمز خاص واحد على الأقل');
    }

    return const ValidationResult.valid();
  }

  /// Validate password confirmation
  static ValidationResult validatePasswordConfirmation(
    String? value,
    String originalPassword,
  ) {
    if (value == null || value.isEmpty) {
      return const ValidationResult.invalid('تأكيد كلمة المرور مطلوب');
    }

    if (value != originalPassword) {
      return const ValidationResult.invalid('كلمتا المرور غير متطابقتين');
    }

    return const ValidationResult.valid();
  }

  /// Validate email format
  static final RegExp email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Validate email format
  static ValidationResult validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return const ValidationResult.invalid('البريد الإلكتروني مطلوب');
    }

    if (!email.hasMatch(value)) {
      return const ValidationResult.invalid('بريد إلكتروني غير صالح');
    }

    return const ValidationResult.valid();
  }

  /// Sanitize input by trimming and stripping control characters
  static String sanitizeInput(String input) {
    return input.trim().replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');
  }
}
