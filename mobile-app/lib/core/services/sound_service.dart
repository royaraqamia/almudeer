import 'package:just_audio/just_audio.dart';
import 'package:logger/logger.dart';

/// Service to manage audio effect playback across the application.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final Logger _logger = Logger();
  final AudioPlayer _uiPlayer = AudioPlayer();
  final AudioPlayer _callPlayer =
      AudioPlayer(); // Dedicated player for ringing/looping

  bool _soundsEnabled = true;
  bool _isInitialized = false;

  /// Initialize the sound service and pre-cache resources
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Configuration can be added here (e.g., from settings)
      _isInitialized = true;
      _logger.i('SoundService initialized');
    } catch (e) {
      _logger.e('Failed to initialize SoundService: $e');
    }
  }

  /// Toggle sounds globally
  void setEnabled(bool enabled) {
    _soundsEnabled = enabled;
  }

  /// Play a sound effect from assets
  Future<void> _playSound(
    String assetPath, {
    double volume = 1.0,
    bool loop = false,
  }) async {
    if (!_soundsEnabled) return;

    try {
      final player = loop ? _callPlayer : _uiPlayer;

      // For non-looping UI sounds, we use a fire-and-forget approach
      // but ensure the player is ready.
      await player.setAsset('assets/audio/$assetPath');
      await player.setVolume(volume);
      await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);

      if (loop) {
        await player.play();
      } else {
        // Don't await the play call for UI responsiveness
        unawaited(player.play());
      }
    } catch (e) {
      _logger.w('Error playing sound $assetPath: $e');
    }
  }

  // --- Message Sounds ---

  void playMessageIncoming() => _playSound('message_incoming.mp3');
  void playMessageOutgoing() => _playSound('message_outgoing.mp3');
  void playTypingIndicator() => _playSound('typing.mp3', volume: 0.5);
  void playRecordingIndicator() =>
      _playSound('recording_start.mp3', volume: 0.5);

  // --- Call Sounds ---

  Future<void> playCallOutgoingRinging() =>
      _playSound('outgoing_ringing.mp3', loop: true);

  void stopCallRinging() {
    try {
      _callPlayer.stop();
    } catch (e) {
      _logger.e('Error stopping call ringing: $e');
    }
  }

  void playCallEnded() => _playSound('call_ended.mp3');
  void playCallJoined() => _playSound('call_joined.mp3');

  // --- System Sounds ---

  void playActionSuccess() => _playSound('action_success.mp3');
  void playActionDeleted() => _playSound('delete_confirmation.mp3');
  void playTransferSuccess() => _playSound('transfer_success.mp3');
  void playTransferError() => _playSound('transfer_error.mp3');

  /// Dispose players
  Future<void> dispose() async {
    try {
      // Stop and dispose UI player
      await _uiPlayer.stop();
      await _uiPlayer.setLoopMode(LoopMode.off);
      await _uiPlayer.dispose();
      
      // Stop and dispose call player
      await _callPlayer.stop();
      await _callPlayer.setLoopMode(LoopMode.off);
      await _callPlayer.dispose();
    } catch (e) {
      _logger.e('Error disposing players: $e');
    }
    _isInitialized = false;
  }
}

// Helper for fire-and-forget futures
void unawaited(Future<void> future) {}
