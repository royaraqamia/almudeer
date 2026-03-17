import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../constants/viewer_constants.dart';
import '../services/media_service.dart';
import '../services/sharing_service.dart';
import '../utils/premium_toast.dart';

/// Base state class for all viewer screens
/// Provides common functionality: retry logic, error handling, share/save operations
abstract class BaseViewerState<T extends StatefulWidget> extends State<T> {
  // Error state
  String? _errorMessage;
  bool _hasError = false;
  ViewerErrorType _errorType = ViewerErrorType.unknown;

  // Retry state
  int _retryCount = 0;
  bool _isLoading = true;
  Timer? _retryTimer;

  // Getters for subclasses
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  int get retryCount => _retryCount;
  int get maxRetries => ViewerConstants.maxRetries;
  bool get canRetry => _retryCount < ViewerConstants.maxRetries;

  /// Set loading state
  void setLoading(bool loading) {
    if (mounted) {
      setState(() {
        _isLoading = loading;
      });
    }
  }

  /// Set error state with optional retry
  void setError({
    required String message,
    ViewerErrorType errorType = ViewerErrorType.unknown,
    bool hasError = true,
  }) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _errorType = errorType;
        _hasError = hasError;
        _isLoading = false;
      });
    }
  }

  /// Clear error state
  void clearError() {
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _hasError = false;
        _errorType = ViewerErrorType.unknown;
      });
    }
  }

  /// Retry with exponential backoff
  /// Subclasses must implement [onRetry] to perform the actual retry operation
  Future<void> retryWithBackoff() async {
    if (!canRetry) return;

    _retryTimer?.cancel();

    // Exponential backoff: 1s, 2s, 4s
    final delay = ViewerConstants.retryBaseDelay * (1 << _retryCount);

    setState(() {
      _retryCount++;
      _isLoading = true;
      _errorMessage = null;
      _hasError = false;
    });

    await Future.delayed(delay);

    if (mounted) {
      await onRetry();
    }
  }

  /// Override this method to implement retry logic in subclasses
  Future<void> onRetry() async {
    // Subclasses should override this
  }

  /// Check file size against limit
  Future<bool> checkFileSize(File file, int maxSize) async {
    if (!await file.exists()) {
      setError(
        message: ViewerErrorType.fileNotFound.message,
        errorType: ViewerErrorType.fileNotFound,
      );
      return false;
    }

    final fileSize = await file.length();
    if (fileSize > maxSize) {
      setError(
        message:
            'حجم الملف كبير جداً (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ميجابايت). الحد الأقصى هو ${maxSize ~/ 1024 ~/ 1024} ميجابايت',
        errorType: ViewerErrorType.fileSizeExceeded,
      );
      return false;
    }

    return true;
  }

  /// Share a file using the sharing service
  Future<void> shareFile({
    required String filePath,
    required String title,
    String type = 'document',
  }) async {
    try {
      SharingService().showShareMenu(
        context,
        filePath: filePath,
        title: title,
        type: type,
      );
    } catch (e) {
      if (mounted) {
        PremiumToast.show(
          context,
          'فشل المشاركة: تأكد من وجود الملف',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }

  /// Save a file to device
  Future<void> saveFile({
    required String filePath,
    required String fileName,
  }) async {
    try {
      final success = await MediaService.saveToFile(filePath, fileName);
      if (mounted) {
        if (success) {
          PremiumToast.show(
            context,
            'تم الحفظ بنجاح',
            icon: SolarLinearIcons.checkCircle,
          );
        } else {
          PremiumToast.show(
            context,
            'فشل الحفظ',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.show(
          context,
          'خطأ في الحفظ: ${e.toString()}',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }

  /// Build error view widget with retry button
  Widget buildErrorView({
    String? customMessage,
    String? customTitle,
    VoidCallback? onRetryOverride,
  }) {
    final canRetry = this.canRetry && _errorType != ViewerErrorType.fileSizeExceeded;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _errorType == ViewerErrorType.fileSizeExceeded
                ? SolarLinearIcons.file
                : _errorType == ViewerErrorType.networkError
                    ? SolarLinearIcons.volumeCross
                    : SolarLinearIcons.dangerCircle,
            size: 64,
            color: isDark ? Colors.white54 : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            customTitle ??
                (_errorType == ViewerErrorType.fileSizeExceeded
                    ? 'حجم الملف كبير جداً'
                    : 'فشل تحميل الملف'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            customMessage ?? _errorMessage ?? _errorType.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (canRetry) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetryOverride ?? retryWithBackoff,
              icon: const Icon(SolarLinearIcons.refresh),
              label: Text('إعادة المحاولة (${ViewerConstants.maxRetries - _retryCount})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build loading view widget
  Widget buildLoadingView({Color? color}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: color ?? const Color(0xFF2196F3),
          ),
          if (_retryCount > 0) ...[
            const SizedBox(height: 16),
            Text(
              'محاولة $_retryCount من ${ViewerConstants.maxRetries}...',
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Check if app is in dark mode
  bool get isDarkMode {
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
