/// Dimension constants for consistent spacing and sizing
/// 
/// Design System Guidelines:
/// - Spacing uses 4px grid system (Material Design & iOS standard)
/// - Border radius follows component-specific naming for consistency
/// - All touch targets minimum 44x44px (WCAG 2.1 AA)
class AppDimensions {
  // Prevent instantiation
  AppDimensions._();

  // ─────────────────────────────────────────────────────────────────
  // Spacing Scale (4px Grid System)
  // ─────────────────────────────────────────────────────────────────
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing6 = 6.0;
  static const double spacing8 = 8.0;
  static const double spacing10 = 10.0;
  static const double spacing12 = 12.0;
  static const double spacing14 = 14.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;
  static const double spacing80 = 80.0;
  static const double spacing100 = 100.0;

  // Padding (aligned with spacing scale)
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // ─────────────────────────────────────────────────────────────────
  // Border Radius (Component-Specific Naming)
  // Web uses --radius: 0.625rem = 10px as base
  // ─────────────────────────────────────────────────────────────────
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusDefault = 10.0; // Matches web --radius
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;
  static const double radiusXXLarge = 24.0;
  static const double radiusFull = 999.0;
  
  // Component-specific radius for consistency
  static const double radiusButton = 24.0;      // Pill-shaped buttons
  static const double radiusInput = 24.0;       // Pill-shaped inputs
  static const double radiusCard = 16.0;        // Standard cards
  static const double radiusDialog = 24.0;      // Dialogs/modals
  static const double radiusBottomSheet = 32.0; // Bottom sheets
  static const double radiusChip = 999.0;       // Full round chips

  // Card-specific dimensions
  static const double paddingCard = 20.0;
  static const double cardMargin = 16.0;

  // ─────────────────────────────────────────────────────────────────
  // Icon Sizes (Aligned with Material Design)
  // ─────────────────────────────────────────────────────────────────
  static const double iconSmall = 16.0;
  static const double iconMedium = 20.0;
  static const double iconLarge = 24.0;
  static const double iconXLarge = 32.0;
  static const double iconXXLarge = 48.0;

  // ─────────────────────────────────────────────────────────────────
  // Button Heights (Minimum 44px for accessibility)
  // ─────────────────────────────────────────────────────────────────
  static const double buttonHeightSmall = 40.0;  // Increased from 36
  static const double buttonHeightMedium = 48.0; // Standardized to 48
  static const double buttonHeightLarge = 56.0;

  // ─────────────────────────────────────────────────────────────────
  // Avatar Sizes
  // ─────────────────────────────────────────────────────────────────
  static const double avatarSmall = 32.0;
  static const double avatarMedium = 40.0;
  static const double avatarLarge = 48.0;
  static const double avatarXLarge = 64.0;

  // Card
  static const double cardElevation = 2.0;
  static const double cardBorderWidth = 1.0;

  // Bottom Navigation
  static const double bottomNavHeight = 60.0;

  // List Padding (accounts for bottom nav + safe area)
  static const double listBottomPadding = 120.0;

  // App Bar
  static const double appBarHeight = 56.0;

  // ─────────────────────────────────────────────────────────────────
  // Chat Dimensions
  // ─────────────────────────────────────────────────────────────────
  static const double chatBubbleMaxWidth = 0.8; // 80% of screen width
  static const double chatBubbleRadius = 18.0;
  static const double chatInputHeight = 56.0;
  static const double chatAvatarSize = 44.0;

  // Conversation List
  static const double conversationTileHeight = 76.0;
  static const double conversationAvatarSize = 52.0;

  // ─────────────────────────────────────────────────────────────────
  // Touch Target Minimums (WCAG 2.1 AA: 44x44px)
  // ─────────────────────────────────────────────────────────────────
  static const double touchTargetMin = 44.0;
  static const double touchTargetComfortable = 48.0;

  // Animations
  static const int animationDurationFast = 150;
  static const int animationDurationMedium = 300;
  static const int animationDurationSlow = 500;
}
