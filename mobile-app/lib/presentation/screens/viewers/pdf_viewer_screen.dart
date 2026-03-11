import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../../../core/services/sharing_service.dart';

import '../../../core/constants/colors.dart';

// P0 FIX: File size limits to prevent memory exhaustion
const int kMaxPdfFileSize = 50 * 1024 * 1024; // 50MB for PDFs
const int kPdfLoadTimeoutSeconds = 30;

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int? pages = 0;
  int? currentPage = 0;
  bool isReady = false;
  String errorMessage = '';
  bool _isHorizontalSwipe = false;

  // P0 FIX: Retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isLoading = true;
  bool _isSizeError = false;

  @override
  void initState() {
    super.initState();
    _validateAndLoad();
  }

  Future<void> _validateAndLoad() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            errorMessage = 'الملف غير موجود';
          });
        }
        return;
      }

      // P0 FIX: Check file size
      final fileSize = await file.length();
      if (fileSize > kMaxPdfFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            errorMessage =
                'حجم الملف كبير جداً (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ميجابايت). الحد الأقصى هو ${kMaxPdfFileSize ~/ 1024 ~/ 1024} ميجابايت';
          });
        }
        return;
      }

      // File is valid, PDFView will load it
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSizeError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSizeError = false;
          errorMessage = 'خطأ في تحميل الملف: ${e.toString()}';
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
        errorMessage = '';
        _isSizeError = false;
      });
      _validateAndLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_isHorizontalSwipe ? Icons.swap_horiz : Icons.swap_vert),
            tooltip: _isHorizontalSwipe ? 'تمرير رأسي' : 'تمرير أفقي',
            onPressed: () {
              setState(() {
                _isHorizontalSwipe = !_isHorizontalSwipe;
              });
            },
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.share),
            onPressed: () => _sharePdf(context),
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.download),
            onPressed: () => _savePdf(context),
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
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : errorMessage.isNotEmpty
          ? _buildErrorView()
          : Stack(
              children: <Widget>[
                PDFView(
                  filePath: widget.filePath,
                  enableSwipe: true,
                  swipeHorizontal: _isHorizontalSwipe,
                  autoSpacing: true,
                  pageFling: true,
                  pageSnap: true,
                  defaultPage: currentPage!,
                  fitPolicy: FitPolicy.BOTH,
                  preventLinkNavigation: false,
                  onRender: (pages) {
                    if (mounted) {
                      setState(() {
                        pages = pages;
                        isReady = true;
                      });
                    }
                  },
                  onError: (error) {
                    if (mounted) {
                      setState(() {
                        errorMessage = 'فشل تحميل PDF: $error';
                      });
                    }
                  },
                  onPageError: (page, error) {
                    if (mounted) {
                      setState(() {
                        errorMessage = 'صفحة $page: $error';
                      });
                    }
                  },
                  onViewCreated: (PDFViewController pdfViewController) {
                    // Controller available if needed
                  },
                  onLinkHandler: (String? uri) {
                    // Handle link if needed
                  },
                  onPageChanged: (int? page, int? total) {
                    if (mounted) {
                      setState(() {
                        currentPage = page;
                      });
                    }
                  },
                ),
                if (!isReady && errorMessage.isEmpty)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
              ],
            ),
      floatingActionButton: isReady
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(currentPage ?? 0) + 1} / ${pages ?? 0}',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
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
            _isSizeError
                ? SolarLinearIcons.file
                : SolarLinearIcons.dangerCircle,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            _isSizeError ? 'حجم الملف كبير جداً' : 'فشل تحميل PDF',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
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

  Future<void> _sharePdf(BuildContext context) async {
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

  Future<void> _savePdf(BuildContext context) async {
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
