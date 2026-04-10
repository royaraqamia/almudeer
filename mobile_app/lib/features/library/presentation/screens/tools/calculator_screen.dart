import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/features/calculator/presentation/providers/calculator_provider.dart';
import 'package:almudeer_mobile_app/features/calculator/presentation/widgets/calculator/calculator_button.dart';
import 'package:almudeer_mobile_app/features/calculator/presentation/widgets/calculator/calculator_display.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/features/shared/presentation/widgets/premium_bottom_sheet.dart';
import 'package:figma_squircle/figma_squircle.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  bool _isScientific = false;

  void _toggleScientificMode() {
    setState(() {
      _isScientific = !_isScientific;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalculatorProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme, isDark),
      body: Container(
        decoration: BoxDecoration(gradient: _buildBackgroundGradient(isDark)),
        child: Column(
          children: [
            Expanded(
              flex: _isScientific ? 3 : 4,
              child: _CalculatorDisplayContainer(
                child: CalculatorDisplay(
                  expression: provider.expression,
                  result: provider.result,
                ),
              ),
            ),
            Expanded(
              flex: _isScientific ? 4 : 5,
              child: _buildKeypad(provider),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    final provider = context.watch<CalculatorProvider>();
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      title: Text(
        'ط§ظ„ط­ط§ط³ط¨ط©',
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: isDark
              ? AppColors.textPrimaryDark
              : AppColors.textPrimaryLight,
        ),
      ),
      centerTitle: true,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceDark.withValues(alpha: 0.5)
                : AppColors.surfaceLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(SolarLinearIcons.arrowRight, size: 20),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        _buildSyncStatusIndicator(isDark, provider.syncStatus),
        const SizedBox(width: 4),
        _buildToggleButton(isDark),
        const SizedBox(width: 4),
        _buildHistoryButton(isDark),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildToggleButton(bool isDark) {
    return GestureDetector(
      onTap: _toggleScientificMode,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _isScientific
              ? AppColors.primary.withValues(alpha: 0.12)
              : (isDark
                    ? AppColors.surfaceDark.withValues(alpha: 0.5)
                    : AppColors.surfaceLight.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
          border: _isScientific
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Icon(
          _isScientific
              ? SolarLinearIcons.calculator
              : SolarLinearIcons.sidebarCode,
          size: 20,
          color: _isScientific ? AppColors.primary : null,
        ),
      ),
    );
  }

  Widget _buildHistoryButton(bool isDark) {
    return GestureDetector(
      onTap: () => _showHistory(context, context.read<CalculatorProvider>()),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark.withValues(alpha: 0.5)
              : AppColors.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(SolarLinearIcons.history, size: 20),
      ),
    );
  }

  Widget _buildSyncStatusIndicator(bool isDark, SyncStatus syncStatus) {
    // Only show indicator when actively syncing or failed
    if (syncStatus == SyncStatus.idle || syncStatus == SyncStatus.synced) {
      return const SizedBox.shrink();
    }

    IconData icon;
    Color? iconColor;
    String? tooltip;

    switch (syncStatus) {
      case SyncStatus.loading:
        icon = SolarLinearIcons.refresh;
        iconColor = AppColors.primary;
        tooltip = 'ط¬ط§ط±ظٹ ط§ظ„ظ…ط²ط§ظ…ظ†ط©...';
        break;
      case SyncStatus.syncing:
        icon = SolarLinearIcons.refresh;
        iconColor = AppColors.primary;
        tooltip = 'ط¬ط§ط±ظٹ ط§ظ„ط­ظپط¸...';
        break;
      case SyncStatus.failed:
        icon = SolarLinearIcons.infoCircle;
        iconColor = Colors.orange;
        tooltip = 'ظپط´ظ„طھ ط§ظ„ظ…ط²ط§ظ…ظ†ط© - طھظ… ط§ظ„ط­ظپط¸ ظ…ط­ظ„ظٹط§ظ‹ ظپظ‚ط·';
        break;
      default:
        return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: syncStatus == SyncStatus.failed
          ? () => _showSyncFailedSnackbar(context)
          : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark.withValues(alpha: 0.5)
              : AppColors.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  void _showSyncFailedSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'ظپط´ظ„طھ ظ…ط²ط§ظ…ظ†ط© ط§ظ„ط³ط¬ظ„ ظ…ط¹ ط§ظ„ط®ط§ط¯ظ…. طھظ… ط§ظ„ط­ظپط¸ ظ…ط­ظ„ظٹط§ظ‹ ظپظ‚ط·.',
          style: TextStyle(fontFamily: 'IBM Plex Sans Arabic'),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'ط¥ط¹ط§ط¯ط© ط§ظ„ظ…ط­ط§ظˆظ„ط©',
          textColor: Colors.white,
          onPressed: () {
            context.read<CalculatorProvider>().setUserId(
              context.read<CalculatorProvider>().userId,
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeypad(CalculatorProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: SmoothBorderRadius(
          cornerRadius: 28,
          cornerSmoothing: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            children: [
              if (_isScientific) ...[
                ..._buildScientificRows(provider),
                const SizedBox(height: 8),
              ],
              ..._buildStandardRows(provider),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStandardRows(CalculatorProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return [
      _buildButtonRow([
        CalculatorButton(
          text: 'AC',
          onTap: () => provider.clear(),
          color: isDark ? Colors.orange[900] : Colors.orange[100],
          textColor: isDark ? Colors.orange[100] : Colors.orange[900],
        ),
        CalculatorButton(
          text: 'DEL',
          onTap: () => provider.delete(),
          color: isDark ? Colors.orange[900] : Colors.orange[100],
          textColor: isDark ? Colors.orange[100] : Colors.orange[900],
        ),
        CalculatorButton(
          text: '%',
          onTap: () => provider.append('%'),
          color: AppColors.primary.withValues(alpha: 0.08),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: 'أ·',
          onTap: () => provider.append('أ·'),
          color: AppColors.primary.withValues(alpha: 0.08),
          textColor: AppColors.primary,
        ),
      ]),
      const SizedBox(height: 8),
      _buildButtonRow([
        CalculatorButton(
          text: '7',
          onTap: () => provider.append('7'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '8',
          onTap: () => provider.append('8'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '9',
          onTap: () => provider.append('9'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: 'أ—',
          onTap: () => provider.append('أ—'),
          color: AppColors.primary.withValues(alpha: 0.08),
          textColor: AppColors.primary,
        ),
      ]),
      const SizedBox(height: 8),
      _buildButtonRow([
        CalculatorButton(
          text: '4',
          onTap: () => provider.append('4'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '5',
          onTap: () => provider.append('5'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '6',
          onTap: () => provider.append('6'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '-',
          onTap: () => provider.append('-'),
          color: AppColors.primary.withValues(alpha: 0.08),
          textColor: AppColors.primary,
        ),
      ]),
      const SizedBox(height: 8),
      _buildButtonRow([
        CalculatorButton(
          text: '1',
          onTap: () => provider.append('1'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '2',
          onTap: () => provider.append('2'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '3',
          onTap: () => provider.append('3'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '+',
          onTap: () => provider.append('+'),
          color: AppColors.primary.withValues(alpha: 0.08),
          textColor: AppColors.primary,
        ),
      ]),
      const SizedBox(height: 8),
      _buildButtonRow([
        CalculatorButton(
          text: '0',
          onTap: () => provider.append('0'),
          isLarge: true,
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '.',
          onTap: () => provider.append('.'),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
        CalculatorButton(
          text: '=',
          onTap: () => provider.evaluate(),
          color: AppColors.primary,
          textColor: Colors.white,
        ),
      ]),
    ];
  }

  Widget _buildButtonRow(List<Widget> buttons) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons,
      ),
    );
  }

  List<Widget> _buildScientificRows(CalculatorProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return [
      _buildButtonRow([
        CalculatorButton(
          text: 'sin',
          onTap: () => provider.append('sin('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: 'cos',
          onTap: () => provider.append('cos('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: 'tan',
          onTap: () => provider.append('tan('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: 'log',
          onTap: () => provider.append('log('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
      ]),
      const SizedBox(height: 8),
      _buildButtonRow([
        CalculatorButton(
          text: '(',
          onTap: () => provider.append('('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: ')',
          onTap: () => provider.append(')'),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: 'sqrt',
          onTap: () => provider.append('sqrt('),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
        CalculatorButton(
          text: '^',
          onTap: () => provider.append('^'),
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          textColor: AppColors.primary,
        ),
      ]),
    ];
  }

  LinearGradient _buildBackgroundGradient(bool isDark) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              AppColors.backgroundDark,
              AppColors.backgroundDark.withValues(alpha: 0.8),
            ]
          : [
              AppColors.backgroundLight,
              AppColors.backgroundLight.withValues(alpha: 0.5),
            ],
    );
  }

  void _showHistory(BuildContext context, CalculatorProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    PremiumBottomSheet.show(
      context: context,
      title: 'ط³ط¬ظ„ظڈظ‘ ط§ظ„ط¹ظ…ظ„ظٹظژظ‘ط§طھ',
      maxHeight: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.history.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDark.withValues(alpha: 0.3)
                    : AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    SolarLinearIcons.calendar,
                    size: 48,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ط§ظ„ط³ظگظ‘ط¬ظ„ظڈظ‘ ظپط§ط±ط؛',
                    style: TextStyle(
                      fontFamily: 'IBM Plex Sans Arabic',
                      fontSize: 16,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ط³طھط¸ظ‡ط± ظ‡ظ†ط§ ط§ظ„ط¹ظ…ظ„ظٹظژظ‘ط§طھ ط§ظ„ظ…ظڈظ†ظپظژظ‘ط°ط©',
                    style: TextStyle(
                      fontFamily: 'IBM Plex Sans Arabic',
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 450),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark.withValues(alpha: 0.3)
                      : AppColors.surfaceLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: true,
                  itemCount: provider.history.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.borderDark.withValues(alpha: 0.3)
                        : AppColors.borderLight.withValues(alpha: 0.3),
                  ),
                  itemBuilder: (context, index) {
                    final displayEntry = provider.history[index];
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          displayEntry,
                          style: const TextStyle(
                            fontSize: 17,
                            fontFamily: 'IBM Plex Sans Arabic',
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.start,
                        ),
                        onTap: () {
                          provider.restoreFromHistory(displayEntry);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A decorative container for the calculator display area
class _CalculatorDisplayContainer extends StatelessWidget {
  final Widget child;

  const _CalculatorDisplayContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: child,
    );
  }
}
