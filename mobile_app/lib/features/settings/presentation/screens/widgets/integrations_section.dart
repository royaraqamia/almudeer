import 'dart:async';
import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/features/settings/presentation/providers/settings_provider.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/animated_toast.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/custom_dialog.dart';

// Sub-widgets
import 'integrations/integration_card.dart';
import 'integrations/channel_settings_form.dart';
import 'integrations/telegram_setup_form.dart';
import 'integrations/telegram_phone_setup_form.dart';

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


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load from cache only - no API call for offline-first experience
      context.read<SettingsProvider>().loadIntegrations(skipAutoRefresh: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telegramTokenController.dispose();
    super.dispose();
  }


  List<Map<String, dynamic>> _getAllChannels(List<dynamic> integrations) {
    final supported = [
      {
        'type': 'telegram_bot',
        'name': 'طھظٹظ„ظٹط¬ط±ط§ظ… (ط¨ظˆطھ)',
        'desc': 'ط§ط³طھظ„ط§ظ… ظˆط¥ط±ط³ط§ظ„ ط§ظ„ط±ط³ط§ط¦ظ„ ط¹ط¨ط± ط¨ظˆطھ ط®ط§طµ',
        'icon': SolarLinearIcons.plain,
        'color': AppColors.telegramBlue,
      },
      {
        'type': 'telegram_phone',
        'name': 'طھظٹظ„ظٹط¬ط±ط§ظ… (ط­ط³ط§ط¨ ط´ط®طµظٹ)',
        'desc': 'ط±ط¨ط· ط­ط³ط§ط¨ظƒ ط§ظ„ط´ط®طµظٹ ط¨ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ',
        'icon': SolarLinearIcons.plain,
        'color': AppColors.telegramBlue,
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
      title: 'ط¥ظ„ط؛ط§ط، ط§ظ„ط±ط¨ط·',
      message: 'ظ‡ظ„ ط£ظ†طھ ظ…طھط£ظƒط¯ ظ…ظ† ط±ط؛ط¨طھظƒ ظپظٹ ط¥ظ„ط؛ط§ط، ط±ط¨ط· ${channel['name']}طں',
      confirmText: 'ظ†ط¹ظ…طŒ ط¥ظ„ط؛ط§ط، ط§ظ„ط±ط¨ط·',
      cancelText: 'طھط±ط§ط¬ط¹',
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _loadingStates[type] = true);
      final success = await context.read<SettingsProvider>().disconnectChannel(
        type,
      );
      if (success && mounted) {
        AnimatedToast.success(context, 'طھظ… ط¥ظ„ط؛ط§ط، ط§ظ„ط±ط¨ط· ط¨ظ†ط¬ط§ط­');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          context.read<SettingsProvider>().errorMessage ?? 'ظپط´ظ„ ط¥ظ„ط؛ط§ط، ط§ظ„ط±ط¨ط·',
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
      // Set loading state for telegram_phone - actual flow is handled inline
      setState(() => _loadingStates['telegram_phone'] = true);
      return;
    }

    setState(() => _loadingStates[type] = true);
    try {
      bool success = false;
      if (type == 'telegram_bot') {
        final token = _telegramTokenController.text.trim();
        if (token.isEmpty) throw Exception('ظٹط±ط¬ظ‰ ط¥ط¯ط®ط§ظ„ طھظˆظƒظ† ط§ظ„ط¨ظˆطھ');
        success = await settingsProvider.saveTelegramConfig(token);
      }

      if (success && mounted) {
        setState(() {
          _expandedStates[type] = true;
          _loadingStates[type] = false;
        });
        AnimatedToast.success(context, 'طھظ… ط§ظ„ط±ط¨ط· ط¨ظ†ط¬ط§ط­');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          settingsProvider.errorMessage ?? 'ظپط´ظ„ ط§ظ„ط±ط¨ط·',
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
        AnimatedToast.success(context, 'طھظ… ط­ظپط¸ ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ ط¨ظ†ط¬ط§ط­');
      } else if (mounted) {
        AnimatedToast.error(
          context,
          settingsProvider.errorMessage ?? 'ظپط´ظ„ طھط­ط¯ظٹط« ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
        );
      }
    } catch (e) {
      if (mounted) {
        AnimatedToast.error(context, 'ظپط´ظ„ طھط­ط¯ظٹط« ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ: $e');
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
      case 'telegram_phone':
        return TelegramPhoneSetupForm(
          onComplete: () async {
            final settingsProvider = context.read<SettingsProvider>();
            AnimatedToast.success(context, 'طھظ… ط±ط¨ط· Telegram ط¨ظ†ط¬ط§ط­!');
            setState(() {
              _loadingStates['telegram_phone'] = false;
              _expandedStates['telegram_phone'] = true;
            });
            await settingsProvider.loadIntegrations();
          },
          onError: (error) {
            AnimatedToast.error(context, error);
            setState(() {
              _loadingStates['telegram_phone'] = false;
            });
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
