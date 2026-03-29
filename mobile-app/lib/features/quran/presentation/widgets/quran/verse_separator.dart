import 'package:flutter/material.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';

/// A beautiful ornamental verse separator widget similar to popular Quran apps.
/// Displays the verse number in a decorative Islamic-style design.
class VerseSeparator extends StatelessWidget {
  final int verseNumber;
  final double size;

  const VerseSeparator({
    super.key,
    required this.verseNumber,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative end caps
          Positioned(
            left: 0,
            child: _buildEndCap(
              isReversed: false,
              size: size * 0.15,
            ),
          ),
          Positioned(
            right: 0,
            child: _buildEndCap(
              isReversed: true,
              size: size * 0.15,
            ),
          ),
          // Center ornamental circle with verse number
          Container(
            width: size * 0.7,
            height: size * 0.7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.primary.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: size * 0.55,
                height: size * 0.55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: Center(
                  child: Text(
                    _toEasternArabicNumerals(verseNumber),
                    style: const TextStyle(
                      fontFamily: 'Amiri Quran',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      height: 1.0,
                      inherit: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Connecting lines
          Positioned(
            left: size * 0.15,
            right: size * 0.15,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primary.withValues(alpha: 0.3),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
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

  Widget _buildEndCap({required bool isReversed, required double size}) {
    return Transform.rotate(
      angle: isReversed ? 0 : 3.14159,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  String _toEasternArabicNumerals(int number) {
    const easternArabicNumerals = ['ظ ', 'ظ،', 'ظ¢', 'ظ£', 'ظ¤', 'ظ¥', 'ظ¦', 'ظ§', 'ظ¨', 'ظ©'];
    return number.toString().split('').map((digit) {
      return easternArabicNumerals[int.parse(digit)];
    }).join('');
  }
}
