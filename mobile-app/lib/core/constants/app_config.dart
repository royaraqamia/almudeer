/// App configuration constants
///
/// Centralized configuration for the app to avoid hardcoded values
/// scattered throughout the codebase.
class AppConfig {
  // Prevent instantiation
  AppConfig._();

  // ============ Version & Update ============

  /// Default APK download URL (fallback if server doesn't provide one)
  static const String defaultDownloadUrl =
      'https://almudeer.royaraqamia.com/download/almudeer.apk';

  /// Cache duration for version check results
  /// Short duration ensures updates are detected quickly
  static const Duration versionCheckCacheDuration = Duration(minutes: 5);

  /// SharedPreferences key for cached version check
  static const String versionCheckCacheKey = 'version_check_cache';

  /// SharedPreferences key for cache timestamp
  static const String versionCheckCacheTimeKey = 'version_check_cache_time';

  /// SharedPreferences key for last background check timestamp
  static const String lastBackgroundCheckKey = 'last_background_check_time';

  /// Interval for background version checks (every 24 hours)
  static const Duration backgroundCheckInterval = Duration(hours: 24);

  /// Minimum interval between version checks on app resume
  /// Prevents checking too frequently which wastes battery/data
  static const Duration minimumCheckInterval = Duration(hours: 4);
  static const String lastVersionCheckKey = 'last_version_check_time';

  /// Maximum number of times user can defer a soft update
  /// After this limit, update becomes mandatory
  static const int maxUpdateDefers = 3;
  static const String updateDeferCountKey = 'update_defer_count';
  static const String updateDeferVersionKey = 'update_defer_version';

  /// Smart update timing - delay before showing update dialog
  /// Allows user to interact with app first before interrupting
  static const Duration updateDialogDelay = Duration(seconds: 3);

  /// Expected SHA256 Signature Hash of the APK signing certificate
  /// This should be updated when the signing key changes
  static const String apkSigningSignature =
      'D9D4B8F1E4A05ED554E65D645482B96BDBC372F959356C4E9FB479B9D07039C3';

  // ============ Download & Retry ============

  /// Maximum retry attempts for SHA256 verification failures
  /// Prevents infinite loops on corrupted APK or MITM attacks
  static const int maxShaRetries = 1;

  /// SharedPreferences key for SHA256 retry count
  static const String shaRetryCountKey = 'sha256_retry_count';

  /// Maximum auto-retry attempts for background downloads
  static const int maxAutoDownloadRetries = 3;

  /// Delay between auto-retry attempts for background downloads
  static const Duration downloadRetryDelay = Duration(minutes: 5);

  /// SharedPreferences key for background download retry count
  static const String bgDownloadRetryCountKey = 'bg_download_retry_count';

  /// Battery threshold percentage for background downloads
  /// Downloads pause when battery is below this level
  static const int batteryThreshold = 20;

  /// Persistence interval for download progress (reduce I/O on slow devices)
  static const Duration downloadPersistenceInterval = Duration(seconds: 30);

  /// Download connection timeout
  static const Duration downloadConnectTimeout = Duration(seconds: 30);

  /// Download receive timeout
  static const Duration downloadReceiveTimeout = Duration(minutes: 10);

  // ============ Cache & Offline ============

  /// Maximum age for cached update_required state (works offline)
  static const Duration updateRequiredCacheMaxAge = Duration(days: 7);

  /// SharedPreferences key for cached update required state
  static const String updateRequiredCacheKey = 'update_required_cached';

  /// SharedPreferences key for update required cache timestamp
  static const String updateRequiredTimeKey = 'update_required_time';

  /// ETag cache TTL (seconds) - should match backend _ETAG_CACHE_TTL
  static const int etagCacheTtl = 60;

  // ============ Background Tasks ============

  /// Notification cooldown hours for background update checks
  /// Reduced from 24h to 6h for better critical update awareness
  static const int updateNotificationCooldownHours = 6;
  
  /// Cooldown for critical priority updates (more frequent reminders)
  static const int criticalUpdateNotificationCooldownHours = 2;

  /// Max failed checks before showing critical alert
  static const int maxFailedChecksBeforeAlert = 3;

  /// Initial delay for background update task
  static const Duration backgroundTaskInitialDelay = Duration(minutes: 15);

  /// Backoff delay for failed background tasks
  static const Duration backgroundTaskBackoffDelay = Duration(minutes: 30);

  // ============ Version Check Timeouts ============

  /// Timeout for version check on WiFi
  /// LAG FIX #2: Increased from 15s to 20s for better reliability
  static const Duration versionCheckWifiTimeout = Duration(seconds: 20);

  /// Timeout for version check on mobile data (longer for slow connections)
  /// LAG FIX #2: Increased from 30s to 45s for 2G/3G networks
  static const Duration versionCheckMobileTimeout = Duration(seconds: 45);

  /// Default version check timeout (fallback)
  static const Duration versionCheckDefaultTimeout = Duration(seconds: 30);

  /// Maximum timeout for background startup checks
  static const Duration backgroundCheckTimeout = Duration(seconds: 60);

  // ============ Legal & External ============

  /// Privacy Policy URL
  static const String privacyPolicyUrl =
      'https://royaraqamia.com/almudeeralraqami/privacy';

  /// Terms of Service URL
  static const String termsOfServiceUrl =
      'https://royaraqamia.com/almudeeralraqami/terms';

  // ============ API ============

  /// Request timeout duration
  static const Duration requestTimeout = Duration(seconds: 30);

  // ============ Animation durations ============

  /// Animation durations
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration normalAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);

  // ============ Deep Links & QR ============

  /// Deep link scheme used for internal app navigation
  /// Must match AndroidManifest and iOS URL Schemes
  static const String deepLinkScheme = 'almudeer';

  /// Allowed URL schemes for QR code URL handling
  static const List<String> allowedUrlSchemes = ['http', 'https'];

  /// Maximum URL length to prevent malformed QR codes
  static const int maxQrUrlLength = 2048;

  /// Maximum data length for QR code generation (practical limit for scannability)
  static const int maxQrDataLength = 500;

  /// Hive box name for QR scanner history
  static const String qrHistoryBoxName = 'qr_scanner_history';

  /// SharedPreferences key for QR flash state
  static const String qrFlashEnabledKey = 'qr_flash_enabled';

  /// Default QR code size in pixels
  static const double defaultQrCodeSize = 200;

  /// QR code debounce duration to prevent duplicate scans
  static const Duration qrScanDebounceDuration = Duration(seconds: 2);
}
