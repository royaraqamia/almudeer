import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:hijri/hijri_calendar.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/constants/shadows.dart';
import '../../../../core/constants/animations.dart';
import '../../../../core/extensions/string_extension.dart';
import '../../../widgets/common_widgets.dart';
import 'data/tools_data.dart';
import 'models/tool_item.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    HijriCalendar.setLocal('ar');
    final hijriNow = HijriCalendar.now();
    final dateStr = hijriNow.toFormat('DD, dd MMMM yyyy').toEnglishNumbers;

    final allTools = ToolsData.getAllTools();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme, dateStr),
            Expanded(child: _buildToolsContent(theme, allTools)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String dateStr) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 14,
              fontFamily: 'IBM Plex Sans Arabic',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsContent(ThemeData theme, List<ToolItem> tools) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppDimensions.listBottomPadding),
      child: _buildToolsGrid(tools, theme),
    );
  }

  Widget _buildToolsGrid(List<ToolItem> tools, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppDimensions.paddingMedium,
          mainAxisSpacing: AppDimensions.paddingMedium,
          childAspectRatio: 1.5,
        ),
        itemCount: tools.length,
        itemBuilder: (context, index) {
          return StaggeredAnimatedItem(
            index: index,
            child: ToolCard(
              tool: tools[index],
              onTap: () => _navigateToTool(tools[index], context),
            ),
          );
        },
      ),
    );
  }

  void _navigateToTool(ToolItem tool, BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => tool.screen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }
}

class ToolCard extends StatefulWidget {
  final ToolItem tool;
  final VoidCallback onTap;

  const ToolCard({super.key, required this.tool, required this.onTap});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: AppAnimations.fast, // Apple standard: 250ms (was 100ms)
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(scale: _scaleAnimation.value, child: child);
      },
      child: Semantics(
        button: true,
        label: widget.tool.title,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => _pressController.forward(),
            onTapUp: (_) => _pressController.reverse(),
            onTapCancel: () => _pressController.reverse(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: ShapeDecoration(
                color: isDark ? AppColors.surfaceCardDark : theme.cardColor,
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 16,
                    cornerSmoothing: 1.0,
                  ),
                  side: BorderSide.none,
                ),
                shadows: [
                  if (theme.brightness != Brightness.dark) AppShadows.premiumShadow,
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIconSection(theme),
                        const SizedBox(height: 8.0),
                        _buildTitle(theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.white;
    return Hero(
      tag: 'tool_icon_${widget.tool.id}',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.tool.gradientStart,
              widget.tool.gradientEnd,
            ],
          ),
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: widget.tool.color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          widget.tool.icon,
          color: iconColor,
          size: 24.0,
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Text(
      widget.tool.title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        fontFamily: 'IBM Plex Sans Arabic',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
