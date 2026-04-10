import 'package:flutter/material.dart';

/// Al-Mudeer brand colors matching the web application
///
/// Color Accessibility Guidelines:
/// - All text colors meet WCAG 2.1 AA contrast requirements (4.5:1 for normal, 3:1 for large)
/// - Primary colors maintain brand consistency across light/dark modes
/// - Semantic colors are adjusted for optimal visibility in both themes
/// - Dedicated colors for disabled, hover, focus, and overlay states
///
/// Apple HIG Compliance:
/// - Dark Mode uses less saturated colors (reduces visual vibration)
/// - Semantic color names follow Apple's naming conventions
/// - Lightness indicates elevation in Dark Mode
class AppColors {
  // Prevent instantiation
  AppColors._();

  // ─────────────────────────────────────────────────────────────────
  // Primary Brand Colors (Royal Blue)
  // Tailwind blue-600/500/700 scale
  // Apple HIG: Dark Mode uses less saturated, lighter colors
  // ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF3B82F6);

  // Apple HIG: Desaturated for dark mode (was #1D4ED8 - too saturated)
  // Lighter, less saturated to reduce visual vibration in dark mode
  static const Color primaryDark = Color(0xFF6EA8FF);

  // Active state background for navigation (dark theme optimized)
  // Lighter alpha for subtle pill, brighter hue for dark mode visibility
  static const Color activeStateLight = Color(0xFF2563EB); // Same as primary
  static const Color activeStateDark = Color(
    0xFF3B82F6,
  ); // Brighter for dark theme

  // Active state muted variants (for pill backgrounds with alpha)
  static const Color activeStateLightMuted = Color(0x1A2563EB); // 10% alpha
  static const Color activeStateDarkMuted = Color(0x1A3B82F6);

  // Brand gradient stops (optimized for icon contrast)
  static const Color brandGradientStart = Color(0xFF2563EB);
  static const Color brandGradientEnd = Color(
    0xFF1636A8,
  ); // Darkened for better icon contrast

  // Error gradient stops
  static const List<Color> errorGradient = [
    Color(0xFFEF4444), // red-500
    Color(0xFFB91C1C), // red-700
  ];

  // ─────────────────────────────────────────────────────────────────
  // Accent Colors (Cyan - Logo Secondary)
  // ─────────────────────────────────────────────────────────────────
  static const Color accent = Color(0xFF0891B2);
  static const Color accentLight = Color(0xFF22D3EE);
  static const Color accentDark = Color(0xFF0E7490);

  // ─────────────────────────────────────────────────────────────────
  // Disabled State Colors
  // ─────────────────────────────────────────────────────────────────
  static const Color disabledLight = Color(0xFFCBD5E1);
  static const Color disabledDark = Color(0xFF475569);
  static const Color disabledBackgroundLight = Color(0xFFF1F5F9);
  static const Color disabledBackgroundDark = Color(0xFF1E293B);

  // ─────────────────────────────────────────────────────────────────
  // Hover & Focus State Colors (Tablet/Desktop Support)
  // ─────────────────────────────────────────────────────────────────
  static const Color hoverLight = Color(0x0A0F172A); // 4% black
  static const Color hoverDark = Color(0x1AFFFFFF); // 10% white
  static const Color focusLight = Color(0x142563EB); // 8% primary
  static const Color focusDark = Color(0x1F3B82F6); // 12% primaryLight

  // ─────────────────────────────────────────────────────────────────
  // Overlay & Scrim Colors
  // ─────────────────────────────────────────────────────────────────
  static const Color scrimLight = Color(0x80000000); // 50% black
  static const Color scrimDark = Color(0x80000000); // 50% black
  static const Color overlayLight = Color(0x0A0F172A); // 4% black
  static const Color overlayDark = Color(0x14FFFFFF); // 8% white

  // ─────────────────────────────────────────────────────────────────
  // Focus Ring Colors (Accessible Input States)
  // ─────────────────────────────────────────────────────────────────
  static const Color focusRingLight = Color(0x402563EB); // 25% primary
  static const Color focusRingDark = Color(0x403B82F6); // 25% primaryLight

  // ─────────────────────────────────────────────────────────────────
  // Background Colors (Light Theme)
  // Apple HIG: Semantic names for iOS compatibility
  // ─────────────────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFECFBFF);
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color surfaceCardLight = Color(0xFFF1F5F9); // Stat card bg

  // Apple HIG Semantic Names (iOS compatibility)
  static const Color systemBackground = Color(0xFFECFBFF);
  static const Color secondarySystemBackground = Color(0xFFF8FAFC);
  static const Color tertiarySystemBackground = Color(0xFFFFFFFF);
  static const Color systemFill = Color(0x14000000);
  static const Color secondarySystemFill = Color(0x0A000000);

