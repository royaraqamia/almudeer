import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/customers/data/models/customer.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/providers/customers_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/premium_fab.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/common_widgets.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/premium_bottom_sheet.dart';
import 'package:almudeer_mobile_app/core/widgets/app_text_field.dart';
import 'package:almudeer_mobile_app/core/widgets/app_gradient_button.dart';
import 'customer_detail_screen.dart';
import 'package:almudeer_mobile_app/features/contacts/presentation/screens/import_contacts_screen.dart';
import 'package:almudeer_mobile_app/features/customers/presentation/widgets/customers/premium_customer_tile.dart';

import 'package:hijri/hijri_calendar.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';

/// Premium Customers screen with enhanced UI
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  @override
  Widget build(BuildContext context) {
    return const _CustomersView();
  }
}

class _CustomersView extends StatefulWidget {
  const _CustomersView();

  @override
  State<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<_CustomersView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AppAnimations.slow, // Apple standard: 400ms (was 800ms)
      vsync: this,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String get _hijriDate {
    HijriCalendar.setLocal('ar');
    final hijriNow = HijriCalendar.now();
    return hijriNow.toFormat('DD, dd MMMM yyyy').toEnglishNumbers;
  }

  void _openCustomerDetail(Customer customer) {
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              CustomerDetailScreen(customer: customer.toJson()),
        ),
      );
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, 'ظپط´ظ„ ظپطھط­ طھظپط§طµظٹظ„ ط§ظ„ط´ط®طµ');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLoading = context.select((CustomersProvider p) => p.isLoading);

    if (!isLoading) {
      _animController.forward();
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: Selector<CustomersProvider, bool>(
        selector: (_, p) => p.isSelectionMode,
        builder: (context, isSelectionMode, _) {
          if (isSelectionMode) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(
              bottom: AppDimensions.bottomNavHeight + AppDimensions.spacing24,
              right: AppDimensions.spacing16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Sub-FAB for import
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF2D5A87)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Haptics.lightTap();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ImportContactsScreen(),
                          ),
                        );
                      },
                      customBorder: const CircleBorder(),
                      child: const Icon(
                        SolarLinearIcons.downloadMinimalistic,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // Main FAB for adding customer
                PremiumFAB(
                  heroTag: 'customers_fab',
                  standalone: false,
                  onPressed: () => _showAddCustomerSheet(context),
                  gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
                  icon: const Icon(
                    SolarBoldIcons.userPlus,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAnimatedSection(
              delay: 0.1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _hijriDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontSize: 14,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                    // Search removed - now global in app bar
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacing8),
            Expanded(child: _buildListContent(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildListContent(ThemeData theme) {
    return Consumer<CustomersProvider>(
      builder: (context, provider, _) {
        // Show cached data immediately - no skeleton loader
        if (provider.customers.isEmpty) {
          return _buildPremiumEmptyState(theme);
        }

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadCustomers(refresh: true);
          },
          color: AppColors.primary,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            itemCount:
                provider.customers.length + (provider.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == provider.customers.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                );
              }

              final customer = provider.customers[index];
              final isLast = index == provider.customers.length - 1;
              return _buildAnimatedSection(
                delay: 0.1 + (index * 0.03).clamp(0.0, 0.5),
                child: PremiumCustomerTile(
                  customer: customer,
                  onTap: () => _openCustomerDetail(customer),
                  isLast: isLast,
                  isSelected: provider.selectedIds.contains(customer.id),
                  isSelectionMode: provider.isSelectionMode,
                  onLongPress: () {
                    Haptics.heavyTap();
                    provider.toggleSelection(customer.id);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddCustomerSheet(BuildContext context) {
    Haptics.selection();
    final provider = context.read<CustomersProvider>();
    provider.clearUsernameLookup();

    PremiumBottomSheet.show(
      context: context,
      title: 'ط¥ط¶ط§ظپط© ط´ط®طµ ط¬ط¯ظٹط¯',
      child: _AddCustomerForm(provider: provider),
    );
  }

  Widget _buildPremiumEmptyState(ThemeData theme) {
    return const EmptyStateWidget(icon: SolarLinearIcons.usersGroupTwoRounded);
  }

  Widget _buildAnimatedSection({required double delay, required Widget child}) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final animValue = Curves.easeOutCubic.transform(
          (_animController.value - delay).clamp(0.0, 1.0 - delay) /
              (1.0 - delay).clamp(0.01, 1.0),
        );
        return Opacity(
          opacity: animValue.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animValue)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Form widget for adding a new customer
/// Manages its own TextEditingControllers to avoid disposal issues
class _AddCustomerForm extends StatefulWidget {
  final CustomersProvider provider;

  const _AddCustomerForm({required this.provider});

  @override
  State<_AddCustomerForm> createState() => _AddCustomerFormState();
}

class _AddCustomerFormState extends State<_AddCustomerForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _usernameController;
  VoidCallback? _usernameLookupListener;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _usernameController = TextEditingController();

    _usernameLookupListener = () {
      if (!mounted) return;
      final username = _usernameController.text.trim().replaceAll('@', '');
      if (username.isNotEmpty) {
        widget.provider.lookupUsername(username);
      }
    };
    _usernameController.addListener(_usernameLookupListener!);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_usernameLookupListener!);
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final bool canAdd = _nameController.text.trim().isNotEmpty;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _nameController,
              hintText: 'ط§ظ„ط§ط³ظ…',
              prefixIcon: const Icon(SolarLinearIcons.user),
              onChanged: (_) => setModalState(() {}),
            ),
            const SizedBox(height: 16),
            Consumer<CustomersProvider>(
              builder: (context, provider, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      controller: _usernameController,
                      hintText: 'ظ…ط¹ط±ظگظ‘ظپ ط§ظ„ط´ظژظ‘ط®طµ ط¹ظ„ظ‰ ط§ظ„طھظژظ‘ط·ط¨ظٹظ‚',
                      prefixIcon: const Icon(SolarLinearIcons.userCircle),
                      onChanged: (val) {
                        setModalState(() {});
                      },
                      suffixIcon: provider.isCheckingUsername
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : provider.foundUsernameDetails != null
                          ? const Icon(
                              SolarBoldIcons.checkCircle,
                              color: AppColors.success,
                              size: 20,
                            )
                          : provider.usernameNotFound
                          ? const Icon(
                              SolarBoldIcons.closeCircle,
                              color: AppColors.error,
                              size: 20,
                            )
                          : null,
                    ),
                    if (provider.foundUsernameDetails != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 12),
                        child: Row(
                          children: [
                            Icon(
                              SolarLinearIcons.infoCircle,
                              size: 14,
                              color: AppColors.success.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'طھظ…ظژظ‘ ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰: ${provider.foundUsernameDetails}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.success.withValues(
                                  alpha: 0.8,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (provider.usernameNotFound &&
                        _usernameController.text.length >= 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 12),
                        child: Row(
                          children: [
                            Icon(
                              SolarLinearIcons.infoCircle,
                              size: 14,
                              color: AppColors.error.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط´ط®طµ ط¨ظ‡ط°ط§ ط§ظ„ظ…ط¹ط±ظگظ‘ظپ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _phoneController,
              hintText: 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ (ط§ط®طھظٹط§ط±ظٹ)',
              prefixIcon: const Icon(SolarLinearIcons.phone),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setModalState(() {}),
            ),
            const SizedBox(height: 32),
            AppGradientButton(
              onPressed: !canAdd
                  ? null
                  : () async {
                      if (_nameController.text.isEmpty) {
                        AnimatedToast.error(context, 'ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ ط§ط³ظ… ط§ظ„ط´ط®طµ');
                        return;
                      }

                      Haptics.mediumTap();
                      final data = {
                        'name': _nameController.text,
                        'phone': _phoneController.text.isNotEmpty
                            ? _phoneController.text
                            : null,
                        'username': _usernameController.text.isNotEmpty
                            ? _usernameController.text
                            : null,
                      };

                      try {
                        final result = await widget.provider.addCustomer(data);
                        if (result['success'] == true && context.mounted) {
                          Navigator.pop(context);
                          AnimatedToast.success(
                            context,
                            result['message'] ?? 'طھظ…ظژظ‘طھ ط§ظ„ط¥ط¶ط§ظپط© ط¨ظ†ط¬ط§ط­',
                          );
                        } else if (context.mounted) {
                          AnimatedToast.error(
                            context,
                            result['error'] ??
                                result['message'] ??
                                'ظپط´ظ„طھ ط§ظ„ط¥ط¶ط§ظپط©',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          AnimatedToast.error(context, 'ظپط´ظ„طھ ط§ظ„ط¥ط¶ط§ظپط©');
                        }
                      }
                    },
              text: 'ط¥ط¶ط§ظپط©',
              gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
            ),
          ],
        );
      },
    );
  }
}
