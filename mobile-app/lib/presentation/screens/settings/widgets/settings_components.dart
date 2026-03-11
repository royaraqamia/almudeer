import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/utils/haptics.dart';

/// Reusable settings row widget with accessibility support
///
/// Design Specifications:
/// - Minimum touch target: 44x44px (WCAG 2.1 AA compliant)
/// - Proper semantics for screen readers
/// - Focus and hover states for keyboard/tablet users
/// - Haptic feedback on interactions
class SettingsRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.showDivider = true,
    this.padding,
  });

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final row = Padding(
      padding:
          widget.padding ??
          const EdgeInsets.symmetric(vertical: AppDimensions.spacing12),
      child: Row(
        children: [
          // Icon container with gradient
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.primary.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
            ),
            child: Icon(
              widget.icon,
              size: AppDimensions.iconLarge,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(width: AppDimensions.spacing12),

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacing4),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    height: 1.5, // Better for Arabic readability
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppDimensions.spacing12),

          // Trailing widget
          widget.trailing,
        ],
      ),
    );

    // Wrap with InkWell if tappable
    if (widget.onTap != null) {
      return Semantics(
        label: '${widget.title}, ${widget.subtitle}',
        button: true,
        enabled: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Focus(
            onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
            child: InkWell(
              onTap: () {
                Haptics.lightTap();
                widget.onTap!();
              },
              borderRadius: SmoothBorderRadius(
                cornerRadius: AppDimensions.radiusLarge,
                cornerSmoothing: 1.0,
              ),
              focusColor: AppColors.primary.withValues(alpha: 0.12),
              hoverColor: AppColors.primary.withValues(alpha: 0.04),
              highlightColor: AppColors.primary.withValues(alpha: 0.08),
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 44, // WCAG 2.1 AA minimum touch target
                ),
                decoration: BoxDecoration(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusLarge,
                    cornerSmoothing: 1.0,
                  ),
                  color: _getBackgroundColor(isDark, theme),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimensions.spacing4,
                  ),
                  child: row,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Non-interactive row
    return Column(
      children: [
        Container(constraints: const BoxConstraints(minHeight: 44), child: row),
        if (widget.showDivider) const SettingsDivider(),
      ],
    );
  }

  Color? _getBackgroundColor(bool isDark, ThemeData theme) {
    if (_isFocused) {
      return AppColors.primary.withValues(alpha: 0.12);
    }
    if (_isHovered) {
      return isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.02);
    }
    return null;
  }
}

/// Settings divider with proper opacity
class SettingsDivider extends StatelessWidget {
  final double indent;
  final double endIndent;

  const SettingsDivider({super.key, this.indent = 64, this.endIndent = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacing4),
      child: Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: endIndent,
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }
}

/// Settings section header with gradient accent bar
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showAccentBar;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showAccentBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (showAccentBar) {
      return Row(
        children: [
          // Gradient accent bar
          Container(
            width: 4,
            height: AppDimensions.spacing24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
            ),
          ),
          const SizedBox(width: AppDimensions.spacing10),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppDimensions.spacing4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    // Simple header without accent bar
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppDimensions.spacing4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Animated section wrapper for staggered entrance animations
class AnimatedSettingsSection extends StatefulWidget {
  final Widget child;
  final double delay;
  final Duration duration;

  const AnimatedSettingsSection({
    super.key,
    required this.child,
    required this.delay,
    this.duration = AppAnimations.slow, // Apple standard: 400ms (was 800ms)
  });

  @override
  State<AnimatedSettingsSection> createState() =>
      _AnimatedSettingsSectionState();
}

class _AnimatedSettingsSectionState extends State<AnimatedSettingsSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
