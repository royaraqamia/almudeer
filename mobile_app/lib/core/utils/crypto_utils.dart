import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Cryptographic utility functions for the app
/// 
/// Centralized crypto operations to avoid duplication:
/// - SHA256 verification
/// - Hash generation
class CryptoUtils {
  CryptoUtils._(); // Private constructor - utility class

  /// Verify SHA256 hash of a file against expected hash
  /// 
  /// Uses chunked reading for memory efficiency with large files.
  /// 
  /// Args:
  ///   - filePath: Path to the file to verify
  ///   - expectedHash: Expected SHA256 hash (case-insensitive)
  /// 
  /// Returns:
  ///   - true if hash matches, false otherwise
  static Future<bool> verifySha256(String filePath, String expectedHash) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      var output = sha256.convert([]);
      final sink = sha256.startChunkedConversion(
        ChunkedConversionSink.withCallback((chunks) {
          output = chunks.single;
        }),
      );

      // Read file in chunks to avoid loading entire file into memory
      final stream = file.openRead();
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      sink.close();

      // Case-insensitive comparison
      return output.toString().toLowerCase() == expectedHash.toLowerCase();
    } catch (e) {
      return false;
    }
  }

  /// Calculate SHA256 hash of a file
  /// 
  /// Uses chunked reading for memory efficiency.
  /// 
  /// Args:
  ///   - filePath: Path to the file to hash
  /// 
  /// Returns:
  ///   - SHA256 hash as hex string, or null on error
  static Future<String?> calculateSha256(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      var output = sha256.convert([]);
      final sink = sha256.startChunkedConversion(
        ChunkedConversionSink.withCallback((chunks) {
          output = chunks.single;
        }),
      );

      final stream = file.openRead();
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      sink.close();

      return output.toString();
    } catch (e) {
      return null;
    }
  }

  /// Calculate SHA256 hash of a string
  /// 
  /// Args:
  ///   - input: String to hash
  /// 
  /// Returns:
  ///   - SHA256 hash as hex string
  static String sha256String(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate a hash value 0-99 from an identifier for rollout distribution
  /// 
  /// Uses SHA256 for consistent distribution across platforms/sessions.
  /// Matches backend implementation for rollout percentage checks.
  /// 
  /// Args:
  ///   - identifier: Unique identifier (device ID, license key, etc.)
  /// 
  /// Returns:
  ///   - Integer 0-99 for rollout distribution
  static int getRolloutHash(String identifier) {
    final bytes = utf8.encode(identifier);
    final digest = sha256.convert(bytes);
    // Take first 8 hex chars and convert to int
    final hash = int.parse(digest.toString().substring(0, 8), radix: 16) % 100;
    return hash;
  }

  /// Check if identifier is in rollout percentage
  /// 
  /// Args:
  ///   - identifier: Unique identifier
  ///   - percentage: Rollout percentage (0-100)
  /// 
  /// Returns:
  ///   - true if included in rollout
  static bool isInRollout(String identifier, int percentage) {
    if (percentage >= 100) return true;
    if (percentage <= 0) return false;
    return getRolloutHash(identifier) < percentage;
  }
}
