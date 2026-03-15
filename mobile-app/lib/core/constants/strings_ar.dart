/// Arabic strings for the Al-Mudeer app
class AppStrings {
  // Prevent instantiation
  AppStrings._();

  // App Info
  static const String appName = 'المدير';
  static const String appNameEn = 'Al-Mudeer';
  static const String appTagline = 'المدير: إدارة ذكيَّة لحياتك الرَّقميَّة';

  // Navigation
  static const String navInbox = 'المحادثات';
  static const String navIntegrations = 'الربط';
  static const String navSettings = 'الإعدادات';

  // Login Screen
  static const String loginTitle = 'تسجيل الدُّخول';
  static const String licenseKeyLabel = 'مفتاح الاشتراك';
  static const String licenseKeyPlaceholder =
      'MUDEER-XXXXXXXX-XXXXXXXX-XXXXXXXX';
  static const String loginButton = 'تسجيل الدُّخول';
  static const String loggingIn = 'نرحب بعودتك.. جاري الدخول';
  static const String getKeyViaWhatsApp = 'احصل على مفتاحك عبر واتساب';
  static const String privacyPolicy = 'سياسة الخصوصيَّة';
  static const String termsOfService = 'شروط الخدمة';
  static const String savedAccounts = 'الحسابات المحفوظة';
  static const String switchAccount = 'تبديل الحساب';
  static const String addNewAccount = 'إضافة حساب جديد';
  static const String removeAccount = 'حذف الحساب';
  static const String confirmRemoveAccount = 'هل أنت متأكد من حذف هذا الحساب؟';
  static const String showAllAccounts = 'إظهار الكل';
  static const String showLessAccounts = 'إظهار أقل';
  static const String longPressToRemove = 'اضغط مطولاً للحذف';
  static const String loginSubtitle = 'أدخِل مفتاح الاشتراك للمتابعة';
  static const String activeAccount = 'الحساب النشط';
  static const String licenseKeyFormatHint = 'التنسيق: MUDEER-XXXX-XXXX-XXXX';
  static const String loginEmptyStateHint = 'احصل على مفتاحك عبر واتساب للبدء';
  static const String or = 'أو';
  static const String rateLimitWarning =
      'لحماية حسابك، يرجى الانتظار قليلًا قبل المحاولة مجددًا';
  static const String pasteFromClipboard = 'لصق من الحافظة';
  static const String clear = 'مسح';

  // Login Errors - Apple HIG: Clear, actionable, not alarming
  static const String errorLicenseRequired =
      'فضلًا، أدخِل مفتاح الاشتراك للبدء';
  static const String errorInvalidFormat =
      'التنسيق غير صحيح. تأكد من إدخاله بالشكل: MUDEER-XXXX-...';
  static const String errorInvalidKey =
      'المفتاح غير صالح. تحقَّق من صحة المفتاح أو تواصل معنا للمساعدة';
  static const String errorConnectionFailed =
      'تعذَّر الاتصال.. يرجى التحقُّق من الإنترنت، جزاك الله خيرًا';
  static const String errorRateLimited =
      'لحماية حسابك، يرجى الانتظار {minutes} دقيقة قبل المحاولة مجددًا';

  // Inbox Screen
  static const String inboxTitle = 'المحادثات';
  static const String allChannels = 'الكل';
  static const String filterPending = 'قيد الانتظار';
  static const String filterSent = 'تم الإرسال';
  static const String filterIgnored = 'تم التجاهل';
  static const String noMessages =
      'صندوقك بانتظار الخير.. لا توجد رسائل حاليًا';
  static const String noMessagesDescription =
      'بانتظار رسائلك القادمة.. يومك سعيد ومبارك';
  static const String pullToRefresh = 'اسحب للتحديث';
  static const String loading = 'جاري التحميل...';
  static const String searchConversations = 'بحث في المحادثات...';
  static const String noSearchResults = 'لا توجد نتائج. جرّب كلمات مفتاحية أخرى'; // Apple HIG: More helpful

