import 'dart:io';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../../../core/constants/viewer_constants.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/sharing_service.dart';

class TextViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const TextViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  List<String> _lines = [];
  bool _isLoading = true;
  String? _error;

  // Retry logic
  int _retryCount = 0;
  bool _isSizeError = false;

  double _fontSize = ViewerConstants.defaultTextFontSize;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);

      // Check if file exists
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.fileNotFound.message;
          });
        }
        return;
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize > ViewerConstants.maxTextFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            _error =
                'حجم الملف كبير جداً (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ميجابايت). الحد الأقصى هو ${ViewerConstants.maxTextFileSize ~/ 1024 ~/ 1024} ميجابايت';
          });
        }
        return;
      }

      final lines = await file.readAsLines();
      if (mounted) {
        // Handle empty files
        if (lines.isEmpty) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.emptyFile.message;
          });
          return;
        }

        // Check for binary content (corrupted or wrong file type)
        final firstLines = lines.take(10).join('\n');
        if (firstLines.contains('\u{0000}')) {
          // Null bytes indicate binary content
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.corruptedFile.message;
          });
          return;
        }

        setState(() {
          _lines = lines;
          _isLoading = false;
          _isSizeError = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'فشل تحميل الملف: ${e.toString()}';
          _isLoading = false;
          _isSizeError = false;
        });
      }
    }
  }

  // Retry with exponential backoff
  void _retryLoad() {
    if (_retryCount >= ViewerConstants.maxRetries) return;

    final delay = ViewerConstants.retryBaseDelay * (1 << _retryCount);

    setState(() {
      _retryCount++;
      _isLoading = true;
      _error = null;
      _isSizeError = false;
    });

    Future.delayed(delay, () {
      if (mounted) {
        _loadFile();
      }
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
        elevation: 1,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: _onSearch,
                autofocus: true,
              )
            : Text(
                widget.fileName,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                ),
              ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _searchQuery = '';
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: Icon(
                SolarLinearIcons.magnifer,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(
                SolarLinearIcons.minusCircle,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize - 2).clamp(
                    ViewerConstants.minFontSize,
                    ViewerConstants.maxFontSize,
                  )),
              tooltip: 'تصغير الخط',
            ),
            IconButton(
              icon: Icon(
                SolarLinearIcons.addCircle,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize + 2).clamp(
                    ViewerConstants.minFontSize,
                    ViewerConstants.maxFontSize,
                  )),
              tooltip: 'تكبير الخط',
            ),
          ],
          IconButton(
            icon: Icon(
              SolarLinearIcons.share,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            onPressed: () => _shareText(context),
          ),
          IconButton(
            icon: Icon(
              SolarLinearIcons.download,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            onPressed: () => _saveText(context),
          ),
        ],
      ),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  if (_retryCount > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      'محاولة $_retryCount من ${ViewerConstants.maxRetries}...',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : _error != null
          ? _buildErrorView(isDark)
          : _buildContent(isDark),
    );
  }

  Widget _buildErrorView(bool isDark) {
    final canRetry = _retryCount < ViewerConstants.maxRetries && !_isSizeError;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSizeError
                ? SolarLinearIcons.file
                : SolarLinearIcons.dangerCircle,
            size: 64,
            color: isDark ? Colors.white54 : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            _isSizeError ? 'حجم الملف كبير جداً' : 'فشل تحميل الملف',
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
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
              onPressed: _retryLoad,
              icon: const Icon(SolarLinearIcons.refresh),
              label: Text('إعادة المحاولة (${ViewerConstants.maxRetries - _retryCount})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
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

  Widget _buildContent(bool isDark) {
    List<String> displayLines = _lines;
    if (_searchQuery.isNotEmpty) {
      displayLines = _lines
          .where((line) => line.toLowerCase().contains(_searchQuery))
          .toList();
    }

    if (displayLines.isEmpty) {
      return Center(
        child: Text(
          'لا توجد نتائج',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: displayLines.length,
      itemBuilder: (context, index) {
        return SelectableText(
          displayLines[index],
          style: TextStyle(
            fontSize: _fontSize,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.5,
          ),
        );
      },
    );
  }

  Future<void> _shareText(BuildContext context) async {
    try {
      SharingService().showShareMenu(
        context,
        filePath: widget.filePath,
        title: widget.fileName,
        type: 'document',
      );
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'فشل المشاركة: تأكد من وجود الملف',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }

  Future<void> _saveText(BuildContext context) async {
    try {
      final success = await MediaService.saveToFile(
        widget.filePath,
        widget.fileName,
      );
      if (context.mounted) {
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
      if (context.mounted) {
        PremiumToast.show(
          context,
          'خطأ في الحفظ: ${e.toString()}',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
