import 'package:flutter/material.dart';

/// A wrapper that adds fading gradient overlays to indicate scrollable content
/// Shows left/right fades based on scroll position
class FadingScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final double fadeWidth;
  final Color? fadeColor;

  const FadingScrollWrapper({
    super.key,
    required this.child,
    required this.scrollController,
    this.fadeWidth = 24.0,
    this.fadeColor,
  });

  @override
  State<FadingScrollWrapper> createState() => _FadingScrollWrapperState();
}

class _FadingScrollWrapperState extends State<FadingScrollWrapper> {
  bool _showStartFade = false;
  bool _showEndFade = true;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateFades);
    super.dispose();
  }

  void _updateFades() {
    if (!widget.scrollController.hasClients) return;

    final position = widget.scrollController.position;
    final atStart = position.pixels <= 0;
    final atEnd = position.pixels >= position.maxScrollExtent;

    if (_showStartFade != !atStart || _showEndFade != !atEnd) {
      setState(() {
        _showStartFade = !atStart;
        _showEndFade = !atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fadeColor = widget.fadeColor ?? theme.scaffoldBackgroundColor;

    return Stack(
      children: [
        widget.child,
        // Start (left in LTR, right in RTL) fade
        if (_showStartFade)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: widget.fadeWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [fadeColor, fadeColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        // End (right in LTR, left in RTL) fade
        if (_showEndFade)
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            width: widget.fadeWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerEnd,
                    end: AlignmentDirectional.centerStart,
                    colors: [fadeColor, fadeColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
