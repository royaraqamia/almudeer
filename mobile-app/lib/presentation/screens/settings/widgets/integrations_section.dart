import 'dart:async';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:provider/provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/animated_toast.dart';
import '../../../widgets/custom_dialog.dart';
import '../../../../core/widgets/app_gradient_button.dart';

// Sub-widgets
import 'integrations/integration_card.dart';
import 'integrations/channel_settings_form.dart';
import 'integrations/telegram_setup_form.dart';
import 'integrations/email_setup_form.dart';

class IntegrationsSection extends StatefulWidget {
  const IntegrationsSection({super.key});

  @override
  State<IntegrationsSection> createState() => _IntegrationsSectionState();
}

class _IntegrationsSectionState extends State<IntegrationsSection>
    with WidgetsBindingObserver {
  final Map<String, bool> _loadingStates = {};
  final Map<String, bool> _expandedStates = {};

  // Controllers
  final TextEditingController _telegramTokenController =
      TextEditingController();

  bool _waitingForEmailOAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadIntegrations();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telegramTokenController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForEmailOAuth) {
      _waitingForEmailOAuth = false;
      context.read<SettingsProvider>().loadIntegrations();
    }
  }

  List<Map<String, dynamic>> _getAllChannels(List<dynamic> integrations) {
    final supported = [
      {
        'type': 'telegram_bot',
        'name': 'تيليجرام (بوت)',
        'desc': 'استلام وإرسال الرسائل عبر بوت خاص',
        'icon': SolarLinearIcons.plain,
        'color': AppColors.telegramBlue,
      },
      {
        'type': 'telegram_phone',
        'name': 'تيليجرام (حساب شخصي)',
        'desc': 'ربط حسابك الشخصي برقم الهاتف',
        'icon': SolarLinearIcons.plain,
        'color': AppColors.telegramBlue,
      },
      {
        'type': 'email',
        'name': 'البريد الإلكتروني',
        'desc': 'ربط حساب Gmail الخاص بك',
        'icon': SolarLinearIcons.letter,
        'color': AppColors.emailRed,
      },
    ];

    return supported.map<Map<String, dynamic>>((template) {
      final connected =
          integrations.firstWhere(
            (i) =>
                i['channel_type'] == template['type'] ||
                (template['type'] == 'telegram_phone' &&
                    i['channel_type'] == 'telegram'),
            orElse: () => <String, dynamic>{},
          ) ??
          {};

      final connectedMap = Map<String, dynamic>.from(connected as Map);

      if (connectedMap.isNotEmpty) {
        return <String, dynamic>{
          ...template,
          ...connectedMap,
          'is_active': connectedMap['is_active'] as bool? ?? false,
          'is_connected': true,
        };
      } else {
        return <String, dynamic>{
          ...template,
          'is_active': false,
          'is_connected': false,
        };
      }
    }).toList();
  }

  void _confirmDisconnect(Map<String, dynamic> channel) async {
    final type = channel['type'] as String;
    final confirmed = await CustomDialog.show<bool>(
      context,
      title: 'إلغاء الربط',
      message: 'هل أنت متأكد من رغبتك في إلغاء ربط ${channel['name']}؟',
      confirmText: 'نعم، إلغاء الربط',
      cancelText: 'تراجع',
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _loadingStates[type] = true);
      final success = await context.read<SettingsProvider>().disconnectChannel(
        type,
      );
      if (success && mounted) {
        AnimatedToast.success(context, 'تم إلغاء الربط بنجاح');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          context.read<SettingsProvider>().errorMessage ?? 'فشل إلغاء الربط',
        );
      }
      if (mounted) {
        setState(() => _loadingStates[type] = false);
      }
    }
  }

  Future<void> _saveSetup(String type) async {
    final settingsProvider = context.read<SettingsProvider>();
    if (type == 'telegram_phone') {
      final result = await Navigator.of(
        context,
      ).pushNamed('/integrations/telegram-phone-setup');
      if (result == true) {
        setState(() => _loadingStates['telegram_phone'] = true);
        await settingsProvider.loadIntegrations();
        if (mounted) {
          setState(() {
            _loadingStates['telegram_phone'] = false;
            _expandedStates['telegram_phone'] = true;
          });
        }
      }
      return;
    }

    setState(() => _loadingStates[type] = true);
    try {
      bool success = false;
      if (type == 'telegram_bot') {
        final token = _telegramTokenController.text.trim();
        if (token.isEmpty) throw Exception('يرجى إدخال توكن البوت');
        success = await settingsProvider.saveTelegramConfig(token);
      } else if (type == 'email') {
        final authUrl = await settingsProvider.fetchGmailAuthUrl();
        if (authUrl != null) {
          _waitingForEmailOAuth = true;
          await custom_tabs.launchUrl(
            Uri.parse(authUrl),
            customTabsOptions: custom_tabs.CustomTabsOptions(
              colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
                toolbarColor: AppColors.primary,
              ),
              showTitle: true,
              urlBarHidingEnabled: true,
            ),
            safariVCOptions: const custom_tabs.SafariViewControllerOptions(
              preferredBarTintColor: AppColors.primary,
              preferredControlTintColor: Colors.white,
              barCollapsingEnabled: true,
              dismissButtonStyle:
                  custom_tabs.SafariViewControllerDismissButtonStyle.close,
            ),
          );
          return;
        }
      }

      if (success && mounted) {
        setState(() {
          _expandedStates[type] = true;
          _loadingStates[type] = false;
        });
        AnimatedToast.success(context, 'تم الربط بنجاح');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          settingsProvider.errorMessage ?? 'فشل الربط',
        );
        setState(() => _loadingStates[type] = false);
      }
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, e.toString());
        setState(() => _loadingStates[type] = false);
      }
    }
  }

  Future<void> _updateSettings(String type) async {
    setState(() => _loadingStates[type] = true);
    final settingsProvider = context.read<SettingsProvider>();
    try {
      final success = await settingsProvider.updateChannelSettings(type, {});
      if (success && mounted) {
        AnimatedToast.success(context, 'تم حفظ الإعدادات بنجاح');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          settingsProvider.errorMessage ?? 'فشل تحديث الإعدادات',
        );
      }
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, 'فشل تحديث الإعدادات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingStates[type] = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final channels = _getAllChannels(settingsProvider.integrations);

    return Column(
      children: [
        ...channels.map((channel) {
          final type = channel['type'] as String;
          final isExpanded = _expandedStates[type] ?? false;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntegrationCard(
              data: channel,
              isExpanded: isExpanded,
              isLoading: _loadingStates[type] ?? false,
              onExpandChanged: (val) {
                setState(() => _expandedStates[type] = val);
              },
              content: _buildChannelContent(channel),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildChannelContent(Map<String, dynamic> channel) {
    final type = channel['type'] as String;
    final isConnected = channel['is_connected'] as bool? ?? false;

    if (isConnected) {
      return ChannelSettingsForm(
        data: channel,
        isLoading: _loadingStates[type] ?? false,
        isDisconnecting: _loadingStates[type] ?? false,
        onDisconnect: () => _confirmDisconnect(channel),
        onUpdateSettings: _updateSettings,
      );
    }

    switch (type) {
      case 'telegram_bot':
        return TelegramSetupForm(
          tokenController: _telegramTokenController,
          onSave: () => _saveSetup(type),
        );
      case 'email':
        return EmailSetupForm(onSave: () => _saveSetup(type));
      case 'telegram_phone':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'يمكنك ربط حسابك الشخصي في تيليجرام لتتمكن من الرد على الرسائل مباشرة من داخل التطبيق.',
                style: TextStyle(height: 1.5, fontSize: 13),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AppGradientButton(
                  onPressed: () => _saveSetup(type),
                  text: 'بدء الربط برقم الهاتف',
                  gradientColors: const [Color(0xFF2563EB), Color(0xFF0891B2)],
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
