import 'package:flutter/material.dart';

class ToolItem {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final Color gradientStart;
  final Color gradientEnd;
  final Widget Function() screen;

  const ToolItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.gradientStart,
    required this.gradientEnd,
    required this.screen,
  });

  ToolItem copyWith({
    String? id,
    String? title,
    IconData? icon,
    Color? color,
    Color? gradientStart,
    Color? gradientEnd,
    Widget Function()? screen,
  }) {
    return ToolItem(
      id: id ?? this.id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      screen: screen ?? this.screen,
    );
  }
}
