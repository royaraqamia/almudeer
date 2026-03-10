import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:intl/intl.dart' as intl;
import 'package:hijri/hijri_calendar.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/dimensions.dart';
import '../../../core/utils/haptics.dart';
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

// Constants for customer data keys
const _kIsAlmudeerUserKeys = ['is_almudeer_user', 'isAlmudeerUser'];
const _kIsOnlineKey = 'is_online';
const _kLastSeenAtKey = 'last_seen_at';
const _kUsernameKey = 'username';
const _kNameKey = 'name';
const _kPhoneKey = 'phone';
const _kEmailKey = 'email';
const _kIdKey = 'id';
const _kProfilePicUrlKey = 'profile_pic_url';
const _kImageKey = 'image';
const _kIsVipKey = 'is_vip';

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
  bool _isSaving = false; // ignore: unused_field - used for UI state during save operations
  bool _isLoadingFullDetails = false;
  bool _isUsernameLookupEnabled = true;

  // Controllers for editing
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  VoidCallback? _usernameLookupListener;

  // Animation controller for stagger animations
  late final AnimationController _animController;

  // Cached values to avoid context access during build
  bool? _isCurrentUser;
  bool? _isAlmudeerUser;

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

  /// Check if customer is an Almudeer user (supports both key formats)
  bool _checkIsAlmudeerUser() {
    for (final key in _kIsAlmudeerUserKeys) {
      final value = _customer[key];
      if (value == true || value == 1) {
        return true;
      }
    }
    return false;
  }

  /// Check if customer is online (supports both bool and int formats)
  bool _checkIsOnline() {
    final value = _customer[_kIsOnlineKey];
    return value == true || value == 1;
  }

  /// Check if customer is new (not in the saved customers list)
  bool _checkIsNewContact() {
    final customerId = _customer[_kIdKey] as int?;
    final customerUsername = _customer[_kUsernameKey]?.toString();
    final customerPhone = _customer[_kPhoneKey]?.toString();
    final customerEmail = _customer[_kEmailKey]?.toString();

    final customersProvider = context.read<CustomersProvider>();
    return customerId != null
        ? !customersProvider.customers.any((c) => c.id == customerId)
        : customersProvider.getCustomerByContact(
            customerUsername ?? customerPhone ?? customerEmail,
          ) == null;
  }

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;

    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();

    _setupUsernameLookupListener();

    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _animController.forward();

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
    _usernameLookupListener = () {
      if (!_isUsernameLookupEnabled || !mounted) return;
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
    if (_usernameLookupListener != null) {
      _usernameController.removeListener(_usernameLookupListener!);
    }
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadFullDetails() async {
    final id = _customer[_kIdKey];
    if (id == null || _isLoadingFullDetails) return;

    setState(() => _isLoadingFullDetails = true);

    try {
      final response = await _repository.getCustomerDetail(id as int);
      final fullDetails =
          (response.containsKey('customer') ? response['customer'] : response)
              as Map<String, dynamic>?;

      if (mounted && fullDetails != null) {
        setState(() {
          _customer = fullDetails;
          _isAlmudeerUser = _checkIsAlmudeerUser();
        });
      }
    } catch (_) {
      // Ignore errors silently
    } finally {
      if (mounted) {
        setState(() => _isLoadingFullDetails = false);
      }
    }
  }

  String get _displayName {
    return _customer[_kNameKey] ??
        _customer[_kPhoneKey] ??
        _customer[_kEmailKey] ??
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
        final hijri = HijriCalendar.fromDate(localDate);
        return 'آخر ظهور ${hijri.toFormat("dd/mm/yyyy").toEnglishNumbers}';
      }
    } catch (e) {
      return 'آخر ظهور غير معروف';
    }
  }

  Future<void> _openEditCustomer() async {
    Haptics.lightTap();
    final customersProvider = context.read<CustomersProvider>();
    customersProvider.clearUsernameLookup();

    // Disable username lookup listener during modal
    setState(() => _isUsernameLookupEnabled = false);

    _nameController.text = _customer[_kNameKey] ?? '';
    _phoneController.text = _customer[_kPhoneKey] ?? '';
    _emailController.text = _customer[_kEmailKey] ?? '';
    _usernameController.text = _customer[_kUsernameKey] ?? '';

    final String initialName = _customer[_kNameKey] ?? '';
    final String initialPhone = _customer[_kPhoneKey] ?? '';
    final String initialEmail = _customer[_kEmailKey] ?? '';
    final String initialUsername = _customer[_kUsernameKey] ?? '';

    // Calculate isNewContact at modal open time (will be recalculated at save time)
    final bool wasNewContact = _checkIsNewContact();

    final result = await PremiumBottomSheet.show<dynamic>(
      context: context,
      title: wasNewContact ? 'إضافة' : 'تعديل',
      child: StatefulBuilder(
        builder: (context, setModalState) {
          bool hasChanges() {
            if (wasNewContact) return _nameController.text.trim().isNotEmpty;
            return _nameController.text.trim() != initialName ||
                _phoneController.text.trim() != initialPhone ||
                _emailController.text.trim() != initialEmail ||
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
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
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
                            : provider.usernameNotFound &&
                                  _usernameController.text.length >= 3
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
                                'تمَّ العثور على: ${provider.foundUsernameDetails}',
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
                                'لم يتم العثور على شخص بهذا المعرِّف',
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
              const SizedBox(height: AppDimensions.spacing16),
              _buildTextField(
                _phoneController,
                'رقم الهاتف (اختياري)',
                SolarLinearIcons.phone,
                onChanged: (_) => setModalState(() {}),
              ),
              const SizedBox(height: AppDimensions.spacing16),
              _buildTextField(
                _emailController,
                'البريد الإلكتروني (اختياري)',
                SolarLinearIcons.letter,
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

    // Re-enable username lookup listener after modal closes
    if (mounted) {
      setState(() => _isUsernameLookupEnabled = true);
    }

    if (result == true) {
      await _saveCustomerDetails();
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

  Future<void> _saveCustomerDetails() async {
    try {
      final data = {
        _kNameKey: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        _kPhoneKey: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        _kEmailKey: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        _kUsernameKey: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
      };

      if (data[_kNameKey] == null) {
        AnimatedToast.error(context, 'يرجى إدخال الاسم');
        return;
      }

      // Recalculate isNewContact at save time for accurate state
      final wasNewContact = _checkIsNewContact();
      final customerId = _customer[_kIdKey] as int?;

      setState(() => _isSaving = true);

      Map<String, dynamic> response;
      if (!wasNewContact && customerId != null) {
        response = await _repository.updateCustomer(customerId, data);
      } else {
        response = await _repository.addCustomer(data);
      }

      final isSuccess =
          response['success'] == true ||
          response.containsKey('customer') ||
          response.containsKey(_kIdKey);

      if (mounted && isSuccess) {
        final savedCustomer =
            (response['customer'] ?? response) as Map<String, dynamic>;

        final newId = savedCustomer[_kIdKey] ?? response[_kIdKey];

        setState(() {
          _customer = {..._customer, ...data, ...savedCustomer};
          if (newId != null) _customer[_kIdKey] = newId;
          _isSaving = false;
          // Update cached values
          _isAlmudeerUser = _checkIsAlmudeerUser();
        });

        // Defer provider update to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            if (!wasNewContact && customerId != null) {
              context.read<CustomersProvider>().updateCustomerInList(_customer);
            } else {
              context.read<CustomersProvider>().refresh();
            }
          } catch (_) {}
        });

        AnimatedToast.success(
          context,
          !wasNewContact && customerId != null
              ? 'تمَّ تحديث البيانات بنجاح'
              : 'تمَّت الإضافة بنجاح',
        );
      } else if (mounted) {
        setState(() => _isSaving = false);
        AnimatedToast.error(
          context,
          response['error'] ??
              (!wasNewContact && customerId != null ? 'فشل تحديث البيانات' : 'فشلت الإضافة'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AnimatedToast.error(context, 'حدث خطأ أثناء حفظ البيانات: $e');
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
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: PremiumFAB(
                heroTag: 'customer_detail_edit_fab',
                standalone: false,
                gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
                onPressed: _openEditCustomer,
                icon: Icon(
                  _checkIsNewContact() ? SolarBoldIcons.userPlus : SolarBoldIcons.pen,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
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
            const SizedBox(height: 80),
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
            offset: Offset(0, 20 * (1 - animValue)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPremiumHeaderCard(ThemeData theme, bool isVip) {
    final isDark = theme.brightness == Brightness.dark;
    final avatarHeroTag = 'avatar_${_customer[_kUsernameKey] ?? _customer[_kIdKey] ?? _customer[_kPhoneKey] ?? 'unknown'}';

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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else if (isRecording) {
                  statusWidget = Text(
                    'يسجِّل مقطع صوتي...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else if (isOnline) {
                  statusWidget = Text(
                    'متَّصل الآن',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else {
                  final formatted = _formatLastSeen(lastSeen);
                  if (formatted.isNotEmpty) {
                    final isDark = theme.brightness == Brightness.dark;
                    statusWidget = Text(
                      formatted,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }
                }

                if (statusWidget == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: statusWidget,
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacing16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
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
    final usernameObj = _customer[_kUsernameKey];
    final username = usernameObj?.toString();
    if (username == null || username.isEmpty) {
      AnimatedToast.error(context, 'لا يوجد معرِّف لهذا الشَّخص للمراسلة');
      return;
    }

    // Get avatar URL from customer data (prefer profile_pic_url, then image)
    final imageUrl = _customer[_kProfilePicUrlKey] ?? _customer[_kImageKey];

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

    _subscribeToStatus(immediate: true);
    _loadFullDetails();
  }

  Future<void> _navigateToSavedMessages() async {
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
  }

  Widget _buildPremiumAvatar(ThemeData theme, bool isVip, bool isDark) {
    final imageUrl = _customer[_kProfilePicUrlKey] ?? _customer[_kImageKey];

    return AppAvatar(
      radius: 48,
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
