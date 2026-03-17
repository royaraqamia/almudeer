import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_player_provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import '../../../core/services/media_service.dart';
import '../../../core/utils/premium_toast.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/sharing_service.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String? audioUrl;
  final String? filePath;
  final String? fileName;
  final String? heroTag;

  const AudioPlayerScreen({
    super.key,
    this.audioUrl,
    this.filePath,
    this.fileName,
    this.heroTag,
  }) : assert(
         audioUrl != null || filePath != null,
         'Must provide either audioUrl or filePath',
       );

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();

  static Future<void> open(
    BuildContext context, {
    String? audioUrl,
    String? filePath,
    String? fileName,
    String? heroTag,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          audioUrl: audioUrl,
          filePath: filePath,
          fileName: fileName,
          heroTag: heroTag,
        ),
      ),
    );
  }
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final provider = context.read<AudioPlayerProvider>();
          final path = widget.filePath ?? widget.audioUrl;

          // Check if same audio is already playing
          if (provider.currentAudioSource == path &&
              provider.currentMessage == null) {
            // Same audio is already playing, just update UI (don't reset)
            return;
          }

          if (path != null) {
            await provider.playAudioFile(path, widget.fileName ?? 'مقطع صوتي');
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = e.toString();
            });
            PremiumToast.show(
              context,
              'فشل تشغيل الصوت: ${e.toString()}',
              icon: SolarLinearIcons.dangerCircle,
              isError: true,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    // Note: We don't stop the audio here as it's managed globally
    // The audio continues playing in the background after navigation
    super.dispose();
  }

  void _handleBack() {
    // Navigate back but keep audio playing in the global player
    Navigator.of(context).pop();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, provider, child) {
        if (_hasError) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
                onPressed: _handleBack,
              ),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    SolarLinearIcons.dangerCircle,
                    size: 64,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'فشل تشغيل الصوت',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? 'خطأ غير معروف',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final duration = provider.effectiveTotalDuration;
        final position = provider.currentPosition;
        final isPlaying = provider.isPlaying;
        final speed = provider.playbackSpeed;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
              onPressed: _handleBack,
            ),
            title: Text(
              widget.fileName ?? 'Audio',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    SolarLinearIcons.share,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => _shareAudio(context),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    SolarLinearIcons.download,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => _saveAudio(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < screenWidth / 2) {
                  provider.handler?.rewind();
                } else {
                  provider.handler?.fastForward();
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Album Art / Icon
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Hero(
                      tag: widget.heroTag ?? 'audio_art',
                      child: const Icon(
                        SolarLinearIcons.musicNote,
                        size: 80,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Progress Slider
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.grey[800],
                            thumbColor: AppColors.primary,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            min: 0.0,
                            max: 1.0,
                            value: provider.progress.clamp(0.0, 1.0),
                            onChanged: (value) {
                              provider.seekTo(value);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(color: Colors.grey),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Speed
                      TextButton(
                        onPressed: () {
                          double newSpeed = 1.0;
                          if (speed == 1.0) {
                            newSpeed = 1.5;
                          } else if (speed == 1.5) {
                            newSpeed = 2.0;
                          } else {
                            newSpeed = 1.0;
                          }
                          provider.setSpeed(newSpeed);
                        },
                        child: Text(
                          '${speed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Rewind 10s
                      IconButton(
                        onPressed: () {
                          provider.handler?.rewind();
                        },
                        icon: const Icon(SolarLinearIcons.rewind10SecondsBack),
                        color: Colors.white,
                        iconSize: 32,
                      ),
                      const SizedBox(width: 20),

                      // Play/Pause
                      Container(
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: () => provider.togglePlay(),
                          icon: Icon(
                            isPlaying
                                ? SolarLinearIcons.pause
                                : SolarLinearIcons.play,
                          ),
                          color: Colors.white,
                          iconSize: 48,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Forward 10s
                      IconButton(
                        onPressed: () {
                          provider.handler?.fastForward();
                        },
                        icon: const Icon(
                          SolarLinearIcons.rewind10SecondsForward,
                        ),
                        color: Colors.white,
                        iconSize: 32,
                      ),
                      const SizedBox(width: 20),

                      // Hidden Spacer to balance UI
                      const SizedBox(width: 48),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareAudio(BuildContext context) async {
    final String? path = widget.filePath ?? widget.audioUrl;
    if (path == null) return;

    SharingService().showShareMenu(
      context,
      filePath: path,
      type: 'audio',
      title: widget.fileName,
    );
  }

  Future<void> _saveAudio(BuildContext context) async {
    final String? path = widget.filePath ?? widget.audioUrl;
    if (path == null) return;

    try {
      final success = await MediaService.saveToFile(
        path,
        widget.fileName ?? 'Audio',
      );
      if (context.mounted) {
        if (success) {
          PremiumToast.show(
            context,
            'تم الحفظ بنجاح',
            icon: SolarLinearIcons.checkCircle,
          );
        } else {
          PremiumToast.show(
            context,
            'فشل الحفظ',
            icon: SolarLinearIcons.dangerCircle,
            isError: true,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.show(
          context,
          'خطأ: $e',
          icon: SolarLinearIcons.dangerCircle,
          isError: true,
        );
      }
    }
  }
}
