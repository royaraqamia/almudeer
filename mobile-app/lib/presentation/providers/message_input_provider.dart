import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/services/media_service.dart';
import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../core/services/media_cache_manager.dart'; // Added import
import 'conversation_detail_provider.dart';

/// Provider for managing message input state (Text, Recording, Attachments)
class MessageInputProvider extends ChangeNotifier {
  final InboxRepository _inboxRepository;

  // Input State
  final List<Map<String, dynamic>> _attachments = [];
  bool _isDisposed = false;

  MessageInputProvider({InboxRepository? inboxRepository})
    : _inboxRepository = inboxRepository ?? InboxRepository();

  List<Map<String, dynamic>> get attachments => _attachments;

  /// Send a message
  /// Requires [chatProvider] to update the UI optimistically
  Future<bool> sendMessage(
    ConversationDetailProvider chatProvider,
    String message, {
    List<File>? mediaFiles,
    Map<String, dynamic>? metadata,
    int? replyToMessageId,
    String? replyToPlatformId,
    String? replyToBodyPreview,

    String? replyToSenderName,
    List<Map<String, dynamic>>? customAttachments,
    void Function(double progress, int uploadedBytes, int totalBytes)?
    onUploadProgress,
  }) async {
    final senderContact = chatProvider.senderContact;
    if (senderContact == null) return false;

    // DEBUG: Log incoming message parameters
    debugPrint('[MessageInputProvider] sendMessage called:');
    debugPrint('  - message: "${message.isEmpty ? "(empty)" : message}"');
    debugPrint('  - mediaFiles: ${mediaFiles?.length ?? 0} files');
    if (mediaFiles != null) {
      for (var f in mediaFiles) {
        debugPrint('    - ${f.path}');
      }
    }
    debugPrint('  - metadata: $metadata');

    // 0. Calculate total bytes FIRST (before compression) for instant progress tracking
    int totalUploadBytes = 0;
    if (mediaFiles != null && mediaFiles.isNotEmpty) {
      for (final file in mediaFiles) {
        try {
          totalUploadBytes += await file.length();
        } catch (e) {
          debugPrint('[MessageInputProvider] Error getting file size: $e');
        }
      }
    }

    // 1. Show OPTIMISTIC message IMMEDIATELY (before compression) for instant UI feedback
    final optimisticMessage = InboxMessage.optimistic(
      body: message,
      channel: senderContact == '__saved_messages__'
          ? 'saved'
          : (chatProvider.activeChannel ??
                (chatProvider.messages.isNotEmpty
                    ? chatProvider.messages.first.channel
                    : 'whatsapp')),
      senderContact: senderContact,
      attachments: null, // Will be updated after compression
      replyToId: replyToMessageId,
      replyToPlatformId: replyToPlatformId,
      replyToBodyPreview: replyToBodyPreview,
      replyToSenderName: replyToSenderName,
      status: 'sent',
      sendStatus: MessageSendStatus.sending,
      isUploading: mediaFiles != null && mediaFiles.isNotEmpty,
      uploadProgress: mediaFiles != null && mediaFiles.isNotEmpty ? 0.05 : null,
      uploadedBytes: 0,
      totalUploadBytes: totalUploadBytes,
    );

    chatProvider.addOptimisticMessage(optimisticMessage);

    // 2. Compress media in background (after showing optimistic message)
    List<Map<String, dynamic>>? attachments;
    if (mediaFiles != null && mediaFiles.isNotEmpty) {
      attachments = [];
      final List<Future<Map<String, dynamic>?>> compressionTasks = mediaFiles
          .map((file) async {
            File? compressedFile;
            String type = 'document';

            final ext = p.extension(file.path).toLowerCase();
            if (['.jpg', '.jpeg', '.png'].contains(ext)) {
              compressedFile = await MediaService.compressImage(file);
              type = 'image';
            } else if (['.mp4', '.mov'].contains(ext)) {
              compressedFile = await MediaService.compressVideo(file);
              type = 'video';
            } else if ([
              '.aac',
              '.m4a',
              '.mp3',
              '.wav',
              '.ogg',
              '.flac',
              '.amr',
            ].contains(ext)) {
              if (metadata != null && metadata['is_voice_note'] == true) {
                type = 'voice';
                compressedFile = file;
              } else {
                type = 'audio';
                compressedFile = file;
              }
            } else {
              compressedFile = file;
            }

            if (compressedFile != null) {
              final Map<String, dynamic> attData = {
                'path': compressedFile.path,
                'type': type,
              };
              if (metadata != null) {
                attData.addAll(metadata);
              }
              return attData;
            }
            return null;
          })
          .toList();

      final List<Map<String, dynamic>?> results = await Future.wait(
        compressionTasks,
      );
      attachments = results.whereType<Map<String, dynamic>>().toList();

      // Update message with compressed attachments (background update)
      debugPrint(
        '[MessageInputProvider] Processed attachments: ${attachments.length}',
      );
      for (var att in attachments) {
        debugPrint('  - type: ${att['type']}, path: ${att['path']}');
      }

      // Update the optimistic message with actual attachments after compression
      chatProvider.updateMessageAttachments(optimisticMessage.id, attachments);
    }

    if (customAttachments != null) {
      attachments ??= [];
      attachments.addAll(customAttachments);
    }

    // DEBUG: Log final attachments before sending to repository
    debugPrint(
      '[MessageInputProvider] Final attachments count: ${attachments?.length ?? 0}',
    );

    try {
      // 2. API Call with progress callback (throttled to prevent excessive UI updates)
      DateTime lastProgressUpdate = DateTime.now();
      final response = await _inboxRepository.sendMessage(
        senderContact,
        message: message,
        channel: optimisticMessage.channel,
        attachments: attachments,
        replyToMessageId: replyToMessageId,
        replyToPlatformId: replyToPlatformId,
        replyToBodyPreview: replyToBodyPreview,
        replyToSenderName: replyToSenderName,
        onUploadProgress: (progress) {
          // Throttle progress updates to every 100ms to prevent UI lag
          final now = DateTime.now();
          if (now.difference(lastProgressUpdate).inMilliseconds < 100) {
            return; // Skip this update
          }
          lastProgressUpdate = now;

          if (onUploadProgress != null && totalUploadBytes > 0) {
            final uploadedBytes = (progress * totalUploadBytes).round();
            onUploadProgress(progress, uploadedBytes, totalUploadBytes);
          }
          // Update the optimistic message with upload progress
          chatProvider.updateMessageUploadProgress(
            optimisticMessage.id,
            progress,
            (progress * totalUploadBytes).round(),
            totalUploadBytes,
          );
        },
      );

      // 3. Confirm Send
      if (response['pending'] == true) {
        // Offline / Pending: Treat as Sent locally
        chatProvider.confirmMessageSent(
          optimisticMessage.id,
          optimisticMessage.id, // Keep temp ID until sync
          'sent',
        );
      } else {
        // Online: Update with Server ID
        final responseData = response['data'] ?? response;
        final int? newId = responseData['id'] is int
            ? responseData['id']
            : (responseData['outbox_id'] is int
                  ? responseData['outbox_id']
                  : null);
        // Extract outbox_id for status tracking
        final int? outboxId = responseData['outbox_id'] is int
            ? responseData['outbox_id']
            : null;

        if (newId != null) {
          chatProvider.confirmMessageSent(
            optimisticMessage.id,
            newId,
            'sent',
            outboxId: outboxId,
          );
        } else {
          chatProvider.confirmMessageSent(
            optimisticMessage.id,
            optimisticMessage.id,
            'sent',
          );
        }
      }

      // 4. Cache Locally (NEW)
      await _cacheSentAttachments(response, attachments ?? []);

      return true;
    } catch (e) {
      // 5. Fail Optimistic
      debugPrint('Message send failed: $e');
      chatProvider.markMessageFailed(optimisticMessage.id);
      return false;
    }
  }

