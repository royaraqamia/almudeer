import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:almudeer_mobile_app/core/constants/animations.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import 'package:almudeer_mobile_app/core/widgets/app_avatar.dart';
import '../../../data/models/customer.dart';

class PremiumCustomerTile extends StatefulWidget {
  final Customer customer;
  final VoidCallback onTap;
  final bool isLast;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isEnabled;
  final VoidCallback? onLongPress;

  const PremiumCustomerTile({
    super.key,
    required this.customer,
    required this.onTap,
    this.isLast = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isEnabled = true,
    this.onLongPress,
  });

  @override
  State<PremiumCustomerTile> createState() => _PremiumCustomerTileState();
}

class _PremiumCustomerTileState extends State<PremiumCustomerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) {
      return _buildDisabledTile(context);
    }

    final theme = Theme.of(context);
    final isVip = widget.customer.isVip;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      onLongPress: () {
        if (widget.onLongPress != null) {
          Haptics.heavyTap();
          widget.onLongPress!();
        }
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingMedium,
                    vertical: 12,
                  ),
                  color: widget.isSelected
                      ? AppColors.primary.withValues(alpha: 0.025)
                      : (isVip
                            ? Colors.amber.withValues(alpha: 0.03)
                            : Colors.transparent),
                  child: Row(
                    children: [
                      _buildPremiumAvatar(isVip, widget.isSelected, theme),
                      const SizedBox(width: AppDimensions.spacing12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              widget.customer.displayName,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (widget
                                              .customer
                                              .isAlmudeerUser) ...[
                                            const SizedBox(width: 8),
                                            Image.asset(
                                              'assets/images/app_icon.png',
                                              width: 14,
                                              height: 14,
                                            ),
                                          ],
                                          if (widget.customer.hasWhatsapp) ...[
                                            const SizedBox(width: 6),
                                            SvgPicture.asset(
                                              'assets/icons/whatsapp.svg',
                                              width: 14,
                                              height: 14,
                                            ),
                                          ],
                                          if (widget.customer.hasTelegram) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              SolarLinearIcons.plain,
                                              size: 14,
                                              color: const Color(
                                                0xFF0088CC,
                                              ).withValues(alpha: 0.8),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (isVip) _buildVipBadge(),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (widget.customer.syncStatus == 'dirty' ||
                                    widget.customer.syncStatus == 'new') ...[
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 16,
                                    color: Colors.orange.withValues(alpha: 0.8),
                                  ),
                                ],
                                const Spacer(),
                                _buildLeadScoreIndicator(theme),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingMedium,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDisabledTile(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.customer.name?.isNotEmpty == true
        ? widget.customer.name!
        : (widget.customer.phone ?? '?');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: 12,
          ),
          child: Row(
            children: [
              const AppAvatar(
                radius: 24,
                // Using AppAvatar consistently
              ),
              const SizedBox(width: AppDimensions.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ظ„ط§ ظٹظˆط¬ط¯ ط­ط³ط§ط¨ ط¹ظ„ظ‰ ط§ظ„ظ…ط¯ظٹط±',
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!widget.isLast)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
            ),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumAvatar(bool isVip, bool isSelected, ThemeData theme) {
    // Get customer image (prefer profile_pic_url, then image)
    final imageUrl = widget.customer.profilePicUrl ?? widget.customer.image;
    
    return AppAvatar(
      radius: 24,
      imageUrl: imageUrl,
      initials: widget.customer.avatarInitials,
      customGradient: isVip
          ? [const Color(0xFFFBBF24), const Color(0xFFD97706)]
          : null,
      border: isVip
          ? Border.all(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
              width: 2,
            )
          : null,
      overlay: isSelected
          ? Positioned(
              bottom: -4,
              left: -4,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  SolarBoldIcons.checkCircle,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildVipBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.2),
            Colors.amber.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(SolarLinearIcons.star, size: 12, color: Colors.amber[700]),
          const SizedBox(width: 4),
          Text(
            'VIP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.amber[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadScoreIndicator(ThemeData theme) {
    return const SizedBox.shrink();
  }
}