  // Message Status
  static const String statusPending = 'قيد الانتظار';
  static const String statusAnalyzed = 'بانتظار مراجعتك';
  static const String statusApproved = 'تمت الموافقة';
  static const String statusIgnored = 'تم التجاهل';
  static const String statusAutoReplied = 'تم الإرسال تلقائيًا';
  static const String statusSent = 'تم الإرسال';

  // Message Actions
  static const String edit = 'تعديل';
  static const String send = 'إرسال';

  // Conversation
  static const String typeMessage = 'اكتب رسالة...';
  static const String voiceMessage = 'رسالة صوتية';
  static const String today = 'اليوم';
  static const String yesterday = 'أمس';

  // Channel Names
  static const String channelWhatsApp = 'واتساب';
  static const String channelTelegram = 'تيليجرام';

  // Customers Screen
  static const String customersTitle = 'النَّاس';
  static const String searchCustomers = 'بحث عن شخص...';
  static const String noCustomers = 'لا يوجد ناس';
  static const String noCustomersDescription =
      'سيظهر النَّاس هنا عند بدء المحادثات';
  static const String vip = 'مميز';
  static const String lastContact = 'آخر تواصل';
  static const String totalMessagesCount = 'عدد الرسائل';
  static const String sentimentScore = 'مؤشر الرضا';
  static const String leadScore = 'مؤشر الاهتمام';
  static const String tags = 'التصنيفات';
  static const String notes = 'ملاحظات';

  // Integrations Screen
  static const String integrationsTitle = 'الربط';
  static const String connectedAccounts = 'الحسابات المتصلة';
  static const String addIntegration = 'إضافة ربط جديد';
  static const String whatsappBusiness = 'واتساب للأعمال';
  static const String telegramBot = 'بوت تيليجرام';
  static const String connected = 'متصل';
  static const String disconnected = 'غير متصل';
  static const String disconnect = 'قطع الاتصال';
  static const String connect = 'اتصال';

  // Settings Screen
  static const String settingsTitle = 'الإعدادات';
  static const String appearance = 'المظهر';
  static const String darkTheme = 'داكن';
  static const String responseTone = 'نبرة الردود';
  static const String toneFormal = 'رسمي';
  static const String toneFriendly = 'ودي';
  static const String toneProfessional = 'مهني';
  static const String subscription = 'الاشتراك';
  static const String expiresAt = 'ينتهي في';
  static const String requestsRemaining = 'الطلبات المتبقية';
  static const String logout = 'تسجيل الخروج';
  static const String logoutConfirmTitle = 'تسجيل الخروج';
  static const String logoutConfirmMessage =
      'هل أنت متأكد من مغادرتنا؟ سنفتقدك، وستحتاج لمفتاح الترخيص عند العودة.';
  static const String confirm = 'تأكيد';
  static const String cancel = 'إلغاء';

  // Common
  static const String save = 'حفظ';
  static const String delete = 'حذف';
  static const String close = 'إغلاق';
  static const String retry = 'إعادة المحاولة';
  static const String error = 'خطأ';
  static const String success = 'نجاح';
  static const String ok = 'حسنًا';
  static const String yes = 'نعم';
  static const String no = 'لا';

  // Empty States
  static const String noData = 'لا توجد بيانات';
  static const String emptyInbox = 'صندوق الرسائل فارغ';
  static const String noConnectedChannels = 'لا توجد حسابات متصلة';
  static const String connectChannelPrompt = 'قم بربط واتساب أو تيليجرام للبدء';

  // Errors - Apple HIG: User-friendly, actionable
  static const String errorGeneric = 'حدث خطأ. يرجى المحاولة مرة أخرى';
  static const String errorNetwork = 'خطأ في الاتصال. تحقَّق من اتصالك بالإنترنت';
  static const String errorTimeout = 'انتهت مهلة الطلب. يرجى المحاولة مرة أخرى';
  static const String errorAuth =
      'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى';

  // Islamic Finance
  static const String qardAlHasan = 'قرض حسن';
}
