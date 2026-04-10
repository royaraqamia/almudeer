import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:path/path.dart' as p;
import 'package:almudeer_mobile_app/core/services/media_service.dart';
import 'package:almudeer_mobile_app/core/utils/premium_toast.dart';
import 'package:almudeer_mobile_app/core/constants/viewer_constants.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/services/sharing_service.dart';

/// Maps file extensions to highlight.js language identifiers
const Map<String, String> _extensionToLanguage = {
  // Dart/Flutter
  'dart': 'dart',

  // JavaScript/TypeScript
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',

  // Web
  'html': 'xml',
  'htm': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'vue': 'xml',
  'svelte': 'xml',

  // Data formats
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'xml': 'xml',
  'toml': 'ini',

  // Python
  'py': 'python',
  'pyw': 'python',

  // JVM languages
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'scala': 'scala',
  'groovy': 'groovy',

  // Apple
  'swift': 'swift',
  'm': 'objectivec',
  'mm': 'objectivec',

  // Systems
  'c': 'c',
  'h': 'c',
  'cpp': 'cpp',
  'hpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'go': 'go',
  'rs': 'rust',

  // Scripting
  'rb': 'ruby',
  'php': 'php',
  'pl': 'perl',
  'lua': 'lua',
  'r': 'r',

  // Shell
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'bat': 'dos',
  'cmd': 'dos',
  'ps1': 'powershell',

  // Database
  'sql': 'sql',

  // Config
  'ini': 'ini',
  'conf': 'ini',
  'cfg': 'ini',
  'env': 'bash',
  'properties': 'properties',

  // Docs
  'md': 'markdown',
  'markdown': 'markdown',
  'rst': 'plaintext',
  'txt': 'plaintext',
  'log': 'plaintext',

  // Build tools
  'gradle': 'groovy',
  'cmake': 'cmake',
  'make': 'makefile',
  'makefile': 'makefile',
  'dockerfile': 'dockerfile',
};

class CodeViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const CodeViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<CodeViewerScreen> createState() => _CodeViewerScreenState();
}

class _CodeViewerScreenState extends State<CodeViewerScreen> {
  String _content = '';
  bool _isLoading = true;
  String? _error;
  bool _showLineNumbers = true;
  double _fontSize = ViewerConstants.defaultCodeFontSize;
  String? _manualLanguage;

  // Retry logic
  int _retryCount = 0;
  bool _isSizeError = false;

  // Search functionality
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentSearchIndex = 0;
  List<int> _searchMatches = [];