  /// Send a text message without active chat provider (Background send)
  Future<bool> sendMessageInBackground(
    String senderContact,
    String channel,
    String message,
  ) async {
    try {
      await _inboxRepository.sendMessage(
        senderContact,
        message: message,
        channel: channel,
      );
      return true;
    } catch (e) {
      debugPrint('Background message send failed: $e');
      rethrow;
    }
  }

  /// Send a note as an attachment without active chat provider (Background send)
  Future<bool> sendNote(
    String senderContact,
    String channel, {
    required String title,
    required String content,
  }) async {
    try {
      final noteAttachment = {
        'type': 'note',
        'title': title,
        'content': content,
      };

      await _inboxRepository.sendMessage(
        senderContact,
        message: '', // Empty body, only attachment
        channel: channel,
        attachments: [noteAttachment],
      );

      return true;
    } catch (e) {
      debugPrint('Note send failed: $e');
      rethrow;
    }
  }

  /// Send a task as an attachment without active chat provider (Background send)
  Future<bool> sendTask(
    String senderContact,
    String channel, {
    required String title,
    String? description,
    bool? isCompleted,
    DateTime? dueDate,
  }) async {
    try {
      final taskAttachment = {
        'type': 'task',
        'title': title,
        'description': description,
        'is_completed': isCompleted,
        'due_date': dueDate?.toIso8601String(),
      };

      await _inboxRepository.sendMessage(
        senderContact,
        message: '', // Empty body
        channel: channel,
        attachments: [taskAttachment],
      );

      return true;
    } catch (e) {
      debugPrint('Task send failed: $e');
      rethrow;
    }
  }

