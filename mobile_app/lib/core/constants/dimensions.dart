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

  // Responsive breakpoints
  static const double breakpointSmallHeight = 600.0;
  static const double loginCardMaxWidth = 480.0;
  static const double loginCardPaddingSmall = 24.0;
  static const double loginCardPaddingLarge = 36.0;
  static const double loginCardHorizontalPaddingSmall = 20.0;
  static const double loginCardHorizontalPaddingLarge = 24.0;

  // ─────────────────────────────────────────────────────────────────
  // Border Radius (Component-Specific Naming)
  // Web uses --radius: 0.625rem = 10px as base
  // ─────────────────────────────────────────────────────────────────
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusDefault = 10.0; // Matches web --radius
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;
  static const double radiusLoginCard = 20.0; // Unified login card radius
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

  // ─────────────────────────────────────────────────────────────────
  // Subscription Screen Dimensions
  // ─────────────────────────────────────────────────────────────────
  static const double statusIconSize = 52.0;
  static const double circularProgressSize = 72.0;
  static const double progressStrokeWidth = 6.0;
  static const double subscriptionCardMinHeight = 180.0;

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

  // ─────────────────────────────────────────────────────────────────
  // Login Screen Dimensions
  // ─────────────────────────────────────────────────────────────────
  // Icon container
  static const double loginIconContainerSize = 88.0;
  static const double loginIconSize = 42.0;

  // Spacing
  static const double loginIconMarginTop = 28.0;
  static const double loginTitleMarginTop = 8.0;
  static const double loginSubtitleMarginTop = 8.0;
  static const double loginFieldMarginTop = 32.0;
  static const double loginButtonMarginTop = 16.0;
  static const double loginErrorMarginTop = 16.0;
  static const double loginAccountsMarginTop = 24.0;
  static const double loginWhatsAppMarginTop = 24.0; // Reduced from 48px

  // Typography
  static const double loginTitleSize = 24.0;
  static const double loginSubtitleSize = 15.0;
  static const double loginLabelSize = 14.0;
  static const double loginHintSize = 12.0;
  static const double loginErrorSize = 13.0;
  static const double loginShowMoreSize = 14.0;
  static const double loginEmptyStateSize = 13.0;

  // Account card
  static const double accountCardPaddingHorizontal = 16.0;
  static const double accountCardPaddingVertical = 12.0;
  static const double accountCardMarginBottom = 8.0;
  static const double accountAvatarRadius = 20.0;
  static const double accountNameSize = 14.0;
  static const double accountUsernameSize = 12.0;
  static const double accountBadgePaddingHorizontal = 8.0;
  static const double accountBadgePaddingVertical = 4.0;
  static const double accountIconSize = 20.0;
  static const double accountBadgeIconSize = 14.0;
  static const double accountActiveScale = 1.02; // Subtle scale for active state

  // Error message
  static const double errorPadding = 12.0;
  static const double errorIconSize = 20.0;
  static const double errorIconMarginEnd = 12.0;

  // Header
  static const double headerLogoHeight = 32.0;
  static const double headerLogoMarginEnd = 8.0;
  static const double headerTitleSize = 20.0;

  // WhatsApp button
  static const double whatsappIconSize = 20.0;
  static const double whatsappDividerMarginTop = 24.0;
  static const double whatsappDividerMarginBottom = 16.0;

  // Show more/less button
  static const double showMoreMarginTop = 4.0;
  static const double showMoreMarginBottom = 8.0;
  static const double showMoreLabelMarginEnd = 4.0;
  static const double showMoreLabelMarginBottom = 12.0;

  // Screen spacing
  static const double loginScreenTopPaddingSmall = 16.0;
  static const double loginScreenTopPaddingLarge = 24.0;
  static const double loginScreenHeaderMarginSmall = 24.0;
  static const double loginScreenHeaderMarginLarge = 32.0;

  // Saved accounts list
  static const int loginMaxVisibleAccounts = 4;
}
