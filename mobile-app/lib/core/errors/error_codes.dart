/// Backend error codes mapped to localized messages
/// 
/// This ensures error messages are localized on the client side
/// rather than relying on backend-transmitted strings.
class AppErrorCodes {
  AppErrorCodes._();

  // Authentication errors
  static const String emailNotVerified = 'EMAIL_NOT_VERIFIED';
  static const String pendingApproval = 'PENDING_APPROVAL';
  static const String accountDeactivated = 'ACCOUNT_DEACTIVATED';
  static const String sessionRevoked = 'SESSION_REVOKED';
  static const String itemNotFound = 'ITEM_NOT_FOUND';
  static const String logoutIncomplete = 'LOGOUT_INCOMPLETE';

  /// Map error code to localized Arabic message
  static String getLocalizedMessage(String? errorCode, String fallbackMessage) {
    switch (errorCode) {
      case emailNotVerified:
        return 'يجب التحقق من البريد الإلكتروني أولاً';
      case pendingApproval:
        return 'حسابك قيد المراجعة. سيتم إعلامك عند الموافقة.';
      case accountDeactivated:
        return 'تم تعطيل الحساب أو انتهاء الاشتراك';
      case sessionRevoked:
        return 'تم إنهاء الجلسة. يرجى تسجيل الدخول مرة أخرى';
      case itemNotFound:
        return 'العنصر غير موجود';
      case logoutIncomplete:
        return 'تعذر تسجيل الخروج بشكل كامل. يرجى المحاولة مرة أخرى.';
      default:
        // If no known code matches, return the backend message as fallback
        return fallbackMessage;
    }
  }
}
