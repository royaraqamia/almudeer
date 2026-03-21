import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../widgets/animated_toast.dart';
import '../../widgets/common_widgets.dart';
import '../../../data/repositories/customers_repository.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_avatar.dart'; // Added AppAvatar import

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key});

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  final CustomersRepository _repository = CustomersRepository();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  Set<String> _existingPhones = {};
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isImporting = false;
  bool _permissionDenied = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() => _isLoading = true);

    try {
      // Request permission using permission_handler
      final contactsPermission = await Permission.contacts.request();
      final permissionGranted = contactsPermission.isGranted;

      if (permissionGranted) {
        // Fetch existing phones for duplicate detection
        final existingPhones = await _repository.getAllCustomerPhones();

        // Fetch contacts with properties to detect WhatsApp/Telegram
        final contacts = await FlutterContacts.getAll(
          properties: {
            ContactProperty.name,
            ContactProperty.phone,
            ContactProperty.organization,
          },
        );

        if (mounted) {
          setState(() {
            _contacts = contacts;
            _filteredContacts = contacts;
            _existingPhones = existingPhones;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching contacts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // You might want to show an error message or set _permissionDenied = true as fallback
          AnimatedToast.error(context, 'حدث خطأ في تحميل أرقام الهواتف: $e');
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _applyFilter() {
    _filteredContacts = _contacts.where((contact) {
      final displayName = contact.displayName ?? '';
      final matchesSearch =
          displayName.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          contact.phones.any((p) => p.number.contains(_searchQuery));

      return matchesSearch;
    }).toList();
  }

  void _toggleSelection(String id) {
    Haptics.selection();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    Haptics.mediumTap();
    setState(() {
      if (_selectedIds.length == _contacts.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_contacts.map((c) => c.id!).cast<String>());
      }
    });
  }

  double _importProgress = 0.0;

  Future<void> _importSelected() async {
    if (_selectedIds.isEmpty) return;

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
    });
    Haptics.mediumTap();

    int successCount = 0;
    int failCount = 0;

    final selectedContacts = _contacts
        .where((c) => c.id != null && _selectedIds.contains(c.id!))
        .toList();

    const int batchSize = 20;
    final int totalContacts = selectedContacts.length;

    for (int i = 0; i < totalContacts; i += batchSize) {
      final end = (i + batchSize < totalContacts)
          ? i + batchSize
          : totalContacts;
      final batch = selectedContacts.sublist(i, end);

      // Process batch
      final results = await Future.wait(
        batch.map((contact) async {
          if (contact.phones.isEmpty) return false;

          try {
            final phone = contact.phones.first.number
                .replaceAll(RegExp(r'\s+'), '') // Remove spaces
                .replaceAll('-', '');

            final customerData = {
              'name': contact.displayName ?? 'Unknown',
              'phone': phone,
              'company': contact.organizations.isNotEmpty
                  ? contact.organizations.first.name
                  : null,
              'has_whatsapp': false,
              'has_telegram': false,
              'notes': 'Imported from contacts',
              'tags': 'imported',
            };

            await _repository.addCustomer(customerData);
            return true;
          } catch (e) {
            debugPrint('Failed to import ${contact.displayName}: $e');
            return false;
          }
        }),
      );

      successCount += results.where((r) => r == true).length;
      failCount += results.where((r) => r == false).length;

      if (mounted) {
        setState(() {
          _importProgress = end / totalContacts;
        });
      }
    }

    setState(() => _isImporting = false);

    if (mounted) {
      if (successCount > 0) {
        AnimatedToast.success(
          context,
          'تمَّ استيراد $successCount رقم هاتف بنجاح',
        );
        Navigator.pop(context, true); // Return true to refresh list
      } else if (failCount > 0) {
        AnimatedToast.error(context, 'فشل الاستيراد');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor.withValues(
          alpha: 0.8,
        ), // Translucent
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        centerTitle: true,
        title: Text(
          'استيراد أرقام الهواتف',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500, // Medium weight
            letterSpacing: -0.5,
          ),
        ),
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_contacts.isNotEmpty && !_isLoading && !_permissionDenied)
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: () {
                  Haptics.lightTap();
                  _selectAll();
                },
                child: Text(
                  _selectedIds.length == _filteredContacts.length
                      ? 'إلغاء الكل'
                      : 'تحديد الكل',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isLoading && !_permissionDenied && _contacts.isNotEmpty)
            _buildPremiumHeader(theme, isDark),
          if (_isImporting)
            LinearProgressIndicator(
              value: _importProgress,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      floatingActionButton: _selectedIds.isNotEmpty && !_isImporting
          ? _buildFloatingImportButton(theme)
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildPremiumHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: AppTextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        hintText: 'بحث باسم أو رقم الهاتف...',
        prefixIcon: const Icon(SolarLinearIcons.magnifer, size: 20),
      ),
    );
  }

  Widget _buildFloatingImportButton(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isImporting ? null : _importSelected,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isImporting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(SolarLinearIcons.downloadSquare),
            const SizedBox(width: 12),
            Text(
              _isImporting
                  ? 'جاري الاستيراد... (${(_importProgress * 100).toInt()}%)'
                  : 'استيراد (${_selectedIds.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_permissionDenied) {
      return const EmptyStateWidget(icon: SolarLinearIcons.forbiddenCircle);
    }

    if (_isLoading) {
      // Use standard loading for now, or Shimmer if available
      return const Center(child: CircularProgressIndicator());
    }

    if (_contacts.isEmpty) {
      return const EmptyStateWidget(
        icon: SolarLinearIcons.usersGroupTwoRounded,
      );
    }

    if (_filteredContacts.isEmpty) {
      return const EmptyStateWidget(icon: SolarLinearIcons.magnifer);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        final phone = contact.phones.isNotEmpty
            ? contact.phones.first.number
                  .replaceAll(RegExp(r'\s+'), '')
                  .replaceAll('-', '')
            : '';

        final isAlreadyRegistered = _existingPhones.contains(phone);
        final contactId = contact.id ?? '';
        final isSelected = _selectedIds.contains(contactId);

        return _buildContactTile(contact, isAlreadyRegistered, isSelected);
      },
    );
  }

  Widget _buildContactTile(
    Contact contact,
    bool isAlreadyRegistered,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final displayName = contact.displayName ?? 'Unknown';
    final contactId = contact.id ?? '';

    return GestureDetector(
      onTap: isAlreadyRegistered ? null : () => _toggleSelection(contactId),
      child: Opacity(
        opacity: isAlreadyRegistered ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: 12,
          ),
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Row(
            children: [
              _buildAvatar(displayName, isSelected, isAlreadyRegistered),
              const SizedBox(width: AppDimensions.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isAlreadyRegistered
                                  ? theme.textTheme.bodySmall?.color
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : '',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 12,
                          ),
                        ),
                        if (isAlreadyRegistered) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.dividerColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Text(
                              'مسجَّل مسبقًا',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.textTheme.bodySmall?.color
                                    ?.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  SolarBoldIcons.checkCircle,
                  color: AppColors.primary,
                  size: 24,
                )
              else if (!isAlreadyRegistered)
                Icon(
                  Icons.radio_button_unchecked,
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, bool isSelected, bool isAlreadyRegistered) {
    if (isAlreadyRegistered) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.withValues(alpha: 0.2),
        child: const Icon(SolarLinearIcons.user, color: Colors.grey, size: 24),
      );
    }

    // Extract initials from name
    final initials = name.isNotEmpty
        ? name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : null;

    return AppAvatar(
      radius: 24,
      initials: initials,
      overlay: isSelected
          ? Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.check, color: Colors.white, size: 20),
                ),
              ),
            )
          : null,
    );
  }
}