  String get _language {
    if (_manualLanguage != null) return _manualLanguage!;
    final ext = p.extension(widget.fileName).toLowerCase().replaceAll('.', '');
    return _extensionToLanguage[ext] ?? 'plaintext';
  }

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
      if (fileSize > ViewerConstants.maxCodeFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            _error =
                'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹ (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ظ…ظٹط¬ط§ط¨ط§ظٹطھ). ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ‡ظˆ ${ViewerConstants.maxCodeFileSize ~/ 1024 ~/ 1024} ظ…ظٹط¬ط§ط¨ط§ظٹطھ';
          });
        }
        return;
      }

      // Read file with timeout to prevent hanging
      final content = await _readFileWithTimeout(file);

      if (mounted) {
        // Handle empty files
        if (content.trim().isEmpty) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.emptyFile.message;
          });
          return;
        }

        // Check for binary content (corrupted or wrong file type)
        // Code files should not contain null bytes or excessive non-printable characters
        if (content.contains('\u{0000}')) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.corruptedFile.message;
          });
          return;
        }

        // Check for excessive non-printable characters (indicates binary file)
        final nonPrintableCount = content.codeUnits
            .where((c) => c < 32 && c != 9 && c != 10 && c != 13).length;
        if (nonPrintableCount > content.length * 0.1) {
          // More than 10% non-printable chars = likely binary
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.corruptedFile.message;
          });
          return;
        }

        setState(() {
          _content = content;
          _isLoading = false;
          _isSizeError = false;
          _error = null;
        });
        _updateSearchMatches();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ: ${e.toString()}';
          _isLoading = false;
          _isSizeError = false;
        });
      }
    }
  }

  // Read file with timeout
  Future<String> _readFileWithTimeout(File file) async {
    try {
      return await file.readAsString().timeout(
        ViewerConstants.fileReadTimeout,
        onTimeout: () {
          throw TimeoutException(
            'ط§ظ†طھظ‡طھ ظ…ظ‡ظ„ط© ظ‚ط±ط§ط،ط© ط§ظ„ظ…ظ„ظپ (${ViewerConstants.fileReadTimeout.inSeconds} ط«ط§ظ†ظٹط©)',
          );
        },
      );
    } on TimeoutException catch (e) {
      throw Exception(e.message);
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

  void _updateSearchMatches() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _searchMatches = [];
        _currentSearchIndex = 0;
      });
      return;
    }

    final matches = <int>[];
    final lines = _content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(_searchQuery.toLowerCase())) {
        matches.add(i);
      }
    }
    setState(() {
      _searchMatches = matches;
      _currentSearchIndex = matches.isNotEmpty ? 0 : -1;
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _currentSearchIndex = 0;
    });
    _updateSearchMatches();
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentSearchIndex = (_currentSearchIndex + 1) % _searchMatches.length;
    });
  }

  void _previousMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentSearchIndex =
          (_currentSearchIndex - 1 + _searchMatches.length) %
          _searchMatches.length;
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _content));
    PremiumToast.show(
      context,
      'طھظ… ظ†ط³ط® ط§ظ„ظƒظˆط¯',
      icon: SolarLinearIcons.checkCircle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF282C34) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF21252B) : Colors.grey[100],
        elevation: 1,
        leading: IconButton(
          icon: Icon(
            SolarLinearIcons.arrowRight,
            size: 24,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _searchQuery = '';
                _updateSearchMatches();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _isSearching
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'ط¨ط­ط« ظپظٹ ط§ظ„ظƒظˆط¯...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: _onSearch,
                      autofocus: true,
                      onSubmitted: (_) => _nextMatch(),
                    ),
                  ),
                  if (_searchMatches.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_currentSearchIndex + 1}/${_searchMatches.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    _language.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(
                SolarLinearIcons.magnifer,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'ط¨ط­ط«',
              onPressed: () => setState(() => _isSearching = true),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                SolarLinearIcons.code,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'طھط؛ظٹظٹط± ط§ظ„ظ„ط؛ط©',
              onSelected: (String lang) {
                setState(() {
                  _manualLanguage = lang;
                });
              },
              itemBuilder: (BuildContext context) {
                final languages = _extensionToLanguage.values.toSet().toList()
                  ..sort();
                return languages.map((String lang) {
                  return PopupMenuItem<String>(
                    value: lang,
                    child: Text(lang.toUpperCase()),
                  );
                }).toList();
              },
            ),
            IconButton(
              icon: Icon(
                SolarLinearIcons.minusCircle,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'طھطµط؛ظٹط± ط§ظ„ط®ط·',
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize - 2).clamp(
                    ViewerConstants.minFontSize,
                    ViewerConstants.maxFontSize,
                  )),
            ),
            IconButton(
              icon: Icon(
                SolarLinearIcons.addCircle,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'طھظƒط¨ظٹط± ط§ظ„ط®ط·',
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize + 2).clamp(
                    ViewerConstants.minFontSize,
                    ViewerConstants.maxFontSize,
                  )),
            ),
            IconButton(
              icon: Icon(
                _showLineNumbers
                    ? SolarBoldIcons.listCheck
                    : SolarLinearIcons.listCheck,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'ط£ط±ظ‚ط§ظ… ط§ظ„ط£ط³ط·ط±',
              onPressed: () =>
                  setState(() => _showLineNumbers = !_showLineNumbers),
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                SolarLinearIcons.arrowLeft,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'ط§ظ„طھط§ظ„ظٹ',
              onPressed: _nextMatch,
            ),
            IconButton(
              icon: Icon(
                SolarLinearIcons.arrowRight,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'ط§ظ„ط³ط§ط¨ظ‚',
              onPressed: _previousMatch,
            ),
          ],
          IconButton(
            icon: Icon(
              SolarLinearIcons.copy,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            tooltip: 'ظ†ط³ط®',
            onPressed: _copyToClipboard,
          ),
          IconButton(
            icon: Icon(
              SolarLinearIcons.share,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            tooltip: 'ظ…ط´ط§ط±ظƒط©',
            onPressed: () => _shareCode(context),
          ),
          IconButton(
            icon: Icon(
              SolarLinearIcons.download,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            tooltip: 'ط­ظپط¸',
            onPressed: () => _saveCode(context),
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
          : _error != null
          ? _buildErrorView(isDark)
          : _buildCodeView(isDark),
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
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            _isSizeError ? 'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹' : 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ',
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

  Widget _buildCodeView(bool isDark) {
    final lines = _content.split('\n');
    final lineNumberWidth = (lines.length.toString().length * 10.0) + 24;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line numbers
            if (_showLineNumbers)
              Container(
                width: lineNumberWidth,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF21252B) : Colors.grey[200],
                  border: Border(
                    right: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey[300]!,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(lines.length, (index) {
                    return SizedBox(
                      height: 20,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: _fontSize,
                          height: 1.5,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Code content with syntax highlighting
            Padding(
              padding: const EdgeInsets.all(16),
              child: HighlightView(
                _content,
                language: _language,
                theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
                padding: EdgeInsets.zero,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: _fontSize,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareCode(BuildContext context) async {
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

  Future<void> _saveCode(BuildContext context) async {
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
