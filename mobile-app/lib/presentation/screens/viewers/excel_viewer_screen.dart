import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/sharing_service.dart';
import '../../widgets/custom_dialog.dart';

// Memory optimization: Max file size before showing warning (10MB)
const int kMaxExcelFileSizeWarning = 10 * 1024 * 1024;
// Max rows to render at once for performance
const int kMaxRowsPerPage = 100;

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
  List<Map<String, dynamic>> _dataWithIndex = [];  // Preserve original order

  @override
  void initState() {
    super.initState();
    _loadExcel();
  }

  Future<void> _loadExcel() async {
    try {
      final file = File(widget.filePath);
      _fileSizeBytes = await file.length();
      
      // Show warning for large files
      if (_fileSizeBytes > kMaxExcelFileSizeWarning) {
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
        final sheet = excel.sheets[firstSheetName]!;
        
        // Convert sheet to list for pagination
        final sheetData = <List<excel_lib.CellValue?>>[];
        var maxColumns = 0;

        // Use iterateAllCells for memory-efficient reading
        for (var row in sheet.rows) {
          final cellRow = row.map((cell) => cell as excel_lib.CellValue?).toList();
          sheetData.add(cellRow);
          if (cellRow.length > maxColumns) maxColumns = cellRow.length;
        }
        
        // Store with original indices for stable sorting
        final dataWithIndex = <Map<String, dynamic>>[];
        for (var i = 0; i < sheetData.length; i++) {
          dataWithIndex.add({
            'index': i,
            'row': sheetData[i],
          });
        }
        
        final totalPages = (sheetData.length / kMaxRowsPerPage).ceil();
        
        setState(() {
          _excel = excel;
          _selectedSheet = firstSheetName;
          _currentSheetData = sheetData;
          _dataWithIndex = dataWithIndex;
          _filteredData = sheetData.take(kMaxRowsPerPage).toList();
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

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _currentPage = 0;  // Reset to first page on search
    });
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    var rest = _dataWithIndex.skip(1).toList();

    // Apply filter
    if (_searchQuery.isNotEmpty) {
      rest = rest
          .where((entry) {
            final row = entry['row'] as List<excel_lib.CellValue>;
            return row.any((cell) =>
              (cell.toString().toLowerCase().contains(_searchQuery))
            );
          })
          .toList();
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

    final totalPages = (rest.length / kMaxRowsPerPage).ceil();
    final startIndex = _currentPage * kMaxRowsPerPage;
    final endIndex = (startIndex + kMaxRowsPerPage).clamp(0, rest.length);
    
    setState(() {
      _filteredData = [
        _dataWithIndex.first['row'] as List<excel_lib.CellValue>,  // Header
        ...rest.skip(startIndex).take(endIndex - startIndex).map((e) => e['row'] as List<excel_lib.CellValue>),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Show size warning dialog on first load
    if (_showSizeWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          CustomDialog.show(
            context,
            title: 'ملف كبير',
            message:
                'حجم الملف ${(_fileSizeBytes / 1024 / 1024).toStringAsFixed(1)} ميجابايت. '
                'قد يستغرق التحميل وقتاً طويلاً.',
            type: DialogType.warning,
            confirmText: 'متابعة',
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
                  hintText: 'بحث...',
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
                      'صفحة ${_currentPage + 1} / $_totalPages (${_filteredData.length} صف)',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
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
              icon: Icon(SolarLinearIcons.magnifer),
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
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    SolarLinearIcons.dangerCircle,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'فشل تحميل ملف Excel',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          : Column(
              children: [
                if (_excel!.sheets.keys.length > 1) _buildSheetSelector(isDark),
                Expanded(
                  child: _selectedSheet != null
                      ? _buildSheetTable(_selectedSheet!, isDark)
                      : const Center(child: Text('لا يوجد بيانات')),
                ),
                // Pagination controls
                if (_totalPages > 1) _buildPaginationControls(isDark),
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
            tooltip: 'الصفحة السابقة',
          ),
          const SizedBox(width: 16),
          Text(
            'صفحة ${_currentPage + 1} من $_totalPages',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(SolarLinearIcons.arrowRight, size: 20),
            onPressed: _currentPage < _totalPages - 1 ? () => _changePage(1) : null,
            tooltip: 'الصفحة التالية',
          ),
        ],
      ),
    );
  }

  Widget _buildSheetSelector(bool isDark) {
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
                  setState(() {
                    _selectedSheet = sheetName;
                    _isSearching = false;
                    _searchController.clear();
                    _searchQuery = '';
                    _sortColumnIndex = null;
                    _isAscending = true;
                  });
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
    final sheet = _excel!.sheets[sheetName]!;
    final allRows = sheet.rows;

    if (allRows.isEmpty) {
      return const Center(child: Text('هذه الورقة فارغة'));
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
      return const Center(child: Text('لا توجد نتائج'));
    }

    final maxColumns = sheet.maxColumns;
    const double cellWidth = 150.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: maxColumns * cellWidth,
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

                  Widget cellContainer = Container(
                    width: cellWidth,
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
          'خطأ: $e',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
