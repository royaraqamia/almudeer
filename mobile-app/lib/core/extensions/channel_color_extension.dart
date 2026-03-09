import 'package:flutter/material.dart';
import '../constants/colors.dart';

extension ChannelColorExtension on String {
  Color get channelColor {
    switch (toLowerCase()) {
      case 'whatsapp':
        return AppColors.whatsappGreen;
      case 'telegram':
      case 'telegram_bot':
        return AppColors.telegramBlue;
      case 'email':
        return AppColors.emailRed;
      default:
        return AppColors.primary;
    }
  }
}
