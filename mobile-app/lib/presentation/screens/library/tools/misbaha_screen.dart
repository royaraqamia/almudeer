import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/constants/colors.dart';
import '../../../../core/utils/haptics.dart';
import '../../../providers/athkar_provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

class MisbahaScreen extends StatefulWidget {
  const MisbahaScreen({super.key});

  @override
  State<MisbahaScreen> createState() => _MisbahaScreenState();
}

class _MisbahaScreenState extends State<MisbahaScreen> {
  int _target = 33;
  final List<int> _commonTargets = [33, 99, 100];

  void _handleTap() {
    final provider = context.read<AthkarProvider>();
    provider.incrementMisbaha();

    if (provider.misbahaCount % _target == 0) {
      Haptics.heavyTap();
    } else {
      Haptics.lightTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<AthkarProvider>();
    final count = provider.misbahaCount;
    final progress = (count % _target) / _target;
    final cycle = (count / _target).floor();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'المسبحة الإلكترونية',
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
            onPressed: () => provider.resetMisbaha(),
            tooltip: 'إعادة ضبط العداد',
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          // Target Selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _commonTargets.map((t) {
                final isSelected = _target == t;
                return GestureDetector(
                  onTap: () => setState(() => _target = t),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : theme.cardColor,
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
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          // Main Counter Display
          GestureDetector(
            onTap: _handleTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress Circle
                SizedBox(
                  width: 280,
                  height: 280,
                  child: CircularProgressIndicator(
                    value: progress == 0 && count > 0 ? 1.0 : progress,
                    strokeWidth: 12,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                // Counter Text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      count.toString(),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 80,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                    ),
                    if (cycle > 0)
                      Text(
                        'الدورة: $cycle',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.grey,
                          fontFamily: 'IBM Plex Sans Arabic',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
