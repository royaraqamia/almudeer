import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import '../../core/api/api_client.dart';
import '../../core/extensions/string_extension.dart';

import '../../data/models/inbox_message.dart';
import '../../core/services/media_cache_manager.dart';

/// The AudioHandler implementation that bridges just_audio with the system
/// media notification (lock-screen controls, notification bar).
class AlMudeerAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  AlMudeerAudioHandler() {
    // Forward player state to AudioService
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Forward duration changes
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    try {
      await _player.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Player stop timeout: $e');
    }
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() =>
      _player.seek(_player.position + const Duration(seconds: 10));

  @override
  Future<void> rewind() => _player.seek(
    _player.position - const Duration(seconds: 10) < Duration.zero
        ? Duration.zero
        : _player.position - const Duration(seconds: 10),
  );

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setAudioSource(AudioSource source) async {
    try {
      await _player.setAudioSource(source).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Player setAudioSource timeout: $e');
      rethrow;
    }
  }

  /// Properly release all player resources
  Future<void> release() async {
    try {
      if (_player.playing) {
        await _player.pause().timeout(const Duration(seconds: 1));
      }
      await _player.stop().timeout(const Duration(seconds: 2));
      await _player.dispose().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Player release error (non-fatal): $e');
    }
  }

  void dispose() {
    // Use release() for proper cleanup with timeouts
    release().catchError((e) => debugPrint('Dispose cleanup error: $e'));
  }
}

/// Singleton guard for AudioService.init — must only be called once
/// in the entire app lifecycle. This ensures both AudioPlayerProvider
/// and AudioPlayerScreen safely share the same handler.
AlMudeerAudioHandler? _globalHandler;
Completer<AlMudeerAudioHandler>? _initCompleter;

