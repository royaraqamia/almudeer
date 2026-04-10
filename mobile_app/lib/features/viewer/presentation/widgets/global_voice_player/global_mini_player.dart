import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/core/constants/dimensions.dart';
import 'package:almudeer_mobile_app/core/utils/haptics.dart';
import '../../providers/audio_player_provider.dart';
import 'package:almudeer_mobile_app/features/inbox/presentation/providers/conversation_detail_provider.dart';
import 'package:almudeer_mobile_app/core/extensions/string_extension.dart';
import 'package:almudeer_mobile_app/features/viewer/presentation/screens/audio_player_screen.dart';

class GlobalMiniPlayer extends StatefulWidget {
  const GlobalMiniPlayer({super.key});

  @override
  State<GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<GlobalMiniPlayer> {
  double _dragOffset = 0.0;

  void _openFullPlayer() {
    Haptics.lightTap();
    AudioPlayerScreen.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final bottomPadding = mediaQuery.padding.bottom;
    final viewInsetsBottom = mediaQuery.viewInsets.bottom;

    return Consumer2<AudioPlayerProvider, ConversationDetailProvider>(
      builder: (context, player, detail, child) {
        if (!player.hasActiveTrack) {
          // Reset drag offset when player is closed
          if (_dragOffset != 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _dragOffset = 0);
            });
          }
          return const SizedBox.shrink();
        }

        final isMessage = player.currentMessage != null;
        final title = isMessage
            ? player.currentMessage!.displayName.safeUtf16
            : (player.currentAudioTitle ?? 'ظ…ظ‚ط·ط¹ طµظˆطھظٹ');

        // Detect if we are in a conversation based on the provider state
        final isInChat = detail.senderContact != null;

        // Use a higher offset if in chat to clear the message input box and AI drafts
        final double baseOffset = isInChat
            ? AppDimensions.chatInputHeight
            : AppDimensions.bottomNavHeight;

        // The calculated margin without dragging
        final double defaultBottomMargin = viewInsetsBottom > 0
            ? viewInsetsBottom + baseOffset + 24
            : (bottomPadding + baseOffset + 24);

        // Apply drag offset (positive offset moves it UP)
        final double bottomMargin = (defaultBottomMargin + _dragOffset).clamp(
          8.0, // Minimum margin from bottom
          screenSize.height - 150, // Maximum margin (don't let it go off top)
        );

        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onTap: _openFullPlayer,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _dragOffset -= details.delta.dy;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(
                  milliseconds: 50,
                ), // Snappier for dragging
                curve: Curves.easeOut,
                margin: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: bottomMargin,
                ),
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.hintColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        // Icon / Avatar
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMessage
                                ? SolarLinearIcons.microphone
                                : SolarLinearIcons.musicNote,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Info
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        showValueIndicator:
                                            ShowValueIndicator.never,
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 14,
                                            ),
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        activeTrackColor: AppColors.primary,
                                        inactiveTrackColor: theme.hintColor
                                            .withValues(alpha: 0.2),
                                        thumbColor: AppColors.primary,
                                      ),
                                      child: Slider(
                                        value: player.progress.clamp(0.0, 1.0),
                                        onChanged: (value) {
                                          player.seekTo(value);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    player.currentPosition.inMilliseconds > 0
                                        ? '${_formatDuration(player.currentPosition)} / ${_formatDuration(player.effectiveTotalDuration)}'
                                        : _formatDuration(
                                            player.effectiveTotalDuration,
                                          ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 10,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Controls
                        IconButton(
                          onPressed: () {
                            Haptics.lightTap();
                            player.togglePlay();
                          },
                          icon: Icon(
                            player.isPlaying
                                ? SolarLinearIcons.pause
                                : SolarLinearIcons.play,
                            color: AppColors.primary,
                          ),
                        ),

                        IconButton(
                          onPressed: () {
                            Haptics.lightTap();
                            player.closePlayer();
                          },
                          icon: Icon(
                            SolarLinearIcons.closeCircle,
                            color: theme.hintColor,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes.toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}
