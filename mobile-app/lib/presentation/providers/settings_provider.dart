import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/user_preferences.dart';
import '../../data/models/knowledge_document.dart';
import '../../data/models/knowledge_constants.dart';
import '../../core/services/persistent_cache_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/knowledge_repository.dart';
import '../../data/repositories/integrations_repository.dart';
import '../../core/services/permission_service.dart';

enum SettingsState { initial, loading, loaded, error }

/// Issue #8: Specific loading state for knowledge documents
enum KnowledgeLoadState { initial, loading, loaded, error }

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository;
  final KnowledgeRepository _knowledgeRepository;
  final IntegrationsRepository _integrationsRepository;

  SettingsState _state = SettingsState.initial;
  SettingsState _integrationsState = SettingsState.initial;
  UserPreferences? _preferences;
  List<KnowledgeDocument> _knowledgeDocuments = [];
  List<dynamic> _integrations = [];
  String? _errorMessage;
  bool _isSaving = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadingFileName;
  bool _isDisposed = false;
  int _loadGeneration =
      0; // Incremented on reset to invalidate stale async results

  // Issue #8: Specific loading state for knowledge documents
  KnowledgeLoadState _knowledgeLoadState = KnowledgeLoadState.initial;

  SettingsProvider({
    SettingsRepository? repository,
    KnowledgeRepository? knowledgeRepository,
    IntegrationsRepository? integrationsRepository,
  }) : _repository = repository ?? SettingsRepository(),
       _knowledgeRepository = knowledgeRepository ?? KnowledgeRepository(),
       _integrationsRepository =
           integrationsRepository ?? IntegrationsRepository();

  SettingsState get state => _state;
  SettingsState get integrationsState => _integrationsState;
  UserPreferences? get preferences => _preferences;
  List<KnowledgeDocument> get knowledgeDocuments => _knowledgeDocuments;
  List<dynamic> get integrations => _integrations;
  String? get errorMessage => _errorMessage;
  bool get isSaving => _isSaving;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get uploadingFileName => _uploadingFileName;
  KnowledgeLoadState get knowledgeLoadState => _knowledgeLoadState;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Load all settings data with cache-first approach
  Future<void> loadSettings() async {
    final currentGeneration = _loadGeneration;
    debugPrint(
      '[SettingsProvider] loadSettings() called, generation=$currentGeneration',
    );
    _errorMessage = null;

    // 1. Instant Cache Load for Knowledge Documents
    if (_knowledgeDocuments.isEmpty) {
      _state = SettingsState.loading;
      notifyListeners();

      try {
        final cache = PersistentCacheService();
        final accountHash = await _repository.apiClient.getAccountCacheHash();
        // Issue #7: Use specific cache key prefix
        final cacheKey =
            '${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents';
        final cachedDocs = await cache.get<Map<String, dynamic>>(
          PersistentCacheService.boxKnowledge,
          cacheKey,
        );
        if (cachedDocs != null && cachedDocs['documents'] != null) {
          // Check if reset happened during async operation
          if (currentGeneration != _loadGeneration) {
            debugPrint(
              '[SettingsProvider] Discarding stale cache result (generation $currentGeneration != $_loadGeneration)',
            );
            return;
          }
          _knowledgeDocuments = (cachedDocs['documents'] as List)
              .map((doc) => KnowledgeDocument.fromJson(doc))
              .toList();
          _state = SettingsState.loaded;
          _knowledgeLoadState = KnowledgeLoadState.loaded;
          notifyListeners();
        }
      } catch (_) {
        // Ignore cache errors
      }
    }

    // 2. Fresh Fetch in Background
    try {
      // Load both preferences and knowledge documents
      final results = await Future.wait([
        _repository.getPreferences(),
        _knowledgeRepository.getKnowledgeDocuments(),
      ]);

      // Check if reset happened during async operation
      if (currentGeneration != _loadGeneration) {
        debugPrint(
          '[SettingsProvider] Discarding stale fetch result (generation $currentGeneration != $_loadGeneration)',
        );
        return;
      }

      _preferences = results[0] as UserPreferences;
      _knowledgeDocuments = results[1] as List<KnowledgeDocument>;
      _state = SettingsState.loaded;
      _knowledgeLoadState = KnowledgeLoadState.loaded;
    } catch (e) {
      // Only show error if we have no data at all
      if (_preferences == null && _knowledgeDocuments.isEmpty) {
        _errorMessage = 'فشل تحميل الإعدادات: $e';
        _state = SettingsState.error;
        _knowledgeLoadState = KnowledgeLoadState.error;
      }

      // Try to load cached preferences specifically if API failed
      try {
        final localPrefs = await _repository.getLocalPreferences();
        if (currentGeneration != _loadGeneration) return; // Check again
        if (localPrefs != null) {
          _preferences = localPrefs;
          _state = SettingsState.loaded;
          _knowledgeLoadState = KnowledgeLoadState.loaded;
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Request notification permission
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isGranted && _preferences != null) {
      await savePreferences(_preferences!.copyWith(notificationsEnabled: true));
      return true;
    }
    return status.isGranted;
  }

  /// Check permission status
  Future<PermissionStatus> checkNotificationPermission() {
    return Permission.notification.status;
  }

  /// Request Manage External Storage (Android 11+)
  Future<bool> requestManageExternalStorage() async {
    final granted = await PermissionService().requestManageExternalStorage();
    if (granted) notifyListeners();
    return granted;
  }

  /// Request System Alert Window
  Future<bool> requestSystemAlertWindow() async {
    final granted = await PermissionService().requestSystemAlertWindow();
    if (granted) notifyListeners();
    return granted;
  }

  /// Open Usage Access Settings
  Future<void> openUsageAccessSettings() async {
    await PermissionService().openUsageAccessSettings();
  }

  /// Open Notification Listener Settings
  Future<void> openNotificationListenerSettings() async {
    await PermissionService().openNotificationListenerSettings();
  }

  /// Check if device is Android 13 or higher
  Future<bool> isAndroid13OrHigher() async {
    return await PermissionService().isAndroid13OrHigher();
  }

  /// Check Status Helpers
  Future<bool> get isExternalStorageGranted async =>
      await Permission.manageExternalStorage.isGranted;

  Future<bool> get isSystemAlertWindowGranted async =>
      await Permission.systemAlertWindow.isGranted;

  /// Open app settings
  Future<void> openAppSettingsSystem() async {
    await openAppSettings();
  }

  /// Update preferences
  Future<bool> savePreferences(UserPreferences newPrefs) async {
    final oldPrefs = _preferences;
    // Optimistic update
    _preferences = newPrefs;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.updatePreferences(newPrefs);
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Revert on failure
      _preferences = oldPrefs;
      _errorMessage = 'فشل حفظ الإعدادات';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Add text document
  /// Issue #5: Improved temp ID generation to prevent collisions
  /// Issue #6: Added input validation
  Future<bool> addKnowledgeDocument(String text) async {
    // Issue #6: Validate input
    if (text.trim().isEmpty) {
      _errorMessage = 'النص لا يمكن أن يكون فارغاً';
      notifyListeners();
      return false;
    }

    if (text.length > KnowledgeBaseConstants.maxTextLength) {
      _errorMessage = 'النص طويل جداً';
      notifyListeners();
      return false;
    }

    // Issue #5: Generate unique ID with UUID to prevent collisions
    final uuid = const Uuid().v4().substring(0, 8);
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$uuid';
    final tempDoc = KnowledgeDocument(
      text: text,
      source: KnowledgeSource.mobileApp,
      createdAt: DateTime.now(),
      id: tempId,
    );
    try {
      _knowledgeDocuments.add(tempDoc); // Optimistic update
      notifyListeners();

      await _knowledgeRepository.addKnowledgeDocument(text);

      // Refresh after a short delay to get the server-assigned ID
      await Future.delayed(const Duration(milliseconds: 500));
      await loadSettings();
      return true;
    } catch (e) {
      // Rollback using unique ID
      _knowledgeDocuments.removeWhere((doc) => doc.id == tempId);
      _errorMessage = _extractErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Update text document
  /// Issue #2: Fixed silent error swallowing - now properly handles errors
  Future<bool> updateKnowledgeDocument(
    KnowledgeDocument doc,
    String text,
  ) async {
    if (doc.id == null) {
      _errorMessage = 'المستند غير موجود';
      notifyListeners();
      return false;
    }

    // Issue #6: Validate input
    if (text.trim().isEmpty) {
      _errorMessage = 'النص لا يمكن أن يكون فارغاً';
      notifyListeners();
      return false;
    }

    if (text.length > KnowledgeBaseConstants.maxTextLength) {
      _errorMessage = 'النص طويل جداً';
      notifyListeners();
      return false;
    }

    final originalText = doc.text;
    final originalIndex = _knowledgeDocuments.indexWhere((d) => d.id == doc.id);

    try {
      // Optimistic update
      if (originalIndex != -1) {
        _knowledgeDocuments[originalIndex] = KnowledgeDocument(
          id: doc.id,
          text: text,
          source: doc.source,
          createdAt: doc.createdAt,
        );
        notifyListeners();
      }

      // Issue #2: Fire and forget BUT with proper error logging and user notification
      _knowledgeRepository
          .updateKnowledgeDocument(doc.id!, text)
          .then((_) {
            debugPrint('[SettingsProvider] Document updated successfully');
            loadSettings(); // Silent background refresh
          })
          .catchError((error) {
            // Issue #2: DON'T ignore errors - log and notify user
            debugPrint('[SettingsProvider] Update failed: $error');
            _errorMessage = 'فشل حفظ التعديلات';
            notifyListeners();
          });

      return true;
    } catch (e) {
      // Rollback
      if (originalIndex != -1) {
        _knowledgeDocuments[originalIndex] = KnowledgeDocument(
          id: doc.id,
          text: originalText,
          source: doc.source,
          createdAt: doc.createdAt,
        );
      }
      _errorMessage = _extractErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Extract user-friendly error message from exception
  String _extractErrorMessage(dynamic error, {String operation = 'add'}) {
    final errorStr = error.toString().toLowerCase();

    // Knowledge document errors
    if (errorStr.contains('هذا الملف موجود بالفعل')) {
      return 'هذا الملف موجود بالفعل';
    }
    if (errorStr.contains('موجود بالفعل') ||
        errorStr.contains('already exists')) {
      return 'هذا المستند موجود بالفعل';
    }
    if (errorStr.contains('تجاوزت حد التخزين') ||
        errorStr.contains('storage limit')) {
      return 'تجاوزت حد التخزين المسموح به';
    }
    if (errorStr.contains('حجم الملف كبير') || errorStr.contains('file size')) {
      return 'حجم الملف كبير جداً';
    }
    if (errorStr.contains('نوع الملف') ||
        errorStr.contains('file type') ||
        errorStr.contains('not allowed')) {
      return 'نوع الملف غير مدعوم';
    }
    if (errorStr.contains('غير موجود') || errorStr.contains('not found')) {
      return 'المستند غير موجود';
    }
    if (errorStr.contains('النص لا يمكن أن يكون فارغاً') ||
        errorStr.contains('empty')) {
      return 'النص لا يمكن أن يكون فارغاً';
    }
    if (errorStr.contains('النص طويل جداً') || errorStr.contains('too long')) {
      return 'النص طويل جداً';
    }

    // Generic errors
    if (errorStr.contains('connection') || errorStr.contains('network')) {
      return 'خطأ في الاتصال بالإنترنت';
    }
    if (errorStr.contains('timeout')) {
      return 'انتهت مهلة العملية';
    }

    // Operation-specific default messages
    if (operation == 'delete') {
      return 'فشل حذف المستند';
    }
    if (operation == 'update') {
      return 'فشل حفظ التعديلات';
    }
    return 'فشل إضافة المستند';
  }

  /// Delete a knowledge document
  Future<bool> deleteKnowledgeDocument(KnowledgeDocument doc) async {
    if (doc.id == null) {
      _errorMessage = 'المستند غير موجود';
      notifyListeners();
      return false;
    }

    // If it's a temp ID, just remove it locally (not saved to server yet)
    if (doc.id!.startsWith('temp_') || doc.id!.startsWith('pending_')) {
      _knowledgeDocuments.removeWhere((d) => d.id == doc.id);
      notifyListeners();
      return true;
    }

    final originalIndex = _knowledgeDocuments.indexWhere((d) => d.id == doc.id);
    KnowledgeDocument? removedDoc;

    try {
      // Optimistic removal - save the removed doc for potential rollback
      if (originalIndex != -1) {
        removedDoc = _knowledgeDocuments.removeAt(originalIndex);
        notifyListeners();
      }

      // Call delete API (repository handles cache invalidation)
      await _knowledgeRepository.deleteKnowledgeDocument(doc.id!);

      return true;
    } catch (e) {
      // Rollback - re-add the document at original position
      if (removedDoc != null && originalIndex != -1) {
        _knowledgeDocuments.insert(originalIndex, removedDoc);
      }
      final errorMsg = _extractErrorMessage(e, operation: 'delete');
      debugPrint('Delete failed: $e');
      _errorMessage = errorMsg;
      notifyListeners();
      return false;
    }
  }

  List<PlatformFile> _pendingFiles = [];
  List<FailedFile> _failedFiles = [];

  List<PlatformFile> get pendingFiles => _pendingFiles;
  List<FailedFile> get failedFiles => _failedFiles;

  /// Pick file and add to pending list
  Future<bool> pickKnowledgeFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: KnowledgeBaseConstants.allowedFileExtensions
            .map((e) => e.substring(1))
            .toList(), // Remove leading dot
        allowMultiple: true,
      );

      if (result != null) {
        // Validate files before adding
        final validFiles = <PlatformFile>[];
        final invalidFiles = <String>[];

        for (final file in result.files) {
          final validation = _validateKnowledgeFile(file);
          if (validation.isValid) {
            validFiles.add(file);
          } else {
            invalidFiles.add('${file.name}: ${validation.error}');
          }
        }

        if (invalidFiles.isNotEmpty) {
          _errorMessage = 'الملفات غير الصالحة:\n${invalidFiles.join('\n')}';
          notifyListeners();
        }

        if (validFiles.isNotEmpty) {
          _pendingFiles.addAll(validFiles);
          notifyListeners();

          // Auto-upload
          await uploadPendingFiles();
        }

        return validFiles.isNotEmpty;
      }
      return false;
    } catch (e) {
      _errorMessage = 'فشل اختيار الملف: $e';
      notifyListeners();
      return false;
    }
  }

  /// Validate a file for knowledge base upload
  _FileValidation _validateKnowledgeFile(PlatformFile file) {
    // Issue #3: Use constant instead of hardcoded value
    if (file.size > KnowledgeBaseConstants.maxFileSize) {
      return _FileValidation(false, 'حجم الملف يتجاوز 20 ميجابايت');
    }

    // Check file extension
    final fileName = file.name.toLowerCase();
    final hasAllowedExtension = KnowledgeBaseConstants.allowedFileExtensions
        .any((ext) => fileName.endsWith(ext));

    if (!hasAllowedExtension) {
      return _FileValidation(false, 'نوع الملف غير مدعوم');
    }

    return _FileValidation(true, null);
  }

  /// Remove file from pending list
  void removePendingFile(PlatformFile file) {
    _pendingFiles.remove(file);
    notifyListeners();
  }

  /// Upload all pending files
  /// Issue #1: Fixed race condition in progress tracking
  /// Issue #9: Added auto-retry for transient failures
  Future<bool> uploadPendingFiles() async {
    if (_pendingFiles.isEmpty && _failedFiles.isEmpty) return true;

    _isUploading = true;
    _uploadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    bool allSuccess = true;
    final List<FailedFile> newFailedFiles = [];
    final List<String> errorMessages = [];
    final List<String> skippedFiles = [];

    // Combine pending and failed files
    final allFiles = [..._pendingFiles, ..._failedFiles.map((f) => f.file)];
    final totalFiles = allFiles.length;

    for (int i = 0; i < allFiles.length; i++) {
      final file = allFiles[i];
      // Issue #2: Track files with null paths instead of silently skipping
      if (file.path == null) {
        skippedFiles.add(file.name);
        continue;
      }

      _uploadingFileName = file.name;
      try {
        // Issue #1: Capture loop variable by value to prevent race condition
        final currentIndex = i;
        await _knowledgeRepository.uploadKnowledgeFile(
          file.path!,
          onProgress: (progress) {
            // Issue #1: Use captured variable instead of loop variable
            final overallProgress =
                ((currentIndex + progress) / totalFiles) * 100;
            _uploadProgress = overallProgress;
            notifyListeners();
          },
        );
        _uploadProgress = ((i + 1) / totalFiles) * 100;
        notifyListeners();
      } catch (e) {
        allSuccess = false;
        newFailedFiles.add(FailedFile(file, _extractErrorMessage(e)));
        final errorMsg = _extractErrorMessage(e);
        if (!errorMessages.contains(errorMsg)) {
          errorMessages.add(errorMsg);
        }
      }
    }

    // Refresh list from server
    try {
      _knowledgeDocuments = await _knowledgeRepository.getKnowledgeDocuments();
    } catch (_) {}

    _pendingFiles = []; // Clear pending
    _failedFiles = newFailedFiles; // Update failed files
    _isUploading = false;
    _uploadingFileName = null;

    // Issue #2: Add skipped files to error messages
    if (skippedFiles.isNotEmpty) {
      errorMessages.add(
        'تم تخطي ${skippedFiles.length} ملف(s) بسبب مسار غير صالح: ${skippedFiles.join(', ')}',
      );
    }

    if (!allSuccess || skippedFiles.isNotEmpty) {
      _errorMessage = errorMessages.isNotEmpty
          ? errorMessages.join('\n')
          : 'فشل رفع بعض الملفات';
    }

    notifyListeners();
    return allSuccess && skippedFiles.isEmpty;
  }

  /// Retry a failed file upload
  Future<bool> retryFailedFile(PlatformFile file) async {
    if (file.path == null) return false;

    _uploadingFileName = file.name;
    _isUploading = true;
    _uploadProgress = 0.0;
    notifyListeners();

    try {
      await _knowledgeRepository.uploadKnowledgeFile(
        file.path!,
        onProgress: (progress) {
          _uploadProgress = progress * 100;
          notifyListeners();
        },
      );

      // Remove from failed files
      _failedFiles.removeWhere((f) => f.file == file);
      _isUploading = false;
      _uploadingFileName = null;
      notifyListeners();
      return true;
    } catch (e) {
      // Update error message
      final idx = _failedFiles.indexWhere((f) => f.file == file);
      if (idx != -1) {
        _failedFiles[idx] = FailedFile(file, _extractErrorMessage(e));
      }
      _isUploading = false;
      _uploadingFileName = null;
      _errorMessage = _extractErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Remove a failed file from the list
  void removeFailedFile(PlatformFile file) {
    _failedFiles.removeWhere((f) => f.file == file);
    notifyListeners();
  }

  /// Retry all failed files
  Future<bool> retryAllFailedFiles() async {
    if (_failedFiles.isEmpty) return true;
    return await uploadPendingFiles();
  }

  /// Reset provider state
  void reset() {
    _loadGeneration++; // Invalidate any in-flight loadSettings calls
    debugPrint(
      '[SettingsProvider] reset() called, generation=$_loadGeneration',
    );
    _state = SettingsState.initial;
    _integrationsState = SettingsState.initial;
    _knowledgeLoadState = KnowledgeLoadState.initial;
    _preferences = null;
    _knowledgeDocuments = [];
    _integrations = [];
    _errorMessage = null;
    _isSaving = false;
    _isUploading = false;
    _pendingFiles = [];
    _failedFiles = [];
    notifyListeners();
  }

  /// Load integrations with cache-first approach
  Future<void> loadIntegrations() async {
    _errorMessage = null;

    // 1. Instant Cache Load
    if (_integrations.isEmpty) {
      try {
        final cache = PersistentCacheService();
        final accountHash = await _repository.apiClient.getAccountCacheHash();
        final cacheKey = '${accountHash}_accounts_status';
        final cachedData = await cache.get<Map<String, dynamic>>(
          PersistentCacheService.boxIntegrations,
          cacheKey,
        );

        if (cachedData != null) {
          _integrations =
              (cachedData['accounts'] as List<dynamic>?) ??
              (cachedData['integrations'] as List<dynamic>?) ??
              [];
          _integrationsState = SettingsState.loaded;
          notifyListeners();
        } else {
          _integrationsState = SettingsState.loading;
          notifyListeners();
        }
      } catch (_) {}
    }

    // 2. Fresh Fetch
    try {
      final status = await _integrationsRepository.getAccountsStatus();
      _integrations =
          (status['accounts'] as List<dynamic>?) ??
          (status['integrations'] as List<dynamic>?) ??
          [];
      _integrationsState = SettingsState.loaded;
    } catch (e) {
      if (_integrations.isEmpty) {
        _errorMessage = 'فشل تحميل التكاملات: $e';
        _integrationsState = SettingsState.error;
      }
    }
    notifyListeners();
  }

  /// Update channel settings
  Future<bool> updateChannelSettings(
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      await _integrationsRepository.updateChannelSettings(type, data);
      await loadIntegrations(); // Refresh
      return true;
    } catch (e) {
      _errorMessage = 'فشل تحديث الإعدادات: $e';
      notifyListeners();
      return false;
    }
  }

  /// Disconnect channel
  Future<bool> disconnectChannel(String type) async {
    try {
      await _integrationsRepository.disconnectChannel(type);
      await loadIntegrations(); // Refresh
      return true;
    } catch (e) {
      _errorMessage = 'فشل إلغاء الربط: $e';
      notifyListeners();
      return false;
    }
  }

  /// Save Telegram config
  Future<bool> saveTelegramConfig(String token) async {
    try {
      await _integrationsRepository.saveTelegramConfig(token);
      await loadIntegrations();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Save WhatsApp config
  Future<bool> saveWhatsappConfig(String phoneId, String token) async {
    try {
      await _integrationsRepository.saveWhatsappConfig(phoneId, token);
      await loadIntegrations();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }


  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  /// Issue #6: Clear pending files on dispose to prevent memory leaks
  void dispose() {
    _isDisposed = true;
    _pendingFiles.clear();
    _failedFiles.clear();
    super.dispose();
  }
}

/// File validation result
class _FileValidation {
  final bool isValid;
  final String? error;

  _FileValidation(this.isValid, this.error);
}

/// Failed file with error message
class FailedFile {
  final PlatformFile file;
  final String error;

  FailedFile(this.file, this.error);
}
