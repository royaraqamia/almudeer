import 'dart:io';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:csv/csv.dart';
import 'package:almudeer_mobile_app/core/services/media_service.dart';
import 'package:almudeer_mobile_app/core/utils/premium_toast.dart';
import 'package:almudeer_mobile_app/core/constants/viewer_constants.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/services/sharing_service.dart';

class CsvViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const CsvViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<CsvViewerScreen> createState() => _CsvViewerScreenState();
}

class _CsvViewerScreenState extends State<CsvViewerScreen> {
  // Parsed data (lazy loaded)
  List<List<dynamic>> _data = [];
  List<List<dynamic>> _filteredData = [];
  
  // Store only indices for sorting (memory efficient)
  List<int> _rowIndices = [];
  
  bool _isLoading = true;
  String? _error;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  int? _sortColumnIndex;
  bool _isAscending = true;
  int _originalRowCount = 0;

  // Retry logic
  int _retryCount = 0;
  bool _isSizeError = false;

  // Pagination
  int _currentPage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCsv() async {
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
      if (fileSize > ViewerConstants.maxCsvFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSizeError = true;
            _error =
                'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹ (${(fileSize / 1024 / 1024).toStringAsFixed(1)} ظ…ظٹط¬ط§ط¨ط§ظٹطھ). ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ‡ظˆ ${ViewerConstants.maxCsvFileSize ~/ 1024 ~/ 1024} ظ…ظٹط¬ط§ط¨ط§ظٹطھ';
          });
        }
        return;
      }

      // Read file content once
      final content = await file.readAsString();

      if (mounted) {
        // Parse CSV using the csv package
        List<List<dynamic>> data;
        try {
          data = csv.decode(content);
        } catch (e) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.corruptedFile.message;
          });
          return;
        }

        // Handle empty files
        if (data.isEmpty) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.emptyFile.message;
          });
          return;
        }

        // Validate CSV structure (check for corrupted files)
        // A valid CSV should have consistent column counts (or at least some rows with data)
        final hasValidStructure = data.any((row) => row.isNotEmpty);
        if (!hasValidStructure) {
          setState(() {
            _isLoading = false;
            _isSizeError = false;
            _error = ViewerErrorType.corruptedFile.message;
          });
          return;
        }

        // Store only indices instead of duplicating row data (memory optimization)
        final rowIndices = List<int>.generate(data.length, (i) => i);

        final totalPages = (data.length / ViewerConstants.defaultRowsPerPage).ceil();

        setState(() {
          _data = data;
          _rowIndices = rowIndices;
          _originalRowCount = data.length;
          _totalPages = totalPages > 0 ? totalPages : 1;
          _currentPage = 0;
          _isLoading = false;
          _isSizeError = false;
          _error = null;
        });
        _applyFilterAndSort();
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
        _loadCsv();
      }
    });
  }

  void _applyFilterAndSort() {
    if (_data.isEmpty) return;

    final query = _searchController.text.toLowerCase();

    // Keep header separate (first row)
    final headerIndex = _rowIndices.isNotEmpty ? _rowIndices.first : -1;

    // Get rest of row indices (skip header)
    var rest = _rowIndices.skip(1).toList();

    // Apply filter
    if (query.isNotEmpty) {
      rest = rest.where((index) {
        if (index >= _data.length) return false;
        final row = _data[index];
        return row.any((cell) => cell.toString().toLowerCase().contains(query));
      }).toList();
    }

    // Apply sort with stable ordering (using indices, not duplicating data)
    if (_sortColumnIndex != null) {
      rest.sort((a, b) {
        if (a >= _data.length || b >= _data.length) return 0;
        
        final rowA = _data[a];
        final rowB = _data[b];

        final valA = _sortColumnIndex! < rowA.length
            ? rowA[_sortColumnIndex!]
            : '';
        final valB = _sortColumnIndex! < rowB.length
            ? rowB[_sortColumnIndex!]
            : '';

        int comparison;
        final numA = double.tryParse(valA.toString());
        final numB = double.tryParse(valB.toString());

        if (numA != null && numB != null) {
          comparison = numA.compareTo(numB);
        } else {
          comparison = valA.toString().compareTo(valB.toString());
        }

        // If equal, preserve original order (stable sort via indices)
        if (comparison == 0) {
          return a.compareTo(b);
        }

        return _isAscending ? comparison : -comparison;
      });
    }

    // Apply pagination
    final totalPages = (rest.length / ViewerConstants.defaultRowsPerPage).ceil();
    final startIndex = _currentPage * ViewerConstants.defaultRowsPerPage;
    final endIndex = (startIndex + ViewerConstants.defaultRowsPerPage).clamp(0, rest.length);

    setState(() {
      // Build filtered data from indices (memory efficient)
      _filteredData = [
        if (headerIndex >= 0 && headerIndex < _data.length) _data[headerIndex],
        ...rest
            .skip(startIndex)
            .take(endIndex - startIndex)
            .map((index) => _data[index]),
      ];
      _totalPages = totalPages > 0 ? totalPages : 1;
    });
  }

  void _changePage(int delta) {
    final newPage = (_currentPage + delta).clamp(0, _totalPages - 1);
    if (newPage != _currentPage) {
      setState(() {
        _currentPage = newPage;
      });
      _applyFilterAndSort();
    }
  }

  void _onSearch(String query) {
    _applyFilterAndSort();
  }

  void _onColumnTapped(int columnIndex) {
    if (_sortColumnIndex == columnIndex) {
      setState(() {
        _isAscending = !_isAscending;
      });
    } else {
      setState(() {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      });
    }
    _applyFilterAndSort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'ط¨ط­ط«...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: _onSearch,
                autofocus: true,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.fileName, style: const TextStyle(fontSize: 16)),
                  if (_data.isNotEmpty)
                    Text(
                      '${_filteredData.length} / $_originalRowCount طµظپظˆظپ',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchController.clear();
                _filteredData = _data;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (_sortColumnIndex != null)
            IconButton(
              icon: Icon(
                _isAscending
                    ? SolarLinearIcons.arrowUp
                    : SolarLinearIcons.arrowDown,
                size: 20,
              ),
              tooltip: _isAscending ? 'طھط±طھظٹط¨ طھطµط§ط¹ط¯ظٹ' : 'طھط±طھظٹط¨ طھظ†ط§ط²ظ„ظٹ',
              onPressed: () {
                setState(() {
                  _sortColumnIndex = null;
                  _isAscending = true;
                  _applyFilterAndSort();
                });
              },
            ),
          IconButton(
            icon: const Icon(SolarLinearIcons.magnifer),
            onPressed: () => setState(() => _isSearching = true),
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.share),
            onPressed: () => _shareCsv(context),
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.download),
            onPressed: () => _saveCsv(context),
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
          ? _buildErrorView()
          : _filteredData.isEmpty
          ? const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ظ†طھط§ط¦ط¬'))
          : Column(
              children: [
                Expanded(child: _buildTable(isDark)),
                if (_totalPages > 1) _buildPaginationControls(isDark),
              ],
            ),
    );
  }

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
            _isSizeError ? 'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹' : 'ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ظ…ظ„ظپ',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
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

  Widget _buildPaginationControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        border: Border(
          top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(SolarLinearIcons.arrowLeft, size: 20),
            onPressed: _currentPage > 0 ? () => _changePage(-1) : null,
            tooltip: 'ط§ظ„طµظپط­ط© ط§ظ„ط³ط§ط¨ظ‚ط©',
          ),
          const SizedBox(width: 16),
          Text(
            'طµظپط­ط© ${_currentPage + 1} ظ…ظ† $_totalPages',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(SolarLinearIcons.arrowRight, size: 20),
            onPressed: _currentPage < _totalPages - 1
                ? () => _changePage(1)
                : null,
            tooltip: 'ط§ظ„طµظپط­ط© ط§ظ„طھط§ظ„ظٹط©',
          ),
        ],
      ),
    );
  }

  Widget _buildTable(bool isDark) {
    if (_filteredData.isEmpty) return const SizedBox();

    final maxColumns = _filteredData.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: maxColumns * ViewerConstants.cellWidth,
        child: ListView.builder(
          itemCount: _filteredData.length,
          itemBuilder: (context, index) {
            final row = _filteredData[index];
            final paddedRow = List<String>.generate(
              maxColumns,
              (i) => i < row.length ? row[i] : '',
            );

            // Check if it's header (usually first row of original data)
            final isHeader = _data.isNotEmpty && row == _data.first;

            return Container(
              decoration: BoxDecoration(
                color: isHeader
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : (index.isEven
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.02)
                                : Colors.grey[50])
                          : null),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!,
                  ),
                ),
              ),
              child: Row(
                children: paddedRow.asMap().entries.map((entry) {
                  final colIndex = entry.key;
                  final cell = entry.value;

                  Widget cellContent = Text(
                    cell,
                    style: TextStyle(
                      fontWeight: isHeader
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );

                  if (isHeader) {
                    cellContent = Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: cellContent),
                        if (_sortColumnIndex == colIndex)
                          Icon(
                            _isAscending
                                ? SolarLinearIcons.altArrowDown
                                : SolarLinearIcons.altArrowUp,
                            size: 16,
                          ),
                      ],
                    );
                  }

                  final Widget cellContainer = Container(
                    width: ViewerConstants.cellWidth,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: isDark ? Colors.white24 : Colors.grey[300]!,
                        ),
                      ),
                    ),
                    child: cellContent,
                  );

                  if (isHeader) {
                    return InkWell(
                      onTap: () => _onColumnTapped(colIndex),
                      child: cellContainer,
                    );
                  }

                  return cellContainer;
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _shareCsv(BuildContext context) async {
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

  Future<void> _saveCsv(BuildContext context) async {
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
