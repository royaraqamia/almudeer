import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/services/media_service.dart';
import 'package:almudeer_mobile_app/core/utils/premium_toast.dart';
import 'package:almudeer_mobile_app/core/services/sharing_service.dart';
import 'package:almudeer_mobile_app/core/constants/viewer_constants.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';

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

  // Retry logic with exponential backoff
  int _retryCount = 0;
  bool _isLoading = true;
  bool _isSizeError = false;

  // PDFViewController reference for cleanup
  // Note: Stored to track controller lifecycle, used in dispose()
  PDFViewController? _pdfViewController;

  @override
  void initState() {
    super.initState();
    _validateAndLoad();
  }

  @override
  void dispose() {
    // Clean up PDF view controller to prevent memory leaks
    // Note: flutter_pdfview doesn't expose a public dispose API,
    // but we can nullify our reference to allow GC
    if (_pdfViewController != null) {
      // The controller is managed by the widget tree, but we nullify our reference
      _pdfViewController = null;
    }
    
    // Force garbage collection hint for large PDF resources
    isReady = false;
    pages = null;
    
    super.dispose();
  }

  Future<void> _validateAndLoad() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            errorMessage = ViewerErrorType.fileNotFound.message;
          });
        }
        return;
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize > ViewerConstants.maxPdfFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            errorMessage =
                'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹ (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ظ…ظٹط¬ط§ط¨ط§ظٹطھ). ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ‡ظˆ ${ViewerConstants.maxPdfFileSize ~/ 1024 ~/ 1024} ظ…ظٹط¬ط§ط¨ط§ظٹطھ';
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
          errorMessage = 'ط®ط·ط£ ظپظٹ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ: ${e.toString()}';
        });
      }
    }
  }

  // Retry with exponential backoff: 1s, 2s, 4s
  void _retryLoad() {
    if (_retryCount >= ViewerConstants.maxRetries) return;

    final delay = ViewerConstants.retryBaseDelay * (1 << _retryCount);

    setState(() {
      _retryCount++;
      _isLoading = true;
      errorMessage = '';
      _isSizeError = false;
    });

    Future.delayed(delay, () {
      if (mounted) {
        _validateAndLoad();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_isHorizontalSwipe ? Icons.swap_horiz : Icons.swap_vert),
            tooltip: _isHorizontalSwipe ? 'طھظ…ط±ظٹط± ط±ط£ط³ظٹ' : 'طھظ…ط±ظٹط± ط£ظپظ‚ظٹ',
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
                      'ظ…ط­ط§ظˆظ„ط© $_retryCount ظ…ظ† ${ViewerConstants.maxRetries}...',
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
                        errorMessage = 'ظپط´ظ„ طھط­ظ…ظٹظ„ PDF: $error';
                      });
                    }
                  },
                  onPageError: (page, error) {
                    if (mounted) {
                      setState(() {
                        errorMessage = 'طµظپط­ط© $page: $error';
                      });
                    }
                  },
                  onViewCreated: (PDFViewController pdfViewController) {
                    // Store controller reference for cleanup
                    _pdfViewController = pdfViewController;
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

  // Error view with retry button
  Widget _buildErrorView() {
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
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            _isSizeError ? 'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹' : 'ظپط´ظ„ طھط­ظ…ظٹظ„ PDF',
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
              label: Text('ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط© (${ViewerConstants.maxRetries - _retryCount})'),
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
          'ظپط´ظ„ ط§ظ„ظ…ط´ط§ط±ظƒط©: طھط£ظƒط¯ ظ…ظ† ظˆط¬ظˆط¯ ط§ظ„ظ…ظ„ظپ',
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
            'طھظ… ط§ظ„ط­ظپط¸ ط¨ظ†ط¬ط§ط­',
            icon: SolarLinearIcons.checkCircle,
          );
        } else {
          PremiumToast.show(
            context,
            'ظپط´ظ„ ط§ظ„ط­ظپط¸',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'ط®ط·ط£ ظپظٹ ط§ظ„ط­ظپط¸: ${e.toString()}',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