/// Returns the singleton AudioHandler, initializing AudioService exactly once.
/// Safe for concurrent callers — uses a Completer to serialize init.
Future<AlMudeerAudioHandler> getOrInitAudioHandler() async {
  // Already initialized
  if (_globalHandler != null) return _globalHandler!;

  // Another call is in-flight, wait for it
  if (_initCompleter != null) return _initCompleter!.future;

  // We are the first caller — do the init
  _initCompleter = Completer<AlMudeerAudioHandler>();
  try {
    final handler = await AudioService.init(
      builder: () => AlMudeerAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.royaraqamia.almudeer.audio',
        androidNotificationChannelName: 'تشغيل الصوت',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
    _globalHandler = handler;
    _initCompleter!.complete(handler);
    return handler;
  } catch (e) {
    _initCompleter!.completeError(e);
    _initCompleter = null; // Allow retry on failure
    rethrow;
  }
}

/// Manages global audio playback for voice notes with system media notification
class AudioPlayerProvider extends ChangeNotifier {
  AlMudeerAudioHandler? _handler;
  bool _isPlayerInitialized = false;
  bool _isDisposed = false;
  bool _isInitializing = false;

  // Active Playback State
  InboxMessage? _currentMessage;
  String? _currentAudioTitle;
  String? _currentAudioSource; // Track the current audio URL/path
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;

  // Progress
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _progress = 0.0; // 0.0 to 1.0

  // Subscription
  StreamSubscription? _playerSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;

  // Getters
  InboxMessage? get currentMessage => _currentMessage;
  String? get currentAudioTitle => _currentAudioTitle;
  String? get currentAudioSource => _currentAudioSource;
  bool get isPlaying => _isPlaying;
  double get playbackSpeed => _playbackSpeed;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  Duration get effectiveTotalDuration {
    if (_totalDuration != Duration.zero) return _totalDuration;
    return _getMetadataDuration(_currentMessage);
  }

  Duration _getMetadataDuration(InboxMessage? message) {
    if (message == null) return Duration.zero;

    final attachment = message.attachments?.firstWhere((a) {
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

  double get progress => _progress;
  bool get hasActiveTrack =>
      _currentMessage != null || _currentAudioTitle != null;

  /// Expose the handler for AudioPlayerScreen to reuse
  AlMudeerAudioHandler? get handler => _handler;

  AudioPlayerProvider() {
    // Lazy init — first call to playMessage will trigger initialization
  }

  /// Guards against concurrent _initPlayer calls
  Future<void>? _initFuture;

  Future<void> _initPlayer() async {
    if (_isPlayerInitialized) return;

    // Deduplicate concurrent calls
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = _doInitPlayer();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInitPlayer() async {
    if (_isPlayerInitialized) return;

    try {
      _isInitializing = true;
      _handler = await getOrInitAudioHandler();

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _isPlayerInitialized = true;
      _initProximity();
      _loadSettings();

      final player = _handler!.player;

      // Listen to player state with error handling
      _playerSubscription = player.playerStateStream.listen(
        (state) {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _progress = 0.0;
            _currentPosition = Duration.zero;
          }
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Player state stream error: $error');
        },
      );

      // Listen to position with error handling
      _positionSubscription = player.positionStream.listen(
        (position) {
          _currentPosition = position;
          if (_totalDuration.inMilliseconds > 0) {
            _progress =
                _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
          }
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Player position stream error: $error');
        },
      );

      // Listen to duration with error handling
      _durationSubscription = player.durationStream.listen(
        (duration) {
          _totalDuration = duration ?? Duration.zero;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Player duration stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('Global Player Init Error: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Play or Resume a message
  Future<void> playMessage(InboxMessage message) async {
    if (_isDisposed) return;

    if (!_isPlayerInitialized && !_isInitializing) {
      await _initPlayer();
    } else if (_isInitializing) {
      // Wait for initialization to complete
      while (_isInitializing && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed) return;

    // If same message, toggle play/pause
    if (_currentMessage?.id == message.id) {
      await togglePlay();
      return;
    }

    // New message - stop current playback first
    await stop(clear: false);
    _currentMessage = message;
    _currentAudioTitle = null;
    _currentAudioSource = null;
    _progress = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = _getMetadataDuration(message);
    notifyListeners();

    // Extract URL/Data
    final attachment = message.attachments?.firstWhere((a) {
      final type = a['type'];
      final mime = a['mime_type'] as String?;
      return type == 'voice' ||
          type == 'audio' ||
          mime?.startsWith('audio/') == true;
    }, orElse: () => {});

    if (attachment == null || attachment.isEmpty) return;

    String? url = (attachment['url'] as String?)?.toFullUrl;
    Uint8List? data;

    if (attachment['data'] != null) {
      try {
        data = base64Decode(attachment['data'] as String);
      } catch (e) {
        debugPrint('Decode error: $e');
      }
    } else if (attachment['base64'] != null) {
      try {
        data = base64Decode(attachment['base64'] as String);
      } catch (e) {
        debugPrint('Decode error: $e');
      }
    }

    if (url == null && data == null && attachment['path'] != null) {
      final localFile = File(attachment['path'] as String);
      if (await localFile.exists()) {
        url = localFile.path;
      }
    }

    if (url == null && data == null) return;

    try {
      if (url != null) {
        final localPath = await MediaCacheManager().getLocalPath(url);
        if (localPath != null && await File(localPath).exists()) {
          url = localPath;
        }
      }

      // Prepare AudioSource
      AudioSource source;
      if (data != null) {
        source = _BufferAudioSource(data);
      } else {
        if (url!.startsWith('http')) {
          source = AudioSource.uri(Uri.parse(url));
        } else {
          source = AudioSource.uri(Uri.file(url));
        }
      }

      await _handler!.setAudioSource(source);

      // Update media notification metadata
      final senderName = message.displayName;
      _handler!.mediaItem.add(
        MediaItem(
          id: message.id.toString(),
          title: senderName,
          album: 'المدير',
          duration: _totalDuration,
        ),
      );

      if (_playbackSpeed != 1.0) {
        await _handler!.setSpeed(_playbackSpeed);
      }

      await _handler!.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Global Play Error: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Play audio from an arbitrary URL or File Path globally
  Future<void> playAudioFile(String urlOrPath, String title) async {
    if (_isDisposed) return;

    if (!_isPlayerInitialized && !_isInitializing) {
      await _initPlayer();
    } else if (_isInitializing) {
      while (_isInitializing && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed) return;

    // If same audio is already playing, just resume/toggle
    if (_currentAudioSource == urlOrPath && _currentMessage == null) {
      await togglePlay();
      return;
    }

    await stop(clear: false);
    _currentMessage = null;
    _currentAudioTitle = title;
    _currentAudioSource = urlOrPath;
    _progress = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    notifyListeners();

    try {
      AudioSource source;
      if (urlOrPath.startsWith('http')) {
        source = AudioSource.uri(Uri.parse(urlOrPath));
      } else {
        source = AudioSource.uri(Uri.file(urlOrPath));
      }

      await _handler!.setAudioSource(source);

      _handler!.mediaItem.add(
        MediaItem(
          id: 'file_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          album: 'المدير',
        ),
      );

      if (_playbackSpeed != 1.0) {
        await _handler!.setSpeed(_playbackSpeed);
      }

      await _handler!.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Global Play Error: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Play Quran recitation from a URL
  Future<void> playQuranRecitation(String url, String surahName) async {
    if (_isDisposed) return;

    if (!_isPlayerInitialized && !_isInitializing) {
      await _initPlayer();
    } else if (_isInitializing) {
      while (_isInitializing && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed) return;

    await stop(clear: false);
    _currentMessage = null;
    _currentAudioTitle = surahName;
    _progress = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    notifyListeners();

    try {
      final source = AudioSource.uri(Uri.parse(url));
      await _handler!.setAudioSource(source);

      _handler!.mediaItem.add(
        MediaItem(
          id: 'quran_$surahName',  // Consistent ID based on surah name
          title: surahName,
          album: 'القرآن الكريم',
          artist: 'تلاوة',
        ),
      );

      if (_playbackSpeed != 1.0) {
        await _handler!.setSpeed(_playbackSpeed);
      }

      await _handler!.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Quran Play Error: $e');
      _isPlaying = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop Quran recitation playback
  Future<void> stopQuranRecitation() async {
    await stop(clear: true);
  }

  /// Play audio from a local file path (used for recording preview)
  Future<void> playFromPath(String filePath) async {
    if (_isDisposed) return;

    if (!_isPlayerInitialized && !_isInitializing) {
      await _initPlayer();
    } else if (_isInitializing) {
      while (_isInitializing && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (_isDisposed) return;

    await stop(clear: false);
    _currentMessage = null;
    _currentAudioTitle = null;
    _progress = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    notifyListeners();

    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final source = AudioSource.uri(Uri.file(filePath));
      await _handler!.setAudioSource(source);

      _handler!.mediaItem.add(
        const MediaItem(
          id: 'preview',
          title: 'معاينة التَّسجيل',
          album: 'المدير',
        ),
      );

      if (_playbackSpeed != 1.0) {
        await _handler!.setSpeed(_playbackSpeed);
      }

      await _handler!.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Preview Play Error: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (_handler == null ||
        (_currentMessage == null && _currentAudioTitle == null)) {
      return;
    }

    final player = _handler!.player;
    final actuallyPlaying = player.playing;

    if (actuallyPlaying) {
      await _handler!.pause();
      _isPlaying = false;
    } else {
      await _handler!.play();
      _isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> seekTo(double percent) async {
    if (_totalDuration.inMilliseconds == 0 || _handler == null) return;

    final ms = (_totalDuration.inMilliseconds * percent).round();
    final pos = Duration(milliseconds: ms);
    await _handler?.seek(pos);
    _currentPosition = pos;
    _progress = percent;
    notifyListeners();
  }

  final ApiClient _apiClient = ApiClient();
  static const String _speedKeyPrefix = 'audio_playback_speed_';

  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed;
    await _handler?.setSpeed(speed);

    // Persist
    try {
      final hash = await _apiClient.getAccountCacheHash();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('$_speedKeyPrefix$hash', speed);
    } catch (e) {
      debugPrint('Speed persistence error: $e');
    }

    notifyListeners();
  }

  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final hash = await _apiClient.getAccountCacheHash();
      final prefs = await SharedPreferences.getInstance();
      _playbackSpeed = prefs.getDouble('$_speedKeyPrefix$hash') ?? 1.0;
      if (_handler != null && _playbackSpeed != 1.0) {
        await _handler!.setSpeed(_playbackSpeed);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stop({bool clear = true}) async {
    try {
      await _handler?.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Stop timeout: $e');
    }
    _isPlaying = false;
    if (clear) {
      _currentMessage = null;
      _currentAudioTitle = null;
      _currentAudioSource = null;
      _progress = 0.0;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    }
    notifyListeners();
  }

  StreamSubscription? _proximitySubscription;
  bool _isNear = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Cancel all subscriptions
    _proximitySubscription?.cancel();
    _playerSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();

    // Release player resources properly
    if (_handler != null) {
      try {
        // Release the internal player with timeout
        _handler!.release().catchError((e) {
          debugPrint('Handler release error during dispose: $e');
        });
      } catch (e) {
        debugPrint('Handler dispose error: $e');
      }
    }

    // Do NOT dispose _globalHandler — it outlives the provider and is app-scoped
    super.dispose();
  }

  Future<void> _initProximity() async {
    if (_proximitySubscription != null) return;
    try {
      _proximitySubscription = ProximitySensor.events.listen((int event) {
        final isNear = event > 0;
        if (_isNear != isNear) {
          _isNear = isNear;
          _updateAudioRoute();
        }
      });
    } catch (e) {
      debugPrint('Proximity init error: $e');
    }
  }

  Future<void> _updateAudioRoute() async {
    if (!_isPlaying) return;
    try {
      final session = await AudioSession.instance;
      if (_isNear) {
        // Earpiece
        await session.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          ),
        );
      } else {
        // Speaker
        await session.configure(const AudioSessionConfiguration.music());
      }
    } catch (e) {
      debugPrint('Audio Route Error: $e');
    }
  }

  /// Close the mini player (stops playback)
  void closePlayer() {
    stop(clear: true);
  }

  /// Completely release all player resources
  /// Use this when the app needs to free up audio resources (e.g., incoming call)
  Future<void> releaseAllResources() async {
    await stop(clear: true);

    // Cancel all subscriptions
    _playerSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _proximitySubscription?.cancel();

    _playerSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _proximitySubscription = null;

    // Release the handler's player
    if (_handler != null) {
      await _handler!.release();
      _handler = null;
    }

    _isPlayerInitialized = false;
    notifyListeners();
  }
}

/// Helper class to play from bytes in just_audio
// ignore: experimental_member_use
class _BufferAudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  _BufferAudioSource(this._buffer) : super(tag: 'BufferAudioSource');

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      contentType: 'audio/mpeg',
      stream: Stream.value(_buffer.sublist(start, end)),
    );
  }
}