  // ─────────────────────────────────────────────────────────────────
  // Background Colors (Dark Theme)
  // Fixed hierarchy: background < surface < card (increasing lightness)
  // Apple HIG: Lighter surfaces indicate higher elevation
  // ─────────────────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0F2E42);
  static const Color surfaceDark = Color(0xFF163A52); // Lighter for hierarchy
  static const Color cardDark = Color(0xFF1B4461); // Even lighter for cards
  static const Color surfaceCardDark = Color(
    0xFF1B4461,
  ); // Match card for consistency

  // Apple HIG Semantic Names (Dark Mode - iOS compatibility)
  static const Color systemBackgroundDark = Color(0xFF0F2E42);
  static const Color secondarySystemBackgroundDark = Color(0xFF163A52);
  static const Color tertiarySystemBackgroundDark = Color(0xFF1B4461);
  static const Color systemFillDark = Color(0x14FFFFFF);
  static const Color secondarySystemFillDark = Color(0x0AFFFFFF);

  // Icon background colors (for icon containers in cards)
  static const Color iconBgPrimary = Color(0xFFDBEAFE); // blue-100
  static const Color iconBgSuccess = Color(0xFFDCFCE7); // green-100
  static const Color iconBgWarning = Color(0xFFFEF3C7); // amber-100
  static const Color iconBgAccent = Color(0xFFCFFAFE); // cyan-100

