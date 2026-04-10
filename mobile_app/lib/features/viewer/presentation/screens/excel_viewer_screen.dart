import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/services/media_service.dart';
import 'package:almudeer_mobile_app/core/utils/premium_toast.dart';
import 'package:almudeer_mobile_app/core/constants/viewer_constants.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/services/sharing_service.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';

class ExcelViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ExcelViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

class _ExcelViewerScreenState extends State<ExcelViewerScreen> {
  excel_lib.Excel? _excel;
  String? _selectedSheet;
  bool _isLoading = true;
  String? _error;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _sortColumnIndex;
  bool _isAscending = true;
  int _fileSizeBytes = 0;
  bool _showSizeWarning = false;

  // Pagination for large sheets
  int _currentPage = 0;
  int _totalPages = 0;
  List<List<excel_lib.CellValue?>> _currentSheetData = [];
  List<List<excel_lib.CellValue?>> _filteredData = [];
  List<Map<String, dynamic>> _dataWithIndex = [];

  // Retry logic
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _loadExcel();
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Clear large data structures on dispose to free memory
    _dataWithIndex.clear();
    _filteredData.clear();
    _currentSheetData.clear();
    _excel = null;
    super.dispose();
  }

  Future<void> _loadExcel() async {
    try {
      final file = File(widget.filePath);

      // Check if file exists
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = ViewerErrorType.fileNotFound.message;
          });
        }
        return;
      }

      // Check file size (hard limit)
      _fileSizeBytes = await file.length();
      if (_fileSizeBytes > ViewerConstants.maxExcelFileSize) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error =
                'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ظƒط¨ظٹط± ط¬ط¯ط§ظ‹ (${(_fileSizeBytes / 1024 / 1024).toStringAsFixed(1)} ظ…ظٹط¬ط§ط¨ط§ظٹطھ). ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ‡ظˆ ${ViewerConstants.maxExcelFileSize ~/ 1024 ~/ 1024} ظ…ظٹط¬ط§ط¨ط§ظٹطھ';
          });
        }
        return;
      }

      // Check available memory before loading large files
      // This is a heuristic based on file size
      if (_fileSizeBytes > ViewerConstants.maxExcelFileSizeWarning) {
        // Show warning but still load
        if (mounted) {
          setState(() {
            _showSizeWarning = true;
          });
        }
      }

      final bytes = await file.readAsBytes();
      final excel = excel_lib.Excel.decodeBytes(bytes);

      if (mounted) {
        // Load only first sheet initially to save memory
        final firstSheetName = excel.sheets.keys.first;
        final sheet = excel.sheets[firstSheetName];
        if (sheet == null) {
          setState(() {
            _isLoading = false;
            _error = 'ط§ظ„ظˆط±ظ‚ط© ظپط§ط±ط؛ط©';
          });
          return;
        }

        // Convert sheet to list for pagination
        final sheetData = <List<excel_lib.CellValue?>>[];

        // Use iterateAllCells for memory-efficient reading
        for (var row in sheet.rows) {
          final cellRow = row
              .map((cell) => cell as excel_lib.CellValue?)
              .toList();
          sheetData.add(cellRow);
        }

        // Store with original indices for stable sorting
        final dataWithIndex = <Map<String, dynamic>>[];
        for (var i = 0; i < sheetData.length; i++) {
          dataWithIndex.add({'index': i, 'row': sheetData[i]});
        }

        final totalPages = (sheetData.length / ViewerConstants.defaultRowsPerPage).ceil();

        setState(() {
          _excel = excel;
          _selectedSheet = firstSheetName;
          _currentSheetData = sheetData;
          _dataWithIndex = dataWithIndex;
          _filteredData = sheetData.take(ViewerConstants.defaultRowsPerPage).toList();
          _totalPages = totalPages;
          _currentPage = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
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
      _showSizeWarning = false;
    });

    Future.delayed(delay, () {
      if (mounted) {
        _loadExcel();
      }
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _currentPage = 0;
    });
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    if (_dataWithIndex.isEmpty) return;

    var rest = _dataWithIndex.skip(1).toList();

    // Apply filter
    if (_searchQuery.isNotEmpty) {
      rest = rest.where((entry) {
        final row = entry['row'] as List<excel_lib.CellValue>;
        return row.any(
          (cell) => (cell.toString().toLowerCase().contains(_searchQuery)),
        );
      }).toList();
    }

    // Apply sort with stable ordering
    if (_sortColumnIndex != null) {
      rest.sort((a, b) {
        final rowA = a['row'] as List<excel_lib.CellValue>;
        final rowB = b['row'] as List<excel_lib.CellValue>;
        final indexA = a['index'] as int;
        final indexB = b['index'] as int;

        final valA = _sortColumnIndex! < rowA.length
            ? (rowA[_sortColumnIndex!].toString())
            : '';
        final valB = _sortColumnIndex! < rowB.length
            ? (rowB[_sortColumnIndex!].toString())
            : '';

        int comparison;
        final numA = double.tryParse(valA);
        final numB = double.tryParse(valB);

        if (numA != null && numB != null) {
          comparison = numA.compareTo(numB);
        } else {
          comparison = valA.compareTo(valB);
        }

        // Stable sort: preserve original order for equal values
        if (comparison == 0) {
          return indexA.compareTo(indexB);
        }

        return _isAscending ? comparison : -comparison;
      });
    }

    final totalPages = (rest.length / ViewerConstants.defaultRowsPerPage).ceil();
    final startIndex = _currentPage * ViewerConstants.defaultRowsPerPage;
    final endIndex = (startIndex + ViewerConstants.defaultRowsPerPage).clamp(0, rest.length);

    setState(() {
      _filteredData = [
        _dataWithIndex.first['row'] as List<excel_lib.CellValue>,
        ...rest
            .skip(startIndex)
            .take(endIndex - startIndex)
            .map((e) => e['row'] as List<excel_lib.CellValue>),
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

  // Reset search state when changing sheets
  void _changeSheet(String sheetName) {
    setState(() {
      _selectedSheet = sheetName;
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
      _sortColumnIndex = null;
      _isAscending = true;
      _currentPage = 0;
    });
    _applyFilterAndSort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Show size warning dialog on first load
    if (_showSizeWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _error == null) {
          CustomDialog.show(
            context,
            title: 'ظ…ظ„ظپ ظƒط¨ظٹط±',
            message:
                'ط­ط¬ظ… ط§ظ„ظ…ظ„ظپ ${(_fileSizeBytes / 1024 / 1024).toStringAsFixed(1)} ظ…ظٹط¬ط§ط¨ط§ظٹطھ. '
                'ظ‚ط¯ ظٹط³طھط؛ط±ظ‚ ط§ظ„طھط­ظ…ظٹظ„ ظˆظ‚طھط§ظ‹ ط·ظˆظٹظ„ط§ظ‹.',
            type: DialogType.warning,
            confirmText: 'ظ…طھط§ط¨ط¹ط©',
            onCancel: () {
              setState(() => _showSizeWarning = false);
            },
          );
        }
      });
    }

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
                  if (_currentSheetData.isNotEmpty)
                    Text(
                      'طµظپط­ط© ${_currentPage + 1} / $_totalPages (${_filteredData.length} طµظپ)',
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
                _searchQuery = '';
                _applyFilterAndSort();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(SolarLinearIcons.magnifer),
              onPressed: () => setState(() => _isSearching = true),
            ),
          IconButton(
            icon: const Icon(SolarLinearIcons.share),
            onPressed: () => _shareFile(context),
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.download),
            onPressed: () => _saveFile(context),
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
          : Column(
              children: [
                if (_excel != null && _excel!.sheets.keys.length > 1)
                  _buildSheetSelector(isDark),
                Expanded(
                  child: _selectedSheet != null
                      ? _buildSheetTable(_selectedSheet!, isDark)
                      : const Center(child: Text('ظ„ط§ ظٹظˆط¬ط¯ ط¨ظٹط§ظ†ط§طھ')),
                ),
                if (_totalPages > 1) _buildPaginationControls(isDark),
              ],
            ),
    );
  }

  Widget _buildErrorView() {
    final canRetry = _retryCount < ViewerConstants.maxRetries && _error != null;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            SolarLinearIcons.dangerCircle,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            'ظپط´ظ„ طھط­ظ…ظٹظ„ ظ…ظ„ظپ Excel',
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

  Widget _buildSheetSelector(bool isDark) {
    if (_excel == null) return const SizedBox();

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _excel!.sheets.keys.map((sheetName) {
          final isSelected = _selectedSheet == sheetName;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(sheetName),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _changeSheet(sheetName);
                }
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSheetTable(String sheetName, bool isDark) {
    final sheet = _excel?.sheets[sheetName];
    if (sheet == null) {
      return const Center(child: Text('ظ‡ط°ظ‡ ط§ظ„ظˆط±ظ‚ط© ظپط§ط±ط؛ط©'));
    }

    final allRows = sheet.rows;

    if (allRows.isEmpty) {
      return const Center(child: Text('ظ‡ط°ظ‡ ط§ظ„ظˆط±ظ‚ط© ظپط§ط±ط؛ط©'));
    }

    // Filter rows based on search and sort
    List<List<excel_lib.Data?>> filteredRows = allRows;
    final hasHeader = allRows.isNotEmpty;
    final header = hasHeader ? [allRows.first] : <List<excel_lib.Data?>>[];
    var rest = hasHeader ? allRows.skip(1).toList() : <List<excel_lib.Data?>>[];

    if (_searchQuery.isNotEmpty) {
      rest = rest
          .where(
            (row) => row.any(
              (cell) => (cell?.value?.toString() ?? '').toLowerCase().contains(
                _searchQuery,
              ),
            ),
          )
          .toList();
    }

    if (_sortColumnIndex != null) {
      rest.sort((a, b) {
        final valA = _sortColumnIndex! < a.length
            ? (a[_sortColumnIndex!]?.value?.toString() ?? '')
            : '';
        final valB = _sortColumnIndex! < b.length
            ? (b[_sortColumnIndex!]?.value?.toString() ?? '')
            : '';

        final numA = double.tryParse(valA);
        final numB = double.tryParse(valB);

        int comparison;
        if (numA != null && numB != null) {
          comparison = numA.compareTo(numB);
        } else {
          comparison = valA.compareTo(valB);
        }

        return _isAscending ? comparison : -comparison;
      });
    }

    filteredRows = [...header, ...rest];

    if (filteredRows.isEmpty) {
      return const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ظ†طھط§ط¦ط¬'));
    }

    final maxColumns = sheet.maxColumns;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: maxColumns * ViewerConstants.cellWidth,
        child: ListView.builder(
          itemCount: filteredRows.length,
          itemBuilder: (context, index) {
            final rowCells = filteredRows[index];
            final isHeader = allRows.isNotEmpty && rowCells == allRows.first;

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
                children: List.generate(maxColumns, (colIndex) {
                  final cell = colIndex < rowCells.length
                      ? rowCells[colIndex]
                      : null;
                  final value = cell?.value?.toString() ?? '';

                  Widget cellContent = Text(
                    value,
                    style: TextStyle(
                      fontWeight: isHeader
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black,
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
                            color: isDark ? Colors.white : Colors.black,
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
                      onTap: () {
                        if (_sortColumnIndex == colIndex) {
                          setState(() {
                            _isAscending = !_isAscending;
                          });
                        } else {
                          setState(() {
                            _sortColumnIndex = colIndex;
                            _isAscending = true;
                          });
                        }
                      },
                      child: cellContainer,
                    );
                  }

                  return cellContainer;
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _shareFile(BuildContext context) async {
    SharingService().showShareMenu(
      context,
      filePath: widget.filePath,
      title: widget.fileName,
      type: 'document',
    );
  }

  Future<void> _saveFile(BuildContext context) async {
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
          'ط®ط·ط£: $e',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
