import 'dart:io';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';

import '../../../core/constants/colors.dart';
import '../../../core/services/sharing_service.dart';

// P0 FIX: File size limits to prevent memory exhaustion
const int kMaxTextFileSize = 5 * 1024 * 1024; // 5MB for text files

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
  
  // P0 FIX: Retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isSizeError = false;

  double _fontSize = 14.0;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      
      // P0 FIX: Check if file exists
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = 'الملف غير موجود';
          });
        }
        return;
      }
      
      // P0 FIX: Check file size
      final fileSize = await file.length();
      if (fileSize > kMaxTextFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            _error = 'حجم الملف كبير جداً (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ميجابايت). الحد الأقصى هو ${kMaxTextFileSize ~/ 1024 ~/ 1024} ميجابايت';
          });
        }
        return;
      }
      
      final lines = await file.readAsLines();
      if (mounted) {
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

  // P0 FIX: Retry method
  void _retryLoad() {
    if (_retryCount < _maxRetries) {
      setState(() {
        _retryCount++;
        _isLoading = true;
        _error = null;
        _isSizeError = false;
      });
      _loadFile();
    }
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.black, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'بحث...',
                  hintStyle: TextStyle(color: Colors.black54),
                  border: InputBorder.none,
                ),
                onChanged: _onSearch,
                autofocus: true,
              )
            : Text(widget.fileName),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 18),
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
              icon: Icon(SolarLinearIcons.magnifer),
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(SolarLinearIcons.minusCircle),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize - 2).clamp(8.0, 48.0)),
              tooltip: 'تصغير الخط',
            ),
            IconButton(
              icon: const Icon(SolarLinearIcons.addCircle),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize + 2).clamp(8.0, 48.0)),
              tooltip: 'تكبير الخط',
            ),
          ],
          IconButton(
            icon: const Icon(SolarLinearIcons.share),
            onPressed: () => _shareText(context),
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.download),
            onPressed: () => _saveText(context),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  if (_retryCount > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      'محاولة $_retryCount من $_maxRetries...',
                      style: const TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                  ],
                ],
              ),
            )
          : _error != null
          ? _buildErrorView()
          : _buildContent(),
    );
  }

  // P0 FIX: Error view with retry button
  Widget _buildErrorView() {
    final canRetry = _retryCount < _maxRetries && !_isSizeError;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSizeError ? SolarLinearIcons.file : SolarLinearIcons.dangerCircle,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            _isSizeError ? 'حجم الملف كبير جداً' : 'فشل تحميل الملف',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.hintColor,
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
              label: Text('إعادة المحاولة (${_maxRetries - _retryCount})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    List<String> displayLines = _lines;
    if (_searchQuery.isNotEmpty) {
      displayLines = _lines
          .where((line) => line.toLowerCase().contains(_searchQuery))
          .toList();
    }

    if (displayLines.isEmpty) {
      return const Center(child: Text('لا توجد نتائج'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: displayLines.length,
      itemBuilder: (context, index) {
        return SelectableText(
          displayLines[index],
          style: TextStyle(fontSize: _fontSize, color: Colors.black87),
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
