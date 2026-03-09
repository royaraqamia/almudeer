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
  bool _isSaving = false;

  // Controllers for editing
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;

  // Animation controller for stagger animations
  late final AnimationController _animController;

  /// Check if this customer is the current logged-in user
  bool get _isCurrentUser {
    final authProvider = context.read<AuthProvider>();
    final currentUserUsername = authProvider.userInfo?.username;
    final customerUsername = _customer['username']?.toString();
    final currentUserLicenseId = authProvider.userInfo?.licenseId?.toString();
    final customerLicenseId = _customer['id']?.toString();

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

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;

    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();

    _usernameController.addListener(() {
      final username = _usernameController.text.trim();
      context.read<CustomersProvider>().lookupUsername(username);
    });

    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _animController.forward();

    _subscribeToStatus();
    _loadFullDetails();
  }

  void _subscribeToStatus({bool immediate = false}) {
    final username = _customer['username'] ?? _customer['senderContact'];
    if (username != null &&
        (_customer['is_almudeer_user'] == true ||
            _customer['is_almudeer_user'] == 1 ||
            _customer['isAlmudeerUser'] == true ||
            _customer['isAlmudeerUser'] == 1)) {
      final lastSeen = _customer['last_seen_at'];
      final isOnline =
          _customer['is_online'] == true || _customer['is_online'] == 1;

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadFullDetails() async {
    final id = _customer['id'];
    if (id == null) return;

    try {
      final response = await _repository.getCustomerDetail(id as int);
      final fullDetails =
          (response.containsKey('customer') ? response['customer'] : response)
              as Map<String, dynamic>?;

      if (mounted && fullDetails != null && !_isSaving) {
        setState(() {
          _customer = fullDetails;
        });
      }
    } catch (_) {
      // Fail silently in background
    }
  }

  String get _displayName {
    return _customer['name'] ??
        _customer['phone'] ??
        _customer['email'] ??
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
    context.read<CustomersProvider>().clearUsernameLookup();

    _nameController.text = _customer['name'] ?? '';
    _phoneController.text = _customer['phone'] ?? '';
    _emailController.text = _customer['email'] ?? '';
    _usernameController.text = _customer['username'] ?? '';

    final String initialName = _customer['name'] ?? '';
    final String initialPhone = _customer['phone'] ?? '';
    final String initialEmail = _customer['email'] ?? '';
    final String initialUsername = _customer['username'] ?? '';

    final bool isNewContact = !(() {
      final customerId = _customer['id'] as int?;
      final customerUsername = _customer['username']?.toString();
      final customerPhone = _customer['phone']?.toString();
      final customerEmail = _customer['email']?.toString();
      return customerId != null
          ? context.read<CustomersProvider>().customers.any((c) => c.id == customerId)
          : context.read<CustomersProvider>().getCustomerByContact(
              customerUsername ?? customerPhone ?? customerEmail,
            ) != null;
    })();

    final result = await PremiumBottomSheet.show<dynamic>(
      context: context,
      title: isNewContact ? 'إضافة' : 'تعديل',
      child: StatefulBuilder(
        builder: (context, setModalState) {
          bool hasChanges() {
            if (isNewContact) return _nameController.text.trim().isNotEmpty;
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
                text: isNewContact ? 'إضافة' : 'حفظ التَّغييرات',
              ),
            ],
          );
        },
      ),
    );

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
        'name': _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'username': _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
      };

      if (data['name'] == null) {
        AnimatedToast.error(context, 'يرجى إدخال الاسم');
        return;
      }

      final customerId = _customer['id'] as int?;
      final customerUsername = _customer['username']?.toString();
      final customerPhone = _customer['phone']?.toString();
      final customerEmail = _customer['email']?.toString();

      final customersProvider = context.read<CustomersProvider>();
      final isInCustomersList = customerId != null
          ? customersProvider.customers.any((c) => c.id == customerId)
          : customersProvider.getCustomerByContact(
              customerUsername ?? customerPhone ?? customerEmail,
            ) != null;

      setState(() => _isSaving = true);

      Map<String, dynamic> response;
      if (isInCustomersList && customerId != null) {
        response = await _repository.updateCustomer(customerId, data);
      } else {
        response = await _repository.addCustomer(data);
      }

      final isSuccess =
          response['success'] == true ||
          response.containsKey('customer') ||
          response.containsKey('id');

      if (mounted && isSuccess) {
        final savedCustomer =
            (response['customer'] ?? response) as Map<String, dynamic>;

        final newId = savedCustomer['id'] ?? response['id'];

        setState(() {
          _customer = {..._customer, ...data, ...savedCustomer};
          if (newId != null) _customer['id'] = newId;
          _isSaving = false;
        });

        if (mounted) {
          try {
            if (isInCustomersList && customerId != null) {
              context.read<CustomersProvider>().updateCustomerInList(_customer);
            } else {
              context.read<CustomersProvider>().refresh();
            }
          } catch (_) {}
        }

        AnimatedToast.success(
          context,
          isInCustomersList && customerId != null
              ? 'تمَّ تحديث البيانات بنجاح'
              : 'تمَّت الإضافة بنجاح',
        );
      } else if (mounted) {
        setState(() => _isSaving = false);
        AnimatedToast.error(
          context,
          response['error'] ??
              (isInCustomersList && customerId != null ? 'فشل تحديث البيانات' : 'فشلت الإضافة'),
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
    final isVip = _customer['is_vip'] == true || _customer['is_vip'] == 1;

    final customerId = _customer['id'] as int?;
    final customerUsername = _customer['username']?.toString();
    final customerPhone = _customer['phone']?.toString();
    final customerEmail = _customer['email']?.toString();

    final customersProvider = context.read<CustomersProvider>();
    final isInCustomersList = customerId != null
        ? customersProvider.customers.any((c) => c.id == customerId)
        : customersProvider.getCustomerByContact(
            customerUsername ?? customerPhone ?? customerEmail,
          ) != null;

    final isNewContact = !isInCustomersList;

    return Scaffold(
      floatingActionButton: _isCurrentUser
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
                  isNewContact ? SolarBoldIcons.userPlus : SolarBoldIcons.pen,
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
    final avatarHeroTag = 'avatar_${_customer['username'] ?? _customer['id'] ?? _customer['phone'] ?? 'unknown'}';

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
          if (_customer['is_almudeer_user'] == true ||
              _customer['is_almudeer_user'] == 1 ||
              _customer['isAlmudeerUser'] == true ||
              _customer['isAlmudeerUser'] == 1) ...[
            Consumer<ConversationDetailProvider>(
              builder: (context, provider, _) {
                final isTyping = provider.isPeerTyping;
                final isRecording = provider.isPeerRecording;
                final isOnline = provider.isPeerOnline;
                final lastSeen =
                    provider.peerLastSeen ?? _customer['last_seen_at'];

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
                    onPressed: _isCurrentUser
                        ? _navigateToSavedMessages
                        : _navigateToInternalChat,
                    text: _isCurrentUser ? 'رسائلي' : 'مراسلة',
                    icon: _isCurrentUser
                        ? SolarBoldIcons.bookmark
                        : SolarBoldIcons.chatLine,
                    gradientColors: _isCurrentUser
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
    final username = _customer['username'];
    if (username == null || username.toString().isEmpty) {
      AnimatedToast.error(context, 'لا يوجد معرِّف لهذا الشَّخص للمراسلة');
      return;
    }

    // Get avatar URL from customer data (prefer profile_pic_url, then image)
    final imageUrl = _customer['profile_pic_url'] ?? _customer['image'];

    final conversation = Conversation(
      id: -1,
      channel: 'almudeer',
      senderName: _customer['name'],
      senderContact: username.toString(),
      senderId: username.toString(),
      body: '',
      status: 'active',
      createdAt: DateTime.now().toIso8601String(),
      messageCount: 0,
      unreadCount: 0,
      avatarUrl: imageUrl,
      lastSeenAt: _customer['last_seen_at'],
      isOnline: _customer['is_online'] == true || _customer['is_online'] == 1,
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
    final imageUrl = _customer['profile_pic_url'] ?? _customer['image'];

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