  /// Send a file as an attachment without active chat provider (Background send)
  Future<bool> sendFile(
    String senderContact,
    String channel, {
    required String filePath,
    required String type,
    String? fileName,
  }) async {
    try {
      String finalPath = filePath;
      String finalType = type;

      // Compress if media
      try {
        final ext = p.extension(filePath).toLowerCase();
        if (['.jpg', '.jpeg', '.png'].contains(ext)) {
          final compressed = await MediaService.compressImage(File(filePath));
          if (compressed != null) {
            finalPath = compressed.path;
            finalType = 'image';
          }
        } else if (['.mp4', '.mov'].contains(ext)) {
          final compressed = await MediaService.compressVideo(File(filePath));
          if (compressed != null) {
            finalPath = compressed.path;
            finalType = 'video';
          }
        }
      } catch (e) {
        debugPrint('[MessageInputProvider] Compression error in sendFile: $e');
      }

      final fileAttachment = {
        'path': finalPath,
        'type': finalType,
        'name': fileName ?? p.basename(filePath),
      };

      final response = await _inboxRepository.sendMessage(
        senderContact,
        message: '', // Empty body
        channel: channel,
        attachments: [fileAttachment],
      );

      // Cache Locally
      await _cacheSentAttachments(response, [fileAttachment]);

      return true;
    } catch (e) {
      debugPrint('File send failed: $e');
      rethrow;
    }
  }

  /// Helper to cache sent attachments locally to avoid immediate redownload
  Future<void> _cacheSentAttachments(
    Map<String, dynamic> response,
    List<Map<String, dynamic>> sentAttachments,
  ) async {
    if (response['data'] != null && response['data']['attachments'] != null) {
      final List<dynamic> remoteAttachments = response['data']['attachments'];

      // We iterate through our local processed attachments to find the corresponding files
      // This relies on the order being preserved.
      if (sentAttachments.length == remoteAttachments.length) {
        for (int i = 0; i < sentAttachments.length; i++) {
          final localAtt = sentAttachments[i];
          final remoteAtt = remoteAttachments[i];

          if (localAtt.containsKey('path') && remoteAtt['url'] != null) {
            final localFile = File(localAtt['path']);
            final remoteUrl = remoteAtt['url'] as String;

            if (await localFile.exists()) {
              // Cache it manually. Use remote filename if available to ensure
              // consistency with how bubbles retrieve it (extension matching).
              final filename =
                  remoteAtt['filename'] as String? ??
                  remoteAtt['file_name'] as String? ??
                  remoteAtt['name'] as String? ??
                  localAtt['name'] as String?;

              MediaCacheManager()
                  .putFile(remoteUrl, localFile, filename: filename)
                  .ignore();
            }
          }
        }
      }
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Reset state for account switching
  void reset() {
    // Clear all attachments
    _attachments.clear();

    notifyListeners();
  }
}
