import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:shimmer/shimmer.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../core/constants/animations.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/dimensions.dart';
import '../../core/constants/shadows.dart';
import '../../core/utils/haptics.dart';

/// Premium unified skeleton loader with enhanced animation
class PremiumSkeleton extends StatelessWidget {
  final Widget child;

  const PremiumSkeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium refined colors for smoother loading effect
    final baseColor = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFEEEEEE);
    final highlightColor = isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFFAFAFA);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1500),
      direction: ShimmerDirection.ltr,
      child: child,
    );
  }
}

/// Loading shimmer for list items
class ShimmerListItem extends StatelessWidget {
  final bool showAvatar;
  final int lines;

  const ShimmerListItem({super.key, this.showAvatar = true, this.lines = 2});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMedium,
          vertical: AppDimensions.paddingSmall,
        ),
        child: Row(
          children: [
            if (showAvatar) ...[
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppDimensions.spacing12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines, (index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: index < lines - 1 ? 8 : 0),
                    child: Container(
                      height: 12,
                      width: index == 0 ? double.infinity : 150,
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(
                            cornerRadius: 4,
                            cornerSmoothing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading shimmer for cards
class ShimmerCard extends StatelessWidget {
  final double height;

  const ShimmerCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: AppDimensions.spacing16),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusLarge,
              cornerSmoothing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading shimmer list
class ShimmerList extends StatelessWidget {
  final int itemCount;
  final bool showAvatar;
  final int lines;

  const ShimmerList({
    super.key,
    this.itemCount = 5,
    this.showAvatar = true,
    this.lines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return ShimmerListItem(showAvatar: showAvatar, lines: lines);
      },
    );
  }
}

/// Skeleton loading for inbox/conversation list
class InboxSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const InboxSkeletonLoader({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 0),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: 12,
            ),
            constraints: const BoxConstraints(minHeight: 72),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar with premium circle
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 100,
                                height: 14,
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: SmoothRectangleBorder(
                                    borderRadius: SmoothBorderRadius(
                                      cornerRadius: 4,
                                      cornerSmoothing: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 35,
                                height: 10,
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: SmoothRectangleBorder(
                                    borderRadius: SmoothBorderRadius(
                                      cornerRadius: 4,
                                      cornerSmoothing: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            height: 10,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: SmoothRectangleBorder(
                                borderRadius: SmoothBorderRadius(
                                  cornerRadius: 4,
                                  cornerSmoothing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (index < itemCount - 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 64),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loading for settings screen
class SettingsSkeletonLoader extends StatelessWidget {
  const SettingsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          top: 130,
          left: AppDimensions.paddingMedium,
          right: AppDimensions.paddingMedium,
          bottom: 120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            _buildSectionHeader(),
            const SizedBox(height: 24),
            // Info cards row
            Row(
              children: [
                Expanded(child: _buildInfoCard()),
                const SizedBox(width: 12),
                Expanded(child: _buildInfoCard()),
              ],
            ),
            const SizedBox(height: 24),
            // Section header
            _buildSectionHeader(),
            const SizedBox(height: 16),
            // Toggle item
            _buildToggleItem(),
            const SizedBox(height: 24),
            // Tone selector items
            ...List.generate(3, (index) => _buildToneItem()),
            const SizedBox(height: 24),
            // Save button
            Container(
              height: 48,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 12,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 10,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 150,
          height: 20,
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 4,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      height: 80,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusLarge,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleItem() {
    return Container(
      height: 70,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusLarge,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildToneItem() {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusLarge,
            cornerSmoothing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading for customers list
class CustomersSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const CustomersSkeletonLoader({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: 12,
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacing12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 120,
                            height: 14,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: SmoothRectangleBorder(
                                borderRadius: SmoothBorderRadius(
                                  cornerRadius: 4,
                                  cornerSmoothing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 70,
                        height: 20,
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: SmoothRectangleBorder(
                            borderRadius: SmoothBorderRadius(
                              cornerRadius: 10,
                              cornerSmoothing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loading for library grid
class LibrarySkeletonLoader extends StatelessWidget {
  final int itemCount;

  const LibrarySkeletonLoader({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 16,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Staggered entrance animation for list/grid items
class StaggeredAnimatedItem extends StatefulWidget {
  final int index;
  final Widget child;
  final bool animate;

  const StaggeredAnimatedItem({
    super.key,
    required this.index,
    required this.child,
    this.animate = true,
  });

  @override
  State<StaggeredAnimatedItem> createState() => _StaggeredAnimatedItemState();
}

class _StaggeredAnimatedItemState extends State<StaggeredAnimatedItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _hasAnimated = false;
  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    // Only animate if animate flag is true and hasn't animated before
    if (widget.animate && !_hasAnimated) {
      _hasAnimated = true;
      _animationTimer = Timer(Duration(milliseconds: widget.index * 60), () {
        if (mounted && !_controller.isAnimating) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant StaggeredAnimatedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset animation state if index changes (item moved in list)
    if (oldWidget.index != widget.index) {
      _hasAnimated = false;
      if (widget.animate) {
        _hasAnimated = true;
        _animationTimer?.cancel();
        _animationTimer = Timer(Duration(milliseconds: widget.index * 60), () {
          if (mounted && !_controller.isAnimating) {
            _controller.forward();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

/// Skeleton loading for Quran surahs list
class QuranSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const QuranSkeletonLoader({super.key, this.itemCount = 10});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: AppDimensions.spacing12),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusCard,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loading for Athkar list
class AthkarSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const AthkarSkeletonLoader({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            height: 180,
            margin: const EdgeInsets.only(bottom: AppDimensions.spacing20),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: AppDimensions.radiusXXLarge,
                  cornerSmoothing: 0.6,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loading for integrations list
class IntegrationsSkeletonLoader extends StatelessWidget {
  const IntegrationsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumSkeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          top: 130,
          left: AppDimensions.paddingMedium,
          right: AppDimensions.paddingMedium,
          bottom: 120,
        ),
        child: Column(
          children: List.generate(
            4,
            (index) => Container(
              height: 100,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: AppDimensions.radiusLarge,
                    cornerSmoothing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading for global search results screen
/// Shows skeleton sections for users, conversations, tasks, library, and customers
class GlobalSearchSkeletonLoader extends StatelessWidget {
  final int itemCountPerSection;

  const GlobalSearchSkeletonLoader({super.key, this.itemCountPerSection = 3});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Match library item card colors exactly for shimmer effect
    // Light: cardLight (#FFFFFFFF), Dark: cardDark (#1B4461)
    final baseColor = isDark
        ? AppColors.cardDark
        : AppColors.cardLight;
    final highlightColor = isDark
        ? AppColors.cardDark.withValues(alpha: 0.8)
        : AppColors.cardLight.withValues(alpha: 0.7);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1500),
      direction: ShimmerDirection.ltr,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          // Users Section
          _buildSectionHeader(context),
          ...List.generate(
            itemCountPerSection,
            (index) => _buildUserTile(context),
          ),
          const SizedBox(height: 8),

          // Conversations Section
          _buildSectionHeader(context),
          ...List.generate(
            itemCountPerSection,
            (index) => _buildConversationTile(context),
          ),
          const SizedBox(height: 8),

          // Tasks Section
          _buildSectionHeader(context),
          ...List.generate(
            itemCountPerSection,
            (index) => _buildTaskTile(context),
          ),
          const SizedBox(height: 8),

          // Library Section
          _buildSectionHeader(context),
          ...List.generate(
            itemCountPerSection,
            (index) => _buildLibraryTile(context),
          ),
          const SizedBox(height: 8),

          // Customers Section
          _buildSectionHeader(context),
          ...List.generate(
            itemCountPerSection,
            (index) => _buildCustomerTile(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 80,
            height: 14,
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 4,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 30,
            height: 18,
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: SmoothRectangleBorder(
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 12,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 8,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 12,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 8,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 14,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 8,
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 100,
                  height: 12,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 8,
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 14,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 50,
                  height: 12,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 12,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacing12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 4,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 70,
                  height: 20,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 10,
                        cornerSmoothing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium Empty state widget with animations
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? iconBgColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    this.iconColor,
    this.iconBgColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = iconColor ?? theme.colorScheme.primary;
    final effectiveIconBgColor =
        iconBgColor ?? effectiveIconColor.withValues(alpha: 0.1);

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Opacity(
                  opacity: ((value - 0.8) / 0.2).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: effectiveIconBgColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: effectiveIconColor.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 56, color: effectiveIconColor),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state widget
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorStateWidget({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              SolarLinearIcons.dangerCircle,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppDimensions.spacing16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppDimensions.spacing16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(SolarLinearIcons.restart),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PREMIUM WIDGETS FOR ENHANCED UI
// ============================================================================

/// Premium card with glassmorphism effect and optional interactivity
///
/// Design Specifications:
/// - Border radius: 16px (default) or custom
/// - Shadows: Layered (light mode), Single (dark mode)
/// - Glassmorphism option with BackdropFilter
/// - Interactive variant with scale animation on tap
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool useGlassmorphism;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final double borderRadius;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final bool showShadow;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.useGlassmorphism = false,
    this.gradient,
    this.color,
    this.borderColor,
    this.borderRadius = AppDimensions.radiusLarge,
    this.clipBehavior = Clip.none,
    this.onTap,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildCard() {
      if (useGlassmorphism) {
        return ClipSmoothRect(
          radius: SmoothBorderRadius(
            cornerRadius: borderRadius,
            cornerSmoothing: 1.0,
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding:
                  padding ?? const EdgeInsets.all(AppDimensions.paddingMedium),
              width: double.infinity,
              clipBehavior: clipBehavior,
              decoration: ShapeDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.7),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: borderRadius,
                    cornerSmoothing: 1.0,
                  ),
                  side: BorderSide(
                    color:
                        borderColor ??
                        (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.5)),
                    width: 1.5,
                  ),
                ),
                shadows: [if (!isDark && showShadow) AppShadows.premiumShadow],
              ),
              child: child,
            ),
          ),
        );
      }

      return Container(
        padding: padding ?? const EdgeInsets.all(AppDimensions.paddingMedium),
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(
          gradient: gradient,
          color: gradient == null ? (color ?? theme.cardColor) : null,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: borderRadius,
              cornerSmoothing: 1.0,
            ),
            side: BorderSide(
              color: borderColor ?? theme.dividerColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          shadows: [
            if (theme.brightness != Brightness.dark && showShadow)
              AppShadows.premiumShadow,
          ],
        ),
        child: child,
      );
    }

    // Interactive variant with tap animation
    if (onTap != null) {
      return _InteractiveCardWrapper(
        onTap: onTap!,
        borderRadius: borderRadius,
        child: buildCard(),
      );
    }

    return buildCard();
  }
}

/// Internal wrapper for interactive card animations
class _InteractiveCardWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;

  const _InteractiveCardWrapper({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_InteractiveCardWrapper> createState() =>
      _InteractiveCardWrapperState();
}

class _InteractiveCardWrapperState extends State<_InteractiveCardWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          Haptics.lightTap();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              color: _isPressed
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.02))
                  : Colors.transparent,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Premium animated toggle switch
class PremiumSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;

  const PremiumSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<PremiumSwitch> createState() => _PremiumSwitchState();
}

class _PremiumSwitchState extends State<PremiumSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.normal,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.interactive,
    );

    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(PremiumSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? AppColors.primary;
    final inactiveColor =
        widget.inactiveColor ??
        (theme.brightness == Brightness.dark
            ? Colors.grey[700]!
            : Colors.grey[300]!);

    _colorAnimation = ColorTween(
      begin: inactiveColor,
      end: activeColor,
    ).animate(_animation);

    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            width: 56,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _colorAnimation.value,
              boxShadow: [
                BoxShadow(
                  color: (widget.value ? activeColor : Colors.grey).withValues(
                    alpha: 0.3,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: AppAnimations.normal,
                  curve: AppAnimations.interactive,
                  left: widget.value ? 28 : 4,
                  top: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: widget.value
                        ? const Icon(
                            SolarLinearIcons.checkCircle,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Gradient icon container for premium look
class GradientIconContainer extends StatelessWidget {
  final IconData icon;
  final double size;
  final List<Color>? gradientColors;
  final Color? iconColor;
  final double iconSize;

  const GradientIconContainer({
    super.key,
    required this.icon,
    this.size = 48,
    this.gradientColors,
    this.iconColor,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        gradientColors ??
        [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.primaryLight.withValues(alpha: 0.08),
        ];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(icon, size: iconSize, color: iconColor ?? AppColors.primary),
    );
  }
}

/// Premium gradient button with animation
class PremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final List<Color>? gradientColors;
  final double height;

  const PremiumButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.gradientColors,
    this.height = 52,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.interactive),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        widget.gradientColors ?? [AppColors.primary, AppColors.primaryDark];

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.onPressed == null
                      ? [Colors.grey[400]!, Colors.grey[500]!]
                      : colors,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                boxShadow: widget.onPressed != null
                    ? [
                        BoxShadow(
                          color: colors.first.withValues(alpha: 0.4),
                          blurRadius: _isPressed ? 4 : 12,
                          offset: Offset(0, _isPressed ? 2 : 6),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            widget.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated selection card for premium settings
class PremiumSelectionCard extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;
  final Color? selectedBorderColor;
  final Color? selectedBackgroundColor;

  const PremiumSelectionCard({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.child,
    this.selectedBorderColor,
    this.selectedBackgroundColor,
  });

  @override
  State<PremiumSelectionCard> createState() => _PremiumSelectionCardState();
}

class _PremiumSelectionCardState extends State<PremiumSelectionCard>
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
    final theme = Theme.of(context);
    final selectedBorder = widget.selectedBorderColor ?? AppColors.primary;
    final selectedBg =
        widget.selectedBackgroundColor ??
        AppColors.primary.withValues(alpha: 0.05);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              curve: AppAnimations.interactive,
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              decoration: BoxDecoration(
                color: widget.isSelected ? selectedBg : theme.cardColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                border: Border.all(
                  color: widget.isSelected
                      ? selectedBorder
                      : theme.dividerColor.withValues(alpha: 0.5),
                  width: widget.isSelected ? 2 : 1,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: selectedBorder.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Animated counter for statistics with smooth number transitions
class AnimatedCounter extends StatefulWidget {
  final num value;
  final Duration duration;
  final TextStyle? style;
  final String? suffix;
  final int decimalPlaces;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 800),
    this.style,
    this.suffix,
    this.decimalPlaces = 0,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = Tween<double>(
      begin: 0,
      end: widget.value.toDouble(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value.toDouble();
      _animation =
          Tween<double>(
            begin: _previousValue,
            end: widget.value.toDouble(),
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        String displayValue;
        if (widget.decimalPlaces > 0) {
          displayValue = _animation.value.toStringAsFixed(widget.decimalPlaces);
        } else {
          displayValue = _animation.value.round().toString();
        }
        if (widget.suffix != null) {
          displayValue = '$displayValue ${widget.suffix}';
        }
        return Text(displayValue, style: widget.style);
      },
    );
  }
}

/// Premium section header with gradient icon
class PremiumSectionHeader extends StatelessWidget {
  final String title;
  final bool isSubSection;
  final IconData? icon;

  const PremiumSectionHeader({
    super.key,
    required this.title,
    this.isSubSection = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isSubSection) {
      return Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.hintColor,
          letterSpacing: 0.5,
        ),
      );
    }

    return Row(
      children: [
        if (icon != null) ...[
          GradientIconContainer(icon: icon!, size: 44, iconSize: 24),
          const SizedBox(width: AppDimensions.spacing12),
        ],
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Premium period chip with gradient and animations
class PremiumPeriodChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const PremiumPeriodChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<PremiumPeriodChip> createState() => _PremiumPeriodChipState();
}

class _PremiumPeriodChipState extends State<PremiumPeriodChip>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
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
    final theme = Theme.of(context);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              curve: AppAnimations.interactive,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: widget.isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      )
                    : null,
                color: widget.isSelected ? null : theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: widget.isSelected
                    ? null
                    : Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        width: 1,
                      ),
              ),
              child: Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isSelected
                        ? Colors.white
                        : theme.textTheme.bodyMedium?.color,
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Premium stat card with gradient icon, animations, and trend indicator
class PremiumStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final num value;
  final String? valueSuffix;
  final double trend;
  final int decimalPlaces;

  const PremiumStatCard({
    super.key,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.value,
    this.valueSuffix,
    this.trend = 0.0,
    this.decimalPlaces = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PremiumCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 10,
      ), // Reduced padding slightly if needed, or keep standard
      child: Row(
        children: [
          // Icon with gradient background - Smaller size
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [iconBgColor, iconBgColor.withValues(alpha: 0.5)],
              ),
              borderRadius: BorderRadius.circular(
                14,
              ), // Slightly smaller radius
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.15), // Softer shadow
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12), // Reduced spacing
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 11, // Slightly smaller title
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Wrap in FittedBox to ensure it fits single line
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedCounter(
                    value: value,
                    suffix: valueSuffix,
                    decimalPlaces: decimalPlaces,
                    style: theme.textTheme.titleLarge?.copyWith(
                      // Downgraded from headlineMedium
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                ),
                if (trend != 0.0) ...[
                  const SizedBox(height: 4),
                  _buildTrendBadge(theme, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendBadge(ThemeData theme, bool isDark) {
    final isPositive = trend > 0;
    final color = isPositive ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive
                ? SolarLinearIcons.arrowUp
                : SolarLinearIcons.arrowDown,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${trend.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium chart card with enhanced styling
class PremiumChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget chart;
  final Widget legend;

  const PremiumChartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.chart,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumCard(
      padding: const EdgeInsets.all(AppDimensions.paddingCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.primaryLight.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacing24),
          Row(
            children: [
              Expanded(flex: 3, child: chart),
              Expanded(flex: 2, child: legend),
            ],
          ),
        ],
      ),
    );
  }
}

class ConfettiOverlay extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;

  const ConfettiOverlay({
    super.key,
    this.onComplete,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final List<Color> _colors = [
    AppColors.primary,
    AppColors.accent,
    AppColors.success,
    AppColors.warning,
    AppColors.error,
    const Color(0xFF8B5CF6),
    const Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    
    for (int i = 0; i < 50; i++) {
      _particles.add(_ConfettiParticle(
        x: (i / 50),
        y: -0.1 - (i * 0.02),
        color: _colors[i % _colors.length],
        size: 8 + (i % 4) * 2,
        speed: 0.3 + (i % 5) * 0.1,
        rotation: i * 0.5,
      ));
    }
    
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return IgnorePointer(
          child: CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _ConfettiParticle {
  double x;
  double y;
  final Color color;
  final double size;
  final double speed;
  final double rotation;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.size,
    required this.speed,
    required this.rotation,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final x = particle.x * size.width + (progress * particle.speed * size.width * 0.5);
      final y = (particle.y + progress * particle.speed * 2) * size.height;
      
      if (y > size.height) continue;
      
      final paint = Paint()
        ..color = particle.color.withValues(alpha: 1.0 - progress * 0.5)
        ..style = PaintingStyle.fill;
      
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(particle.rotation + progress * 3);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: particle.size,
          height: particle.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

void showConfetti(BuildContext context, {VoidCallback? onComplete}) {
  late OverlayEntry overlayEntry;
  
  overlayEntry = OverlayEntry(
    builder: (context) => ConfettiOverlay(
      onComplete: () {
        overlayEntry.remove();
        onComplete?.call();
      },
    ),
  );
  
  Overlay.of(context).insert(overlayEntry);
}
