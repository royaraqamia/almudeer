import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart' as intl;
import 'package:hijri/hijri_calendar.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_gradient_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/customers_repository.dart';
import '../../../data/models/conversation.dart';
import '../../providers/customers_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/conversation_detail_provider.dart';
import '../../widgets/animated_toast.dart';
import '../../widgets/premium_bottom_sheet.dart';
import '../../widgets/premium_fab.dart';
import '../../widgets/customers/customer_contact_card.dart';
import '../inbox/conversation_detail_screen.dart';
import '../../../core/extensions/string_extension.dart';

// Constants for customer data keys - using snake_case (API convention)
const _kIsOnlineKey = 'is_online';
const _kLastSeenAtKey = 'last_seen_at';
const _kUsernameKey = 'username';
const _kNameKey = 'name';
const _kPhoneKey = 'phone';
const _kIdKey = 'id';
const _kProfilePicUrlKey = 'profile_pic_url';
const _kImageKey = 'image';
const _kIsVipKey = 'is_vip';

// Edit operation type to prevent race conditions
enum _EditOperationType { add, update }

/// Premium Customer detail screen with enhanced UI
class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  final CustomersRepository _repository = CustomersRepository();
  late Map<String, dynamic> _customer;
  bool _isLoadingFullDetails = false;

  // Controllers for editing
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;
  VoidCallback? _usernameLookupListener;
  bool _usernameListenerInitialized = false;

  // Animation controller for stagger animations
  late final AnimationController _animController;

  // Cached values to avoid context access during build
  bool? _isCurrentUser;
  bool? _isAlmudeerUser;
  bool? _isNewContact; // Cache isNewContact to avoid O(n) lookup on rebuild

  // Cancellation tracking for async operations
  bool _isDisposed = false;
  bool _isNavigating = false;

  // CustomersProvider listener reference for proper cleanup
  VoidCallback? _customersProviderListener;

  /// Check if this customer is the current logged-in user
  bool _checkIsCurrentUser(AuthProvider authProvider) {
    final currentUserUsername = authProvider.userInfo?.username;
    final customerUsername = _customer[_kUsernameKey]?.toString();
    final currentUserLicenseId = authProvider.userInfo?.licenseId?.toString();
    final customerLicenseId = _customer[_kIdKey]?.toString();

    if (currentUserUsername != null &&
        customerUsername != null &&
        currentUserUsername.toLowerCase() == customerUsername.toLowerCase()) {
      return true;
    }

    if (currentUserLicenseId != null &&
        customerLicenseId != null &&
        currentUserLicenseId == customerLicenseId) {
      return true;
    }

    return false;
  }

  /// Check if customer is an Almudeer user (supports both bool and int formats)
  bool _checkIsAlmudeerUser() {
    // Standardized to single snake_case key
    final value = _customer['is_almudeer_user'];
    return value == true || value == 1 || value == 'true' || value == '1';
  }

  /// Check if customer is online (supports both bool and int formats)
  bool _checkIsOnline() {
    final value = _customer[_kIsOnlineKey];
    return value == true || value == 1;
  }

  /// Check if customer is new (not in the saved customers list)
  /// Result is cached to avoid expensive O(n) lookup on every rebuild
  bool _checkIsNewContact() {
    try {
      final customerId = _customer[_kIdKey] as int?;
      final customerUsername = _customer[_kUsernameKey]?.toString();
      final customerPhone = _customer[_kPhoneKey]?.toString();

      final customersProvider = context.read<CustomersProvider>();
      return customerId != null
          ? !customersProvider.customers.any((c) => c.id == customerId)
          : customersProvider.getCustomerByContact(
              customerUsername ?? customerPhone,
            ) == null;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.e('Failed to check if new contact', error: e, stackTrace: stackTrace);
      }
      return true; // Assume new contact on error
    }
  }

  /// Get cached or compute isNewContact value
  bool _getIsNewContactCached() {
    _isNewContact ??= _checkIsNewContact();
    return _isNewContact!;
  }

  /// Invalidate the cached isNewContact value (call after save operations)
  void _invalidateNewContactCache() {
    _isNewContact = null;
  }

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;

    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _usernameController = TextEditingController();

    _setupUsernameLookupListener();

    _animController = AnimationController(
      duration: const Duration(milliseconds: AppDimensions.animationDurationSlow),
      vsync: this,
    );
    _animController.forward();

    // Listen to CustomersProvider changes to invalidate cache
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      // Store listener reference for proper cleanup (fixes memory leak)
      _customersProviderListener = _invalidateNewContactCache;
      context.read<CustomersProvider>().addListener(_customersProviderListener!);
    });

    // Cache values that depend on context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      setState(() {
        _isCurrentUser = _checkIsCurrentUser(authProvider);
        _isAlmudeerUser = _checkIsAlmudeerUser();
      });
      _subscribeToStatus();
      _loadFullDetails();
    });
  }

  void _setupUsernameLookupListener() {
    // Remove existing listener if present to avoid duplicates on rebuild
    if (_usernameListenerInitialized && _usernameLookupListener != null) {
      _usernameController.removeListener(_usernameLookupListener!);
    }

    _usernameListenerInitialized = true;

    _usernameLookupListener = () {
      if (!mounted || _isDisposed) return;
      final username = _usernameController.text.trim();
      if (username.isNotEmpty) {
        context.read<CustomersProvider>().lookupUsername(username);
      }
    };
    _usernameController.addListener(_usernameLookupListener!);
  }

  void _subscribeToStatus({bool immediate = false}) {
    if (_isAlmudeerUser != true) return;

    final username = _customer[_kUsernameKey] ?? _customer['senderContact'];
    if (username == null) return;

    final lastSeen = _customer[_kLastSeenAtKey];
    final isOnline = _checkIsOnline();

    void action() {
      if (mounted) {
        context.read<ConversationDetailProvider>().loadConversation(
          username.toString(),
          channel: 'almudeer',
          fresh: false,
          lastSeenAt: lastSeen,
          isOnline: isOnline,
        );
      }
    }

    if (immediate) {
      action();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => action());
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isNavigating = false;

    // Safely remove username listener only if initialized
    if (_usernameListenerInitialized && _usernameLookupListener != null) {
      _usernameController.removeListener(_usernameLookupListener!);
    }
    
    // Remove CustomersProvider listener using stored reference (fixes memory leak)
    try {
      if (mounted && _customersProviderListener != null) {
        context.read<CustomersProvider>().removeListener(_customersProviderListener!);
      }
    } catch (_) {
      // Provider might already be disposed, ignore
    }
    
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _animController.stop();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadFullDetails() async {
    final id = _customer[_kIdKey];
    if (id == null || _isLoadingFullDetails || _isDisposed) return;

    setState(() => _isLoadingFullDetails = true);

    try {
      final response = await _repository.getCustomerDetail(id as int);
      final fullDetails =
          (response.containsKey('customer') ? response['customer'] : response)
              as Map<String, dynamic>?;

      if (mounted && !_isDisposed && fullDetails != null) {
        setState(() {
          _customer = fullDetails;
          _isAlmudeerUser = _checkIsAlmudeerUser();
          _invalidateNewContactCache(); // Refresh cache with new data
        });
      }
    } catch (e, stackTrace) {
      // Log error for debugging instead of silent failure
      if (kDebugMode) {
        Logger.e('Failed to load customer details', error: e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isLoadingFullDetails = false);
      }
    }
  }

  String get _displayName {
    return _customer[_kNameKey] ??
        _customer[_kPhoneKey] ??
        'شخص';
  }

  String _formatLastSeen(String? lastSeenAt) {
    if (lastSeenAt == null || lastSeenAt.isEmpty) return '';
    try {
      var date = DateTime.parse(lastSeenAt);
      if (!lastSeenAt.endsWith('Z') && !lastSeenAt.contains('+')) {
        date = DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
      }
      final localDate = date.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDate);

      if (difference.isNegative) {
        return 'نشط الآن';
      }
      if (difference.inMinutes < 1) {
        return 'نشط منذ ثوانٍ';
      } else if (difference.inMinutes < 60) {
        return 'نشط منذ ${difference.inMinutes} دقيقة';
      } else if (localDate.year == now.year &&
          localDate.month == now.month &&
          localDate.day == now.day) {
        return 'آخر ظهور اليوم ${intl.DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers}';
      } else if (localDate.year == now.year &&
          localDate.month == now.month &&
          localDate.day == now.day - 1) {
        return 'آخر ظهور أمس ${intl.DateFormat.jm('ar_AE').format(localDate).toEnglishNumbers}';
      } else {
        try {
          final hijri = HijriCalendar.fromDate(localDate);
          return 'آخر ظهور ${hijri.toFormat("dd/mm/yyyy").toEnglishNumbers}';
        } catch (hijriError) {
          // Fallback to Gregorian date if Hijri conversion fails
          return 'آخر ظهور ${intl.DateFormat.yMd('ar_AE').format(localDate).toEnglishNumbers}';
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.e('Failed to format last seen date', error: e, stackTrace: stackTrace);
      }
      return 'آخر ظهور غير معروف';
    }
  }

  Future<void> _openEditCustomer() async {
    Haptics.lightTap();
    final customersProvider = context.read<CustomersProvider>();
    customersProvider.clearUsernameLookup();

    _nameController.text = _customer[_kNameKey] ?? '';
    _phoneController.text = _customer[_kPhoneKey] ?? '';
    _usernameController.text = _customer[_kUsernameKey] ?? '';

    final String initialName = _customer[_kNameKey] ?? '';
    final String initialPhone = _customer[_kPhoneKey] ?? '';
    final String initialUsername = _customer[_kUsernameKey] ?? '';

    // Calculate operation type ONCE at modal open time to prevent race conditions
    final bool wasNewContact = _getIsNewContactCached();
    final operationType = wasNewContact ? _EditOperationType.add : _EditOperationType.update;

    final result = await PremiumBottomSheet.show<dynamic>(
      context: context,
      title: wasNewContact ? 'إضافة' : 'تعديل',
      child: StatefulBuilder(
        builder: (context, setModalState) {
          bool hasChanges() {
            if (wasNewContact) return _nameController.text.trim().isNotEmpty;
            return _nameController.text.trim() != initialName ||
                _phoneController.text.trim() != initialPhone ||
                _usernameController.text.trim() != initialUsername;
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                _nameController,
                'الاسم',
                SolarLinearIcons.user,
                onChanged: (_) => setModalState(() {}),
              ),
              const SizedBox(height: AppDimensions.spacing16),
              Consumer<CustomersProvider>(
                builder: (context, provider, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        controller: _usernameController,
                        hintText: 'معرِّف الشَّخص على التَّطبيق',
                        onChanged: (_) => setModalState(() {}),
                        prefixIcon: const Icon(
                          SolarLinearIcons.userId,
                          color: AppColors.primary,
                        ),
                        suffixIcon: provider.isCheckingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(AppDimensions.spacing12),
                                child: SizedBox(
                                  width: AppDimensions.iconLarge,
                                  height: AppDimensions.iconLarge,
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
                                size: AppDimensions.iconLarge,
                              )
                            : provider.usernameNotFound &&
                                  _usernameController.text.length >= 3
                            ? const Icon(
                                SolarBoldIcons.closeCircle,
                                color: AppColors.error,
                                size: AppDimensions.iconLarge,
                              )
                            : null,
                      ),
                      if (provider.foundUsernameDetails != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppDimensions.spacing8,
                            right: AppDimensions.spacing12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                SolarLinearIcons.infoCircle,
                                size: AppDimensions.iconSmall,
                                color: AppColors.success.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: AppDimensions.spacing4),
                              Text(
                                'تمَّ العثور على: ${provider.foundUsernameDetails}',
                                style: TextStyle(
                                  fontSize: AppDimensions.spacing12,
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
                          padding: const EdgeInsets.only(
                            top: AppDimensions.spacing8,
                            right: AppDimensions.spacing12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                SolarLinearIcons.infoCircle,
                                size: AppDimensions.iconSmall,
                                color: AppColors.error.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: AppDimensions.spacing4),
                              Text(
                                'لم يتم العثور على شخص بهذا المعرِّف',
                                style: TextStyle(
                                  fontSize: AppDimensions.spacing12,
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
              const SizedBox(height: AppDimensions.spacing16),
              _buildTextField(
                _phoneController,
                'رقم الهاتف (اختياري)',
                SolarLinearIcons.phone,
                onChanged: (_) => setModalState(() {}),
              ),
              const SizedBox(height: AppDimensions.spacing16),
              AppGradientButton(
                onPressed: hasChanges()
                    ? () async {
                        Haptics.mediumTap();
                        Navigator.of(context).pop(true);
                      }
                    : null,
                text: wasNewContact ? 'إضافة' : 'حفظ التَّغييرات',
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      // Pass the operation type determined at modal open time
      await _saveCustomerDetails(operationType);
    }
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return AppTextField(
      controller: controller,
      maxLines: maxLines,
      hintText: label,
      onChanged: onChanged,
      prefixIcon: Icon(icon, color: AppColors.primary),
    );
  }

  Future<void> _saveCustomerDetails(_EditOperationType operationType) async {
    // Validate inputs before proceeding
    final nameValidation = Validators.validateName(_nameController.text.trim());
    if (!nameValidation.isValid) {
      AnimatedToast.error(context, nameValidation.errorMessage ?? 'الاسم غير صالح');
      return;
    }

    final phoneValidation = Validators.validatePhone(_phoneController.text.trim());
    if (!phoneValidation.isValid) {
      AnimatedToast.error(context, phoneValidation.errorMessage ?? 'رقم الهاتف غير صالح');
      return;
    }

    final usernameValidation = Validators.validateUsername(_usernameController.text.trim());
    if (!usernameValidation.isValid) {
      AnimatedToast.error(context, usernameValidation.errorMessage ?? 'المعرِّف غير صالح');
      return;
    }

    try {
      // Sanitize inputs
      final data = {
        _kNameKey: _nameController.text.trim().isEmpty
            ? null
            : Validators.sanitizeUsername(_nameController.text.trim()),
        _kPhoneKey: _phoneController.text.trim().isEmpty
            ? null
            : Validators.sanitizePhone(_phoneController.text.trim()),
        _kUsernameKey: _usernameController.text.trim().isEmpty
            ? null
            : Validators.sanitizeUsername(_usernameController.text.trim()),
      };

      final customerId = _customer[_kIdKey] as int?;

      Map<String, dynamic> response;
      // Use the operation type determined at modal open time (prevents race conditions)
      if (operationType == _EditOperationType.update && customerId != null) {
        response = await _repository.updateCustomer(customerId, data);
      } else {
        response = await _repository.addCustomer(data);
      }

      final isSuccess =
          response['success'] == true ||
          response.containsKey('customer') ||
          response.containsKey(_kIdKey);

      if (mounted && !_isDisposed && isSuccess) {
        final savedCustomer =
            (response['customer'] ?? response) as Map<String, dynamic>;

        final newId = savedCustomer[_kIdKey] ?? response[_kIdKey];

        setState(() {
          _customer = {..._customer, ...data, ...savedCustomer};
          if (newId != null) _customer[_kIdKey] = newId;
          // Update cached values
          _isAlmudeerUser = _checkIsAlmudeerUser();
          _invalidateNewContactCache(); // Invalidate cache after save
        });

        // Defer provider update to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDisposed) return;
          try {
            if (operationType == _EditOperationType.update && customerId != null) {
              context.read<CustomersProvider>().updateCustomerInList(_customer);
            } else {
              context.read<CustomersProvider>().refresh();
            }
          } catch (e, stackTrace) {
            Logger.e('Failed to update provider after save', error: e, stackTrace: stackTrace);
          }
        });

        AnimatedToast.success(
          context,
          operationType == _EditOperationType.update && customerId != null
              ? 'تمَّ تحديث البيانات بنجاح'
              : 'تمَّت الإضافة بنجاح',
        );
      } else if (mounted && !_isDisposed) {
        // Provide more context in error message
        final errorMessage = response['error']?.toString() ?? 
            response['message']?.toString() ??
            (operationType == _EditOperationType.update && customerId != null
                ? 'فشل تحديث البيانات - تأكد من اتصالك بالإنترنت'
                : 'فشلت الإضافة - تأكد من اتصالك بالإنترنت');
        AnimatedToast.error(context, errorMessage);
      }
    } catch (e, stackTrace) {
      Logger.e('Error saving customer details', error: e, stackTrace: stackTrace);
      if (mounted && !_isDisposed) {
        // Provide more context about the error
        final errorType = e.toString().contains('SocketException') || e.toString().contains('Network')
            ? 'تحقق من اتصالك بالإنترنت وحاول مرة أخرى'
            : 'حدث خطأ أثناء حفظ البيانات - حاول مرة أخرى';
        AnimatedToast.error(context, errorType);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVip = _customer[_kIsVipKey] == true || _customer[_kIsVipKey] == 1;

    return Scaffold(
      floatingActionButton: _isCurrentUser == true
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + AppDimensions.spacing24,
              ),
              child: Semantics(
                label: _getIsNewContactCached() ? 'إضافة شخص' : 'تعديل الشخص',
                button: true,
                child: PremiumFAB(
                  heroTag: 'customer_detail_edit_fab',
                  standalone: false,
                  gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
                  onPressed: _openEditCustomer,
                  icon: Icon(
                    _getIsNewContactCached() ? SolarBoldIcons.userPlus : SolarBoldIcons.pen,
                    color: Colors.white,
                    size: AppDimensions.iconXXLarge,
                  ),
                ),
              ),
            ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Semantics(
          label: 'رجوع',
          button: true,
          child: IconButton(
            icon: const Icon(SolarLinearIcons.arrowRight, size: AppDimensions.iconXLarge),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'رجوع',
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMedium,
          vertical: AppDimensions.paddingSmall,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnimatedSection(
              delay: 0.0,
              child: _buildPremiumHeaderCard(theme, isVip),
            ),
            const SizedBox(height: AppDimensions.spacing24),
            _buildAnimatedSection(
              delay: 0.1,
              child: CustomerContactCard(customer: _customer),
            ),
            const SizedBox(height: AppDimensions.spacing80),
          ],
        ),
      ),
    );
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
            offset: Offset(0, AppDimensions.spacing20 * (1 - animValue)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPremiumHeaderCard(ThemeData theme, bool isVip) {
    final isDark = theme.brightness == Brightness.dark;
    // Fix null safety: properly handle all null cases for avatar hero tag
    final avatarHeroTag = 'avatar_${_customer[_kUsernameKey]?.toString() ?? _customer[_kIdKey]?.toString() ?? _customer[_kPhoneKey]?.toString() ?? 'unknown'}';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: avatarHeroTag,
            child: _buildPremiumAvatar(theme, isVip, isDark),
          ),
          const SizedBox(height: AppDimensions.spacing16),
          Text(
            _displayName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
            textAlign: TextAlign.center,
          ),
          if (_isAlmudeerUser == true) ...[
            Consumer<ConversationDetailProvider>(
              builder: (context, provider, _) {
                final isTyping = provider.isPeerTyping;
                final isRecording = provider.isPeerRecording;
                final isOnline = provider.isPeerOnline;
                final lastSeen =
                    provider.peerLastSeen ?? _customer[_kLastSeenAtKey];

                Widget? statusWidget;
                if (isTyping) {
                  statusWidget = Text(
                    'يكتب...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.primaryColor,
                      fontSize: AppDimensions.spacing12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else if (isRecording) {
                  statusWidget = Text(
                    'يسجِّل مقطع صوتي...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.primaryColor,
                      fontSize: AppDimensions.spacing12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else if (isOnline) {
                  statusWidget = Text(
                    'متَّصل الآن',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.primaryColor,
                      fontSize: AppDimensions.spacing12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else {
                  final formatted = _formatLastSeen(lastSeen);
                  if (formatted.isNotEmpty) {
                    statusWidget = Text(
                      formatted,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontSize: AppDimensions.spacing12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }
                }

                if (statusWidget == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: AppDimensions.spacing4),
                  child: statusWidget,
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacing16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: AppDimensions.spacing100 + AppDimensions.spacing40,
                  child: AppGradientButton(
                    onPressed: _isCurrentUser == true
                        ? _navigateToSavedMessages
                        : _navigateToInternalChat,
                    text: _isCurrentUser == true ? 'رسائلي' : 'مراسلة',
                    icon: _isCurrentUser == true
                        ? SolarBoldIcons.bookmark
                        : SolarBoldIcons.chatLine,
                    gradientColors: _isCurrentUser == true
                        ? const [Color(0xFF10B981), Color(0xFF059669)]
                        : const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _navigateToInternalChat() async {
    // Prevent double-tap navigation
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final usernameObj = _customer[_kUsernameKey];

      // Validate username is a String type
      final String? username;
      if (usernameObj is String) {
        username = usernameObj.isEmpty ? null : usernameObj;
      } else if (usernameObj != null) {
        // Try to convert to string, but validate it's not an object
        final converted = usernameObj.toString();
        username = converted.isEmpty || converted == 'null' ? null : converted;
      } else {
        username = null;
      }

      if (username == null || username.isEmpty) {
        AnimatedToast.error(context, 'لا يوجد معرِّف لهذا الشَّخص للمراسلة');
        return;
      }

      // Get avatar URL from customer data (prefer profile_pic_url, then image)
      final imageUrl =
          (_customer[_kProfilePicUrlKey] ?? _customer[_kImageKey]) as String?;

      final conversation = Conversation(
        id: -1,
        channel: 'almudeer',
        senderName: _customer[_kNameKey],
        senderContact: username,
        senderId: username,
        body: '',
        status: 'active',
        createdAt: DateTime.now().toIso8601String(),
        messageCount: 0,
        unreadCount: 0,
        avatarUrl: imageUrl,
        lastSeenAt: _customer[_kLastSeenAtKey],
        isOnline: _checkIsOnline(),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              ConversationDetailScreen(conversation: conversation),
        ),
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.e('Failed to navigate to chat', error: e, stackTrace: stackTrace);
      }
      if (mounted) {
        AnimatedToast.error(context, 'فشل فتح المحادثة');
      }
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
      _subscribeToStatus(immediate: true);
      _loadFullDetails();
    }
  }

  Future<void> _navigateToSavedMessages() async {
    // Prevent double-tap navigation
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final conversation = Conversation(
        id: -1,
        channel: 'almudeer',
        senderName: 'رسائلي المحفوظة',
        senderContact: '__saved_messages__',
        senderId: '__saved_messages__',
        body: '',
        status: 'active',
        createdAt: DateTime.now().toIso8601String(),
        messageCount: 0,
        unreadCount: 0,
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              ConversationDetailScreen(conversation: conversation),
        ),
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        Logger.e('Failed to navigate to saved messages', error: e, stackTrace: stackTrace);
      }
      if (mounted) {
        AnimatedToast.error(context, 'فشل فتح المحادثة');
      }
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  Widget _buildPremiumAvatar(ThemeData theme, bool isVip, bool isDark) {
    final imageUrl =
        (_customer[_kProfilePicUrlKey] ?? _customer[_kImageKey]) as String?;

    return AppAvatar(
      radius: AppDimensions.avatarLarge,
      imageUrl: imageUrl,
      customGradient: isVip
          ? [const Color(0xFFFBBF24), const Color(0xFFD97706)]
          : null,
      border: isVip
          ? Border.all(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
              width: 3,
            )
          : null,
    );
  }
}
