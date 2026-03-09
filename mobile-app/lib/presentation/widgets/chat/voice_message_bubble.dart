import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/colors.dart';
import '../../../core/extensions/string_extension.dart';
import '../../../core/services/audio_waveform_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/inbox_message.dart';
import '../../providers/audio_player_provider.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../widgets/animated_toast.dart';

/// Voice message bubble with premium playback controls and waveform
class VoiceMessageBubble extends StatefulWidget {
  final InboxMessage message;
  final bool isOutgoing;
  final Color color;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    required this.color,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  List<double> _waveform = [];
  Duration? _fileDuration;
  bool _isDownloading = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    // 1. Initial placeholder immediately so UI doesn't collapse
    if (mounted && _waveform.isEmpty) {
      final random = Random();
      setState(() {
        _waveform = List.generate(40, (_) => 0.1 + (random.nextDouble() * 0.2));
      });
    }

    final attachment = widget.message.attachments?.firstWhere((a) {
      final type = a['type'];
      final mime = a['mime_type'] as String?;
      return type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true;
    }, orElse: () => {});

    if (attachment != null && attachment.isNotEmpty) {
      if (attachment['url'] != null) {
        final url = (attachment['url'] as String).toFullUrl;
        final filename =
            attachment['filename'] as String? ??
            attachment['file_name'] as String?;
        final path = await MediaCacheManager().getLocalPath(
          url,
          filename: filename,
        );
        if (mounted) {
          setState(() {
            _localPath = path;
          });
          if (_localPath != null) {
            _loadWaveform();
          }
        }
      } else if (attachment['path'] != null) {
        final localFile = File(attachment['path'] as String);
        if (await localFile.exists()) {
          if (mounted) {
            setState(() {
              _localPath = localFile.path;
            });
            _loadWaveform();
          }
        }
      }
    }
  }

  Future<void> _download() async {
    final attachment = widget.message.attachments?.firstWhere((a) {
      final type = a['type'];
      final mime = a['mime_type'] as String?;
      return type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true;
    }, orElse: () => {});

    if (attachment == null || attachment.isNotEmpty != true) return;

    if (attachment['url'] == null) {
      if (attachment['path'] != null) {
        if (mounted) {
          setState(() {
            _localPath = attachment['path'] as String;
          });
          _loadWaveform();
        }
      }
      return;
    }

    final url = (attachment['url'] as String).toFullUrl;

    setState(() => _isDownloading = true);

    try {
      final filename =
          attachment['filename'] as String? ??
          attachment['file_name'] as String?;
      final path = await MediaCacheManager().downloadFile(
        url,
        filename: filename,
      );
      if (mounted) {
        setState(() {
          _localPath = path;
          _isDownloading = false;
        });
        _loadWaveform();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        AnimatedToast.error(context, 'فشل تحميل الصوت: $e');
      }
    }
  }

  Future<void> _loadWaveform() async {
    if (_localPath == null) return;

    final attachment = widget.message.attachments?.firstWhere((a) {
      final type = a['type'];
      final mime = a['mime_type'] as String?;
      return type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true;
    }, orElse: () => {});

    if (attachment != null && attachment.isNotEmpty) {
      try {
        String audioSource;
        if (attachment['url'] != null) {
          audioSource = (attachment['url'] as String).toFullUrl;
        } else if (attachment['path'] != null) {
          audioSource = attachment['path'] as String;
        } else {
          return;
        }

        final data = await AudioWaveformService().getWaveform(
          audioSource,
          samples: 40,
        );

        if (mounted) {
          setState(() {
            if (data.samples.isNotEmpty) {
              _waveform = data.samples;
            }
            if (data.duration != Duration.zero) {
              _fileDuration = data.duration;
            }
          });
        }
      } catch (e) {
        // Keep placeholder on error
      }
    }
  }

  void _onPlay(AudioPlayerProvider player) async {
    if (_localPath == null && !_isDownloading) {
      await _download();
      // After download, play
      if (_localPath != null) {
        player.playMessage(widget.message);
      }
      return;
    }

    if (_localPath != null) {
      player.playMessage(widget.message);
    }
  }

  void _onSeek(AudioPlayerProvider player, double percentage) {
    player.seekTo(percentage);
  }

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes.toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Duration _getMetadataDuration() {
    // 1. Prefer extracted duration from file (most accurate)
    if (_fileDuration != null && _fileDuration != Duration.zero) {
      return _fileDuration!;
    }

    final attachment = widget.message.attachments?.firstWhere((a) {
      final type = a['type'];
      final mime = a['mime_type'] as String?;
      return type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true;
    }, orElse: () => {});

    if (attachment == null || attachment.isEmpty) return Duration.zero;

    final d =
        attachment['duration'] ??
        attachment['duration_ms'] ??
        attachment['duration_seconds'];
    if (d == null) return Duration.zero;

    if (d is int) {
      if (d > 1000 || attachment.containsKey('duration_ms')) {
        return Duration(milliseconds: d);
      }
      return Duration(seconds: d);
    } else if (d is double) {
      return Duration(milliseconds: (d * 1000).toInt());
    }

    return Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final playButtonColor = isDark
        ? theme.canvasColor.withValues(alpha: 0.2)
        : (widget.isOutgoing
              ? Colors.white
              : AppColors.primary.withValues(alpha: 0.1));

    final playIconColor = isDark ? Colors.white : AppColors.primary;

    final waveformBaseColor = isDark || widget.isOutgoing
        ? Colors.white.withValues(alpha: 0.3)
        : AppColors.primary.withValues(alpha: 0.15);

    final waveformActiveColor = isDark || widget.isOutgoing
        ? Colors.white
        : AppColors.primary;

    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : (widget.isOutgoing
              ? Colors.white.withValues(alpha: 0.9)
              : theme.hintColor.withValues(alpha: 0.8));

    return Consumer<AudioPlayerProvider>(
      builder: (context, player, child) {
        final isPlayingMe =
            player.currentMessage?.id == widget.message.id && player.isPlaying;
        final isPausedMe =
            player.currentMessage?.id == widget.message.id && !player.isPlaying;
        final myProgress = (player.currentMessage?.id == widget.message.id)
            ? player.progress
            : 0.0;
        final myPos = (player.currentMessage?.id == widget.message.id)
            ? player.currentPosition
            : Duration.zero;

        // Fix: Sync accurate duration from player if available
        if ((isPlayingMe || isPausedMe) &&
            player.totalDuration != Duration.zero &&
            player.totalDuration != _fileDuration) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _fileDuration = player.totalDuration;
              });
            }
          });
        }

        return Semantics(
          label: isPlayingMe
              ? 'جار التشغيل، اضغط للإيقاف'
              : 'رسالة صوتية، اضغط للتشغيل',
          child: InkWell(
            onTap: () {
              Haptics.lightTap();
              _onPlay(player);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
                minWidth: 200,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Play/Pause button with shadow
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: playButtonColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isPlayingMe && !isDark)
                              ? playButtonColor.withValues(alpha: 0.4)
                              : Colors.black.withValues(alpha: 0.05),
                          blurRadius: isPlayingMe ? 12 : 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      isPlayingMe ? SolarBoldIcons.pause : SolarBoldIcons.play,
                      color: playIconColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive Waveform with smooth bars
                        SizedBox(
                          height: 38,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth == 0 ||
                                  constraints.maxWidth.isInfinite) {
                                return const SizedBox();
                              }
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  Haptics.selection();
                                  if (player.currentMessage?.id ==
                                      widget.message.id) {
                                    _onSeek(
                                      player,
                                      details.localPosition.dx /
                                          constraints.maxWidth,
                                    );
                                  }
                                },
                                onHorizontalDragUpdate: (details) {
                                  if (player.currentMessage?.id ==
                                      widget.message.id) {
                                    Haptics.selection(); // Tactile seeking
                                    double seek =
                                        details.localPosition.dx /
                                        constraints.maxWidth;
                                    _onSeek(player, seek.clamp(0.0, 1.0));
                                  }
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: List.generate(_waveform.length, (
                                    index,
                                  ) {
                                    final amplitude = _waveform[index];
                                    final isCompleted =
                                        myProgress > (index / _waveform.length);
                                    // Senior UX: Smooth bar height scaling
                                    final barHeight =
                                        8 +
                                        (amplitude *
                                            28); // Slightly taller minimum

                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width:
                                          2.5, // Denser, more premium waveform
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? waveformActiveColor
                                            : waveformBaseColor.withValues(
                                                alpha: 0.35,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          1.5,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Duration and Speed
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Builder(
                              builder: (context) {
                                final totalDuration =
                                    (isPlayingMe || isPausedMe) &&
                                        player.totalDuration != Duration.zero
                                    ? player.totalDuration
                                    : _getMetadataDuration();

                                return Text(
                                  isPlayingMe || isPausedMe
                                      ? "${_formatDuration(myPos)} / ${_formatDuration(totalDuration)}"
                                      : (totalDuration != Duration.zero
                                            ? _formatDuration(totalDuration)
                                            : 'رسالة صوتية'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (isPlayingMe || isPausedMe)
                              GestureDetector(
                                onTap: () {
                                  Haptics.mediumTap();
                                  double newSpeed = player.playbackSpeed >= 2.0
                                      ? 1.0
                                      : player.playbackSpeed + 0.5;
                                  player.setSpeed(newSpeed);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical:
                                        4, // Slightly taller pill for balance
                                  ),
                                  decoration: BoxDecoration(
                                    color: playButtonColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${player.playbackSpeed.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '')}x",
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
