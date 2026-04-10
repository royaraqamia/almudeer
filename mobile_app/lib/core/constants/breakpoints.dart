/// Responsive breakpoints for adaptive layouts
/// 
/// Breakpoint Guidelines (Material Design 3):
/// - Mobile: 0-599px (phone, small tablet portrait)
/// - Tablet: 600-1023px (tablet, large phone)
/// - Desktop: 1024px+ (desktop, tablet landscape)
class AppBreakpoints {
  // Prevent instantiation
  AppBreakpoints._();

  // ─────────────────────────────────────────────────────────────────
  // Screen Size Breakpoints
  // ─────────────────────────────────────────────────────────────────
  
  /// Maximum width for mobile phones
  static const double mobileMax = 599.0;
  
  /// Minimum width for tablets
  static const double tabletMin = 600.0;
  
  /// Maximum width for tablets
  static const double tabletMax = 1023.0;
  
  /// Minimum width for desktop
  static const double desktopMin = 1024.0;
  
  /// Large desktop minimum
  static const double desktopLargeMin = 1440.0;

  // ─────────────────────────────────────────────────────────────────
  // Layout Constraints
  // ─────────────────────────────────────────────────────────────────
  
  /// Maximum content width for readability
  static const double contentMaxWidth = 800.0;
  
  /// Maximum width for centered content
  static const double centeredMaxWidth = 1200.0;
  
  /// Side margin for mobile layouts
  static const double mobileMargin = 16.0;
  
  /// Side margin for tablet layouts
  static const double tabletMargin = 24.0;
  
  /// Side margin for desktop layouts
  static const double desktopMargin = 32.0;

  // ─────────────────────────────────────────────────────────────────
  // Grid System
  // ─────────────────────────────────────────────────────────────────
  
  /// Number of columns for mobile
  static const int mobileColumns = 4;
  
  /// Number of columns for tablet
  static const int tabletColumns = 8;
  
  /// Number of columns for desktop
  static const int desktopColumns = 12;
  
  /// Gutter width for mobile
  static const double mobileGutter = 16.0;
  
  /// Gutter width for tablet
  static const double tabletGutter = 24.0;
  
  /// Gutter width for desktop
  static const double desktopGutter = 24.0;

  // ─────────────────────────────────────────────────────────────────
  // Helper Methods
  // ─────────────────────────────────────────────────────────────────
  
  /// Check if screen width is mobile
  static bool isMobile(double width) => width < tabletMin;
  
  /// Check if screen width is tablet
  static bool isTablet(double width) => width >= tabletMin && width < desktopMin;
  
  /// Check if screen width is desktop
  static bool isDesktop(double width) => width >= desktopMin;
  
  /// Get appropriate margin based on screen width
  static double getMargin(double width) {
    if (width < tabletMin) return mobileMargin;
    if (width < desktopMin) return tabletMargin;
    return desktopMargin;
  }
  
  /// Get appropriate column count based on screen width
  static int getColumnCount(double width) {
    if (width < tabletMin) return mobileColumns;
    if (width < desktopMin) return tabletColumns;
    return desktopColumns;
  }
}
