/// P3-22: Simple i18n utility for auth error messages
/// Provides English fallback when Arabic is not available
library;

/// Auth-related localized strings
class AuthStrings {
  AuthStrings._();

  /// Get localized string with English fallback
  static String t(String arabic, String english) {
    // In the future, this can be extended to check device locale
    // For now, always return Arabic (primary language) with English as documented fallback
    return arabic;
  }

  // Login
  static String get loginButton => t('تسجيل الدخول', 'Login');
  static String get loginTitle => t('تسجيل الدخول', 'Sign In');
  static String get loginSubtitle => t('أدخل بريدك الإلكتروني وكلمة المرور', 'Enter your email and password');
  static String get emailRequired => t('البريد الإلكتروني مطلوب', 'Email is required');
  static String get invalidEmail => t('بريد إلكتروني غير صالح', 'Invalid email address');
  static String get passwordRequired => t('كلمة المرور مطلوبة', 'Password is required');
  static String get wrongCredentials => t('البريد الإلكتروني أو كلمة المرور غير صحيحة', 'Invalid email or password');
  static String get loggingIn => t('جاري الدخول...', 'Signing in...');
  static String get forgotPassword => t('نسيت كلمة المرور؟', 'Forgot password?');
  static String get noAccount => t('ليس لديك حساب؟ إنشاء حساب جديد', "Don't have an account? Sign up");

  // Signup
  static String get signupTitle => t('إنشاء حساب جديد', 'Create Account');
  static String get fullName => t('الاسم الكامل', 'Full Name');
  static String get fullNameRequired => t('الاسم الكامل مطلوب', 'Full name is required');
  static String get passwordTooShort => t('كلمة المرور يجب أن تكون 8 أحرف على الأقل', 'Password must be at least 8 characters');
  static String get passwordNeedsUppercase => t('كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل', 'Password must contain at least one uppercase letter');
  static String get passwordNeedsLowercase => t('كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل', 'Password must contain at least one lowercase letter');
  static String get passwordNeedsDigit => t('كلمة المرور يجب أن تحتوي على رقم واحد على الأقل', 'Password must contain at least one digit');
  static String get passwordNeedsSpecial => t('كلمة المرور يجب أن تحتوي على رمز خاص واحد على الأقل (!@#\$%^&*)', 'Password must contain at least one special character (!@#\$%^&*)');
  static String get emailAlreadyRegistered => t('البريد الإلكتروني مسجل بالفعل', 'Email is already registered');
  static String get accountCreated => t('تم إنشاء الحساب. يرجى التحقق من بريدك الإلكتروني لرمز التحقق.', 'Account created. Please check your email for verification code.');

  // OTP
  static String get otpVerification => t('التحقق من البريد الإلكتروني', 'Email Verification');
  static String get enterOtp => t('أدخل رمز التحقق المكون من 6 أرقام', 'Enter the 6-digit verification code');
  static String get wrongOtp => t('رمز التحقق غير صحيح', 'Incorrect verification code');
  static String get otpExpired => t('انتهت صلاحية رمز التحقق. يرجى طلب رمز جديد', 'Verification code expired. Please request a new one');
  static String get maxAttemptsReached => t('تم تجاوز الحد الأقصى من المحاولات. يرجى طلب رمز جديد', 'Maximum attempts reached. Please request a new code');
  static String get resendOtp => t('إعادة إرسال الرمز', 'Resend code');
  static String get resendCooldown => t('يرجى الانتظار', 'Please wait');

  // Rate limiting
  static String get accountLocked => t('تم حظر الحساب مؤقتاً', 'Account temporarily locked');
  static String tryAgainMinutes(int minutes) => t('حاول مرة أخرى بعد $minutes دقائق', 'Try again in $minutes minutes');
  static String tryAgainSeconds(int seconds) => t('حاول مرة أخرى بعد $seconds ثانية', 'Try again in $seconds seconds');

  // Password reset
  static String get forgotPasswordTitle => t('نسيت كلمة المرور', 'Forgot Password');
  static String get resetPasswordTitle => t('إعادة تعيين كلمة المرور', 'Reset Password');
  static String get resetEmailSent => t('إذا كان البريد الإلكتروني مسجلاً، ستتلقى رابط إعادة تعيين كلمة المرور.', 'If the email is registered, you will receive a password reset link.');
  static String get newPassword => t('كلمة المرور الجديدة', 'New Password');
  static String get confirmPassword => t('تأكيد كلمة المرور', 'Confirm Password');
  static String get passwordsNotMatch => t('كلمتا المرور غير متطابقتين', 'Passwords do not match');
  static String get passwordResetSuccess => t('تم إعادة تعيين كلمة المرور بنجاح. يمكنك تسجيل الدخول الآن.', 'Password reset successfully. You can now sign in.');

  // Approval
  static String get pendingApproval => t('حسابك قيد المراجعة', 'Your account is under review');
  static String get waitingApproval => t('في انتظار الموافقة', 'Waiting for Approval');

  // Errors
  static String get networkError => t('تعذر الاتصال بالخادم. تأكد من اتصالك بالإنترنت وحاول مجدداً', 'Unable to connect to server. Check your internet connection and try again.');
  static String get connectionError => t('تعذر الاتصال', 'Connection error');
  static String get genericError => t('حدث خطأ غير متوقع', 'An unexpected error occurred');
}
