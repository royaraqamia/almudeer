import 'dart:ui' as ui;
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class RecordingVisualizer extends StatelessWidget {
  final RecorderController recorderController;
  final bool isLocked;
  final bool isCancelling;

  const RecordingVisualizer({
    super.key,
    required this.recorderController,
    this.isLocked = false,
    this.isCancelling = false,
  });

  @override
  Widget build(BuildContext context) {
    // If cancelling, we might want to show a different visual, e.g., red or fading
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final waveColor = isCancelling
        ? AppColors.error
        : (isDark ? Colors.white : AppColors.primary);

    return AudioWaveforms(
      enableGesture: false,
      size: Size(MediaQuery.of(context).size.width / 2, 40),
      recorderController: recorderController,
      waveStyle: WaveStyle(
        waveColor: waveColor,
        extendWaveform: true,
        showMiddleLine: false,
        spacing: 4.0, // Denser premium spacing
        waveThickness: 2.5, // Denser premium thickness
        // Gradient for a premium feel
        gradient: ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, 40),
          [
            waveColor.withValues(alpha: 0.2), // Punchy edges
            waveColor,
            waveColor.withValues(alpha: 0.2),
          ],
          [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
