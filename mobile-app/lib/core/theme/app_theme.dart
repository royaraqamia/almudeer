import 'package:flutter/material.dart';
import '../constants/animations.dart';
import '../constants/colors.dart';
import '../constants/dimensions.dart';
import 'package:figma_squircle/figma_squircle.dart';

/// App theme configuration matching the web application
///
/// Design System Principles:
/// - Consistent border radius using AppDimensions constants
/// - Typography scale optimized for Arabic readability
/// - Focus indicators for accessibility
/// - Proper touch targets (minimum 44px)
class AppTheme {
  // Prevent instantiation
  AppTheme._();

  /// Light theme
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.textPrimaryLight,
        error: AppColors.error,
        onError: Colors.white,
      ),
      fontFamily: 'IBM Plex Sans Arabic',
      scaffoldBackgroundColor: AppColors.backgroundLight,
      cardColor: AppColors.cardLight,
      dividerColor: AppColors.borderLight,
      focusColor: AppColors.focusLight,
      hoverColor: AppColors.hoverLight,
      highlightColor: AppColors.primary.withValues(alpha: 0.08),

      // Typography - Fixed scale for proper hierarchy
      textTheme: _buildTextTheme(Brightness.light),

      // AppBar
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.backgroundLight,
        foregroundColor: AppColors.textPrimaryLight,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryLight),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundLight,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondaryLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Cards - Using standardized radius
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.cardLight,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusCard,
            cornerSmoothing: 1.0,
          ),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),

      // Buttons - Using standardized heights and radius
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
          // Add hover state for tablet/desktop support
          overlayColor: AppColors.hoverLight,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16, // Standardized from 18
            fontWeight: FontWeight.w600,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      ),

      // Input Decoration - Using standardized radius and border states
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        constraints: const BoxConstraints(
          minHeight: AppDimensions.buttonHeightMedium,
        ),
        // Focus indicator for accessibility
        focusColor: AppColors.focusRingLight,
        border: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.borderLight, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.borderLight, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: const TextStyle(
          color: AppColors.textTertiaryLight,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryLight),
      ),

      // Chip Theme - Using standardized radius
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusChip,
            cornerSmoothing: 1.0,
          ),
        ),
      ),

      // Dialog - Using standardized radius
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardLight,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusDialog,
            cornerSmoothing: 1.0,
          ),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 16,
          color: AppColors.textSecondaryLight,
        ),
      ),

      // Snackbar - Using standardized radius (16px for floating style)
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimaryLight,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXLarge,
            cornerSmoothing: 1.0,
          ),
        ),
        elevation: 0,
        behavior: SnackBarBehavior.floating,
      ),

      // Fast page transitions
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FastPageTransitionsBuilder(),
          TargetPlatform.iOS: _FastPageTransitionsBuilder(),
        },
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusBottomSheet,
            cornerSmoothing: 1.0,
          ),
        ),
        // Focus indicator
        modalBackgroundColor: AppColors.scrimLight,
      ),
    );
  }

  /// Dark theme
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textPrimaryDark,
        error: AppColors.error,
        onError: Colors.white,
      ),
      fontFamily: 'IBM Plex Sans Arabic',
      // Typography - Fixed scale for proper hierarchy
      textTheme: _buildTextTheme(Brightness.dark),

      // AppBar
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textPrimaryDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textSecondaryDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Cards - Using standardized radius
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.cardDark,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusCard,
            cornerSmoothing: 1.0,
          ),
        ),
      ),

      // Buttons - Using standardized heights and radius
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
          // Add hover state for tablet/desktop support
          overlayColor: AppColors.hoverDark,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          side: const BorderSide(color: AppColors.primaryLight),
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          minimumSize: const Size(
            double.infinity,
            AppDimensions.buttonHeightMedium,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
            vertical: AppDimensions.paddingMedium,
          ),
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: AppDimensions.radiusButton,
              cornerSmoothing: 1.0,
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'IBM Plex Sans Arabic',
          ),
        ),
      ),

      // Input Decoration - Using standardized radius and border states
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        constraints: const BoxConstraints(
          minHeight: AppDimensions.buttonHeightMedium,
        ),
        // Focus indicator for accessibility
        focusColor: AppColors.focusRingDark,
        border: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.borderDark, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.borderDark, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusInput,
            cornerSmoothing: 1.0,
          ),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: const TextStyle(
          color: AppColors.textTertiaryDark,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
      ),

      // Chip Theme - Using standardized radius
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceDark,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'IBM Plex Sans Arabic',
        ),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusChip,
            cornerSmoothing: 1.0,
          ),
        ),
      ),

      // Dialog - Using standardized radius
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardDark,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusDialog,
            cornerSmoothing: 1.0,
          ),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 16,
          color: AppColors.textSecondaryDark,
        ),
      ),

      // Snackbar - Using standardized radius (16px for floating style)
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        contentTextStyle: const TextStyle(color: AppColors.textPrimaryDark),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusXLarge,
            cornerSmoothing: 1.0,
          ),
        ),
        elevation: 0,
        behavior: SnackBarBehavior.floating,
      ),

      // Fast page transitions
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FastPageTransitionsBuilder(),
          TargetPlatform.iOS: _FastPageTransitionsBuilder(),
        },
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: AppDimensions.radiusBottomSheet,
            cornerSmoothing: 1.0,
          ),
        ),
        // Focus indicator
        modalBackgroundColor: AppColors.scrimDark,
      ),
    );
  }

  /// Build text theme for both light and dark modes
  ///
  /// Typography Scale (optimized for Arabic readability):
  /// - Display: 32, 28, 24 (headlines, large titles)
  /// - Headline: 28, 24, 20 (section headers)
  /// - Title: 20, 18, 16 (card titles, subtitles)
  /// - Body: 16, 14, 12 (content text - fixed from oversized values)
  /// - Label: 16, 14, 12 (buttons, labels)
  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color textColor = brightness == Brightness.light
        ? AppColors.textPrimaryLight
        : AppColors.textPrimaryDark;
    final Color secondaryColor = brightness == Brightness.light
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;

    return TextTheme(
      // Display styles - Large headlines
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textColor,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textColor,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textColor,
        height: 1.2,
      ),
      // Headline styles - Section headers
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      // Title styles - Card titles, subtitles
      titleLarge: TextStyle(
        fontSize: 20, // Fixed from 24
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontSize: 18, // Fixed from 20
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontSize: 16, // Fixed from 18
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.4,
      ),
      // Body styles - Content text (fixed from oversized values)
      bodyLarge: TextStyle(
        fontSize: 16, // Fixed from 24 - proper body text size
        fontWeight: FontWeight.w400,
        color: textColor,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14, // Fixed from 20 - proper body text size
        fontWeight: FontWeight.w400,
        color: textColor,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12, // Fixed from 18 - proper caption size
        fontWeight: FontWeight.w400,
        color: secondaryColor,
        height: 1.4,
      ),
      // Label styles - Buttons, labels
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textColor,
        height: 1.2,
      ),
      labelMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        height: 1.2,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        height: 1.1,
      ),
    );
  }
}

/// Custom fast page transitions builder
class _FastPageTransitionsBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppAnimations.enter),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: AppAnimations.enter),
            ),
        child: child,
      ),
    );
  }
}
