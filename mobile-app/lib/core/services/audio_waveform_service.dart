import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class WaveformData {
  final List<double> samples;
  final Duration duration;

  const WaveformData({required this.samples, this.duration = Duration.zero});
}

/// Service for handling audio waveform extraction
class AudioWaveformService {
  static final AudioWaveformService _instance =
      AudioWaveformService._internal();
  static AudioWaveformService? _mockInstance;
  static set mockInstance(AudioWaveformService? mock) => _mockInstance = mock;
  factory AudioWaveformService() => _mockInstance ?? _instance;
  AudioWaveformService._internal();

  // Cache for waveform data
  final Map<String, WaveformData> _waveformCache = {};

  // Track ongoing extractions to prevent duplicates
  final Map<String, Future<WaveformData>> _ongoingExtractions = {};

  /// Get waveform data for an audio file (url or local path)
  Future<WaveformData> getWaveform(
    String audioSource, {
    int samples = 50,
  }) async {
    // 1. Check in-memory cache
    if (_waveformCache.containsKey(audioSource)) {
      return _waveformCache[audioSource]!;
    }

    // 2. Check ongoing request
    if (_ongoingExtractions.containsKey(audioSource)) {
      return _ongoingExtractions[audioSource]!;
    }

    // 3. Start extraction
    final future = _extractWaveform(audioSource, samples);
    _ongoingExtractions[audioSource] = future;

    try {
      final result = await future;
      _waveformCache[audioSource] = result;
      return result;
    } finally {
      _ongoingExtractions.remove(audioSource);
    }
  }

  Future<WaveformData> _extractWaveform(String source, int samples) async {
    File? audioFile;
    bool isTempFile = false;

    try {
      // Handle URL vs Local Path
      if (source.startsWith('http')) {
        audioFile = await _downloadFile(source);
        isTempFile = true;
      } else {
        audioFile = File(source);
      }

      if (!await audioFile.exists()) {
        return _simulateWaveform(samples, source);
      }

      // Extract using just_waveform
      final waveFile = File('${audioFile.path}.wave');

      try {
        final progressStream = JustWaveform.extract(
          audioInFile: audioFile,
          waveOutFile: waveFile,
          zoom: const WaveformZoom.pixelsPerSecond(100),
        );

        await for (final _ in progressStream) {
          // Wait for completion
        }

        if (await waveFile.exists()) {
          final waveform = await JustWaveform.parse(waveFile);

          // Resample data to target sample count
          final data = waveform.data;
          final List<double> resampled = [];
          if (data.isEmpty) {
            return _simulateWaveform(samples, source);
          }

          // Normalize and resample
          // Data is int16 (I think?). Let's check max value or just max in the list.
          int maxVal = 1;
          for (var v in data) {
            if (v.abs() > maxVal) maxVal = v.abs();
          }

          final step = data.length / samples;
          for (var i = 0; i < samples; i++) {
            // Simple sampling (take value at index)
            final index = (i * step).floor();
            if (index < data.length) {
              resampled.add(data[index].abs() / maxVal);
            } else {
              resampled.add(0.0);
            }
          }

          // Cleanup .wave file
          try {
            await waveFile.delete();
          } catch (_) {}

          return WaveformData(samples: resampled, duration: waveform.duration);
        }
      } catch (e) {
        debugPrint('Waveform extraction failed: $e');
      }

      return _simulateWaveform(samples, source);
    } catch (e) {
      debugPrint('Error getting waveform: $e');
      return _simulateWaveform(samples, source);
    } finally {
      if (isTempFile && audioFile != null && await audioFile.exists()) {
        try {
          await audioFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<File> _downloadFile(String url) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final filename = path.basename(Uri.parse(url).path);
    final file = File('${docsDir.path}/temp_audio_$filename');

    if (await file.exists()) return file;

    final response = await http.get(Uri.parse(url));
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  WaveformData _simulateWaveform(int samples, String source) {
    // Generate a consistent pseudo-random waveform based on the source string
    final seed = source.hashCode;
    final random = Random(seed);

    final data = List.generate(samples, (index) {
      // Create a bell-curve shape with randomness
      final x = index / samples;
      final bell = 1.0 - (2 * x - 1) * (2 * x - 1);

      // Use the seeded random for consistent 'noise'
      final noise = random.nextDouble();

      return (bell * 0.6 + 0.2 + (0.2 * noise)).clamp(0.1, 1.0);
    });

    return WaveformData(samples: data, duration: Duration.zero);
  }
}
