import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../models/tool_item.dart';
import '../calculator_screen.dart';
// import '../enhanced_send_receive_screen.dart'; // Hidden for future development
import '../quran/quran_screen.dart';
import '../athkar/athkar_screen.dart';
import '../browser_screen.dart';
import '../misbaha_screen.dart';
import 'package:almudeer_mobile_app/features/qr/presentation/screens/qr_scanner_screen.dart';

class ToolsData {
  ToolsData._();

  static List<ToolItem> getAllTools() {
    return [
      // Hidden for future development - nearby-share tool
      // ToolItem(
      //   id: 'share',
      //   title: 'ط§ظ„ظ…ط´ط§ط±ظƒط©',
      //   icon: SolarLinearIcons.transmission,
      //   color: const Color(0xFF2563EB),
      //   gradientStart: const Color(0xFF3B82F6),
      //   gradientEnd: const Color(0xFF1D4ED8),
      //   screen: () => const EnhancedSendReceiveScreen(),
      // ),
      ToolItem(
        id: 'calculator',
        title: 'ط§ظ„ط­ط§ط³ط¨ط©',
        icon: SolarLinearIcons.calculator,
        color: Colors.blue,
        gradientStart: const Color(0xFF60A5FA),
        gradientEnd: const Color(0xFF2563EB),
        screen: () => const CalculatorScreen(),
      ),
      ToolItem(
        id: 'quran',
        title: 'ط§ظ„ظ‚ط±ط¢ظ† ط§ظ„ظƒط±ظٹظ…',
        icon: SolarLinearIcons.bookBookmark,
        color: const Color(0xFF10B981),
        gradientStart: const Color(0xFF34D399),
        gradientEnd: const Color(0xFF059669),
        screen: () => const QuranScreen(),
      ),
      ToolItem(
        id: 'athkar',
        title: 'ط§ظ„ط£ط°ظƒط§ط±',
        icon: SolarLinearIcons.sun,
        color: const Color(0xFFF97316),
        gradientStart: const Color(0xFFFB923C),
        gradientEnd: const Color(0xFFEA580C),
        screen: () => const AthkarScreen(),
      ),
      ToolItem(
        id: 'browser',
        title: 'ط§ظ„ظ…طھطµظپظگظ‘ط­',
        icon: SolarLinearIcons.global,
        color: const Color(0xFF3B82F6),
        gradientStart: const Color(0xFF60A5FA),
        gradientEnd: const Color(0xFF1D4ED8),
        screen: () => const BrowserScreen(),
      ),
      ToolItem(
        id: 'misbaha',
        title: 'ط§ظ„ظ…ط³ط¨ط­ط©',
        icon: SolarLinearIcons.videocameraRecord,
        color: Colors.teal,
        gradientStart: const Color(0xFF2DD4BF),
        gradientEnd: const Color(0xFF14B8A6),
        screen: () => const MisbahaScreen(),
      ),
      ToolItem(
        id: 'qr_scanner',
        title: 'ظ…ط§ط³ط­ QR',
        icon: SolarLinearIcons.qrCode,
        color: const Color(0xFF8B5CF6),
        gradientStart: const Color(0xFFA78BFA),
        gradientEnd: const Color(0xFF7C3AED),
        screen: () => const QRScannerScreen(),
      ),
    ];
  }

  static List<ToolItem> searchTools(List<ToolItem> allTools, String query) {
    if (query.isEmpty) return allTools;
    final lowerQuery = query.toLowerCase();
    return allTools
        .where((t) => t.title.toLowerCase().contains(lowerQuery))
        .toList();
  }
}
