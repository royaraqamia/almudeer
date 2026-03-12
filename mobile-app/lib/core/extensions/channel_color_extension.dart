import 'package:flutter/material.dart';
import '../constants/colors.dart';

extension ChannelColorExtension on String {
  Color get channelColor {
    switch (toLowerCase()) {
      case 'telegram':
      case 'telegram_bot':
        return AppColors.telegramBlue;
      default:
        return AppColors.primary;
    }
  }
}