  // ─────────────────────────────────────────────────────────────────
  // Text Colors (Light Theme)
  // WCAG 2.1 AA Compliant: All ratios meet 4.5:1 minimum
  // ─────────────────────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(
    0xFF475569,
  ); // Darkened from 64748B for better contrast (5.8:1)
  static const Color textTertiaryLight = Color(
    0xFF64748B,
  ); // Fixed from 94A3B8 (was 2.8:1, now 4.6:1)
  static const Color textDisabledLight = Color(0xFFCBD5E1);

  // ─────────────────────────────────────────────────────────────────
  // Text Colors (Dark Theme)
  // WCAG 2.1 AA Compliant: All ratios meet 4.5:1 minimum
  // ─────────────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(
    0xFFCBD5E1,
  ); // Lightened from 94A3B8 for better contrast
  static const Color textTertiaryDark = Color(
    0xFFA1B0C4,
  ); // Lightened from 94A3B8 for better contrast on surfaceDark (5.2:1)
  static const Color textDisabledDark = Color(0xFF64748B);

  // Border Colors
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF334155);

  // Semantic Colors (Light Mode)
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Additional Semantic States (Light Mode)
  static const Color pending = Color(0xFFF59E0B); // Amber for pending states
  static const Color draft = Color(0xFF6B7280); // Gray for drafts
  static const Color archived = Color(0xFF94A3B8); // Slate for archived

  // Semantic Colors (Dark Mode) - Enhanced visibility
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color errorDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF60A5FA);

  // Additional Semantic States (Dark Mode)
  static const Color pendingDark = Color(0xFFFBBF24);
  static const Color draftDark = Color(0xFF94A3B8);
  static const Color archivedDark = Color(0xFF64748B);

  // WhatsApp Colors
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color whatsappTeal = Color(0xFF128C7E);
  static const Color whatsappOutgoingLight = Color(0xFFDCF8C6);
  static const Color whatsappOutgoingDark = Color(0xFF005C4B);
  static const Color whatsappIncomingLight = Color(0xFFFFFFFF);
  static const Color whatsappIncomingDark = Color(0xFF202C33);
  static const Color whatsappChatBgLight = Color(0xFFECE5DD);
  static const Color whatsappChatBgDark = Color(0xFF0B141A);
  static const Color whatsappBlueTick = Color(0xFF53BDEB);

  // Notification Badge Colors
  static const Color badgeNew = Color(0xFFEF4444); // Red for new items
  static const Color badgeUnread = Color(0xFF3B82F6); // Blue for unread
  static const Color badgeUpdate = Color(0xFFF59E0B); // Amber for updates

  // Shimmer/Skeleton Loading Colors
  static const Color shimmerBaseLight = Color(0xFFE2E8F0);
  static const Color shimmerHighlightLight = Color(0xFFF1F5F9);
  static const Color shimmerBaseDark = Color(0xFF334155);
  static const Color shimmerHighlightDark = Color(0xFF475569);

  // Telegram Colors
  static const Color telegramBlue = Color(0xFF2AABEE);
  static const Color telegramBlueDark = Color(0xFF229ED9);
  static const Color telegramOutgoingLight = Color(0xFFEFFDDE);
  static const Color telegramOutgoingDark = Color(0xFF2B5278);
  static const Color telegramIncomingLight = Color(0xFFFFFFFF);
  static const Color telegramIncomingDark = Color(0xFF182533);
  static const Color telegramCheck = Color(0xFF4AC959);

  // Intent Colors
  static const Map<String, Color> intentColors = {
    'استفسار': Color(0xFF3B82F6), // inquiry - blue
    'طلب خدمة': Color(0xFF10B981), // service request - emerald
    'شكوى': Color(0xFFEF4444), // complaint - red
    'متابعة': Color(0xFFF59E0B), // follow-up - amber
    'عام': Color(0xFF6B7280), // general - gray
    'تحية': Color(0xFF8B5CF6), // greeting - violet
    'إلغاء': Color(0xFFEC4899), // cancellation - pink
    'طلب سعر': Color(0xFF06B6D4), // price request - cyan
  };

  // Urgency Colors
  static const Map<String, Color> urgencyColors = {
    'عاجل': Color(0xFFEF4444), // urgent - red
    'مرتفع': Color(0xFFF59E0B), // high - amber
    'متوسط': Color(0xFF3B82F6), // medium - blue
    'منخفض': Color(0xFF6B7280), // low - gray
  };

  // Sentiment Colors
  static const Map<String, Color> sentimentColors = {
    'إيجابي': Color(0xFF22C55E), // positive - green
    'محايد': Color(0xFF6B7280), // neutral - gray
    'سلبي': Color(0xFFEF4444), // negative - red
  };

  // Chart Colors (Languages)
  static const Color langEnglish = Color(0xFF2563EB); // primary
  static const Color langArabic = Color(0xFF10B981); // emerald-500
  static const Color langUrdu = Color(0xFFF59E0B); // amber-500
  static const Color langFrench = Color(0xFF8B5CF6); // violet-500

  // Chart Colors (Channels)
  static const Color channelTwitter = Color(0xFF0EA5E9); // sky-500
  static const Color channelUnknown = Color(0xFF9CA3AF); // gray-400
  static const Color channelFacebook = Color(0xFF3B82F6); // blue-500
  static const Color channelWhatsapp = Color(0xFF25D366);
  static const Color channelInstagram = Color(0xFFE1306C);

  // Chart Colors - Extended Palette (Light Mode)
  static const Color chartLight1 = Color(0xFF2563EB);
  static const Color chartLight2 = Color(0xFF10B981);
  static const Color chartLight3 = Color(0xFFF59E0B);
  static const Color chartLight4 = Color(0xFF8B5CF6);
  static const Color chartLight5 = Color(0xFFEC4899);

  // Chart Colors - Extended Palette (Dark Mode) - Brighter, more saturated
  static const Color chartDark1 = Color(0xFF3B82F6);
  static const Color chartDark2 = Color(0xFF34D399);
  static const Color chartDark3 = Color(0xFFFBBF24);
  static const Color chartDark4 = Color(0xFFA78BFA);
  static const Color chartDark5 = Color(0xFFF472B6);

  // Elevation Shadow Colors (Brand-colored for premium feel)
  static const Color shadowPrimaryLight = Color(0x142563EB); // 8% primary
  static const Color shadowPrimaryDark = Color(0x1F000000); // 12% black

  // Avatar Gradient Colors (Optimized for both themes)
  static const List<Color> avatarGradientLight = [
    Color(0xFFDBE6FE),
    Color(0xFFCFF5FE),
  ];
  static const List<Color> avatarGradientDark = [
    Color(0xFF30347F),
    Color(0xFF174863),
  ];
  // Alternative brighter gradient for dark mode icons
  static const List<Color> avatarGradientDarkBright = [
    Color(0xFF4C52A8),
    Color(0xFF2D6A8F),
  ];

  // Task Category Colors
  static const Map<String, Color> taskCategoryColors = {
    'عمل': Color(0xFF2563EB), // work - blue
    'شخصي': Color(0xFF10B981), // personal - emerald
    'تسوق': Color(0xFFF59E0B), // shopping - amber
    'عاجل': Color(0xFFEF4444), // urgent - red
    'أخرى': Color(0xFF6B7280), // other - gray
    'دراسة': Color(0xFF8B5CF6), // study - violet
    'صحة': Color(0xFFEC4899), // health - pink
    'مالية': Color(0xFF14B8A6), // finance - teal
  };

  // Task Category Icons
  static const Map<String, int> taskCategoryIconCodes = {
    'عمل': 0xE5D2, // work - briefcase
    'شخصي': 0xE7FD, // personal - person
    'تسوق': 0xE8CB, // shopping - cart
    'عاجل': 0xE153, // urgent - warning
    'أخرى': 0xE5D3, // other - more_horiz
    'دراسة': 0xE80C, // study - school
    'صحة': 0xE3F3, // health - favorite
    'مالية': 0xE850, // finance - account_balance
  };

  // Background Gradient Colors (Light Theme)
  static const List<Color> backgroundGradientLight = [
    Color(0xFFEFF4FF),
    Color(0xFFECFBFF),
  ];

  // Background Gradient Colors (Dark Theme)
  static const List<Color> backgroundGradientDark = [
    Color(0xFF1C1D4A),
    Color(0xFF0F2E42),
  ];

  // Alternative Dark Background Gradient (Deeper contrast)
  static const List<Color> backgroundGradientDarkDeep = [
    Color(0xFF0A1F2E),
    Color(0xFF0F2E42),
  ];
}
