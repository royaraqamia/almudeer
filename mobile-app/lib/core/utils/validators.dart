/// Input validation utilities for form fields
///
/// Provides validation for email, phone, username, and other common fields.
library;

/// Regular expression patterns for validation
class _Patterns {
  _Patterns._();

  /// Email validation pattern (RFC 5322 simplified)
  static final RegExp email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

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

  /// Validate email format
  static ValidationResult validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.valid(); // Optional field
    }

    final trimmed = value.trim().toLowerCase();
    if (!_Patterns.email.hasMatch(trimmed)) {
      return const ValidationResult.invalid('البريد الإلكتروني غير صالح');
    }

    return const ValidationResult.valid();
  }

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

  /// Sanitize email (trim and lowercase)
  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase();
  }
}
