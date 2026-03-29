import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/features/athkar/presentation/providers/athkar_provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

class MisbahaScreen extends StatefulWidget {
  const MisbahaScreen({super.key});

  @override
  State<MisbahaScreen> createState() => _MisbahaScreenState();
}

class _MisbahaScreenState extends State<MisbahaScreen>
    with SingleTickerProviderStateMixin {
  // Configuration constants
  static const List<int> _commonTargets = [33, 99, 100];
  static const double _circleSize = 280.0;
  static const double _strokeWidth = 12.0;
  static const Duration _animationDuration = Duration(milliseconds: 150);
  static const double _scaleEnd = 0.95;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _showResetConfirm = false;
  bool _showTargetChangeConfirm = false;
  int? _pendingTarget;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: _animationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: _scaleEnd).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    final provider = context.read<AthkarProvider>();
    provider.incrementMisbaha();

    // Reset and trigger animation on every tap to handle rapid taps correctly
    _animationController
      ..reset()
      ..forward();

    // Haptic feedback based on completion status
    final count = provider.misbahaCount;
    final target = provider.misbahaTarget;

    // Heavy haptic when completing a full cycle (e.g., 33, 66, 99)
    if (count > 0 && count % target == 0) {
      Haptics.heavyTap();
    } else {
      Haptics.lightTap();
    }
  }

  void _handleTargetChange(int newTarget) {
    final provider = context.read<AthkarProvider>();
    final count = provider.misbahaCount;
    final currentTarget = provider.misbahaTarget;

    // If same target, do nothing
    if (newTarget == currentTarget) {
      return;
    }

    // If count is 0, change target immediately with haptic feedback
    if (count == 0) {
      provider.setMisbahaTarget(newTarget);
      Haptics.lightTap();
      return;
    }

    // Show confirmation dialog when changing target mid-cycle
    setState(() {
      _pendingTarget = newTarget;
      _showTargetChangeConfirm = true;
    });
  }

  void _confirmTargetChange() {
    if (_pendingTarget != null) {
      context.read<AthkarProvider>().setMisbahaTarget(_pendingTarget!);
      _pendingTarget = null;
      setState(() => _showTargetChangeConfirm = false);
    }
  }

  void _handleReset() {
    final provider = context.read<AthkarProvider>();
    if (provider.misbahaCount == 0) {
      provider.resetMisbaha();
      return;
    }
    setState(() => _showResetConfirm = true);
  }

  void _confirmReset() {
    context.read<AthkarProvider>().resetMisbaha();
    setState(() => _showResetConfirm = false);
  }

  Widget _buildConfirmationDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
    required Color confirmColor,
    required FontWeight? confirmFontWeight,
    required VoidCallback onConfirm,
  }) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'IBM Plex Sans Arabic',
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'IBM Plex Sans Arabic',
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _showResetConfirm = false;
                          _showTargetChangeConfirm = false;
                          _pendingTarget = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        style: const TextStyle(
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: TextStyle(
                          fontFamily: 'IBM Plex Sans Arabic',
                          fontWeight: confirmFontWeight ?? FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<AthkarProvider>();
    final target = provider.misbahaTarget;
    final count = provider.misbahaCount;

    // Calculate progress within current cycle (0 to target)
    final progressInCycle = count % target;
    // Progress for the ring: show completion at target
    final progress = target == 0
        ? 0.0
        : count > 0 && progressInCycle == 0
            ? 1.0
            : progressInCycle / target;

    final cycle = (count / target).floor();
    final isAtTarget = count > 0 && progressInCycle == 0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'ط§ظ„ظ…ط³ط¨ط­ط© ط§ظ„ط¥ظ„ظƒطھط±ظˆظ†ظٹط©',
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            SolarLinearIcons.altArrowRight,
            color: theme.iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(SolarLinearIcons.restart, size: 22),
            onPressed: _handleReset,
            tooltip: 'ط¥ط¹ط§ط¯ط© ط¶ط¨ط· ط§ظ„ط¹ط¯ط§ط¯',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 40),
              // Target Selection
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _commonTargets.map((t) {
                    final isSelected = target == t;
                    return Semantics(
                      label: 'ط§ظ„ظ‡ط¯ظپ $t',
                      button: true,
                      selected: isSelected,
                      child: GestureDetector(
                        onTap: () => _handleTargetChange(t),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected ? AppColors.primary : theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : theme.dividerColor.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            t.toString(),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : theme.textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'IBM Plex Sans Arabic',
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Spacer(),
              // Main Counter Display
              Semantics(
                label: 'ط§ط¶ط؛ط· ظ„ظ„ط¹ط¯طŒ count $count ظ…ظ† $target',
                button: true,
                child: GestureDetector(
                  onTap: _handleTap,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                    // Progress Circle with completion glow
                    SizedBox(
                      width: _circleSize,
                      height: _circleSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer glow when at target
                          if (isAtTarget)
                            Container(
                              width: _circleSize,
                              height: _circleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          // Progress ring
                          SizedBox(
                            width: _circleSize,
                            height: _circleSize,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: _strokeWidth,
                              backgroundColor: AppColors.primary
                                  .withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isAtTarget
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Counter Text with scale animation
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            count.toString(),
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 80,
                              fontWeight: FontWeight.bold,
                              color: isAtTarget
                                  ? AppColors.primaryLight
                                  : AppColors.primary,
                              fontFamily: 'IBM Plex Sans Arabic',
                            ),
                          ),
                          if (cycle > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ط§ظ„ط¯ظˆط±ط©: $cycle',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: isAtTarget
                                      ? AppColors.primaryLight
                                      : Colors.grey,
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontWeight: isAtTarget
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          // Completion indicator
                          if (isAtTarget)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'طھظ… ط§ظ„ظ‡ط¯ظپ âœ“',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'IBM Plex Sans Arabic',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const Spacer(),
              // Tap hint
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'ط§ط¶ط؛ط· ظ„ظ„ط¹ط¯',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                    fontFamily: 'IBM Plex Sans Arabic',
                  ),
                ),
              ),
            ],
          ),
          // Reset Confirmation Dialog
          if (_showResetConfirm)
            _buildConfirmationDialog(
              icon: SolarLinearIcons.dangerCircle,
              iconColor: AppColors.warning,
              title: 'ط¥ط¹ط§ط¯ط© ط¶ط¨ط· ط§ظ„ط¹ط¯ط§ط¯طں',
              message: 'ط³ظٹطھظ… طھطµظپظٹط± ط§ظ„ط¹ط¯ط§ط¯ ط¥ظ„ظ‰ ط§ظ„طµظپط±',
              cancelLabel: 'ط¥ظ„ط؛ط§ط،',
              confirmLabel: 'ط¥ط¹ط§ط¯ط© ط¶ط¨ط·',
              confirmColor: AppColors.error,
              confirmFontWeight: FontWeight.bold,
              onConfirm: _confirmReset,
            ),
          // Target Change Confirmation Dialog
          if (_showTargetChangeConfirm)
            _buildConfirmationDialog(
              icon: SolarLinearIcons.settingsMinimalistic,
              iconColor: AppColors.info,
              title: 'طھط؛ظٹظٹط± ط§ظ„ظ‡ط¯ظپطں',
              message: 'ظ„ط¯ظٹظƒ طھظ‚ط¯ظ… ظپظٹ ط§ظ„ط¹ط¯ط§ط¯ ط§ظ„ط­ط§ظ„ظٹ. ط§ظ„طھط؛ظٹظٹط± ط³ظٹط¨ط¯ط£ ط¯ظˆط±ط© ط¬ط¯ظٹط¯ط©.',
              cancelLabel: 'ط¥ظ„ط؛ط§ط،',
              confirmLabel: 'طھط؛ظٹظٹط±',
              confirmColor: AppColors.primary,
              confirmFontWeight: FontWeight.bold,
              onConfirm: _confirmTargetChange,
            ),
        ],
      ),
    );
  }
}
