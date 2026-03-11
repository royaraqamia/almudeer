import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../../data/models/library_item.dart';

import '../../../core/services/notification_navigator.dart';
import '../../presentation/screens/chat_selection_screen.dart';
import '../../presentation/screens/viewers/universal_viewer_screen.dart';
import '../../../data/models/conversation.dart';
import '../../presentation/providers/message_input_provider.dart';
import '../extensions/string_extension.dart';
import 'package:path/path.dart' as p;
import '../../../core/utils/haptics.dart';
import '../../../core/constants/colors.dart';
import '../../presentation/widgets/premium_bottom_sheet.dart';
import '../../presentation/widgets/animated_toast.dart';
import '../../presentation/widgets/custom_dialog.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'media_cache_manager.dart';

/// Service to handle files and text shared from other apps to Almudeer
class SharingService {
  static final SharingService _instance = SharingService._internal();
  factory SharingService() => _instance;
  SharingService._internal();

  /// Share a file to other apps using system share sheet
  Future<void> shareFile(String path, {String? title, String? mimeType}) async {
    try {
      final xFile = XFile(path, mimeType: mimeType);
      await SharePlus.instance.share(
        ShareParams(files: [xFile], subject: title),
      );
    } catch (e) {
      debugPrint('Error sharing file: $e');
    }
  }

  /// Forward library items to Almudeer chats
  ///
  /// P3-14 FIX: Properly handles file downloads, error handling, and progress indication
  Future<void> forwardItems(
    BuildContext context,
    List<LibraryItem> items, {
    List<String>? excludeChannels,
  }) async {
    // Navigate to ChatSelectionScreen to choose destination
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatSelectionScreen(
          allowBulkSelection: true,
          excludeChannels: excludeChannels,
        ),
      ),
    );

    if (result != null && context.mounted) {
      final List<Conversation> selectedChats = (result is List)
          ? List<Conversation>.from(result)
          : [result as Conversation];

      // Validate chats have senderContact
      final validChats = selectedChats
          .where(
            (chat) =>
                chat.senderContact != null && chat.senderContact!.isNotEmpty,
          )
          .toList();

      if (validChats.isEmpty) {
        if (context.mounted) {
          AnimatedToast.error(
            context,
            'لا يمكن الإرسال: لا توجد محادثات صالحة',
          );
        }
        return;
      }

      final inputProvider = context.read<MessageInputProvider>();

      // Show loading indicator
      if (context.mounted) {
        CustomDialog.show(
          context,
          title: 'جاري الإرسال...',
          message: 'جاري تحضير ${items.length} عنصر للإرسال',
          type: DialogType.info,
          isLoading: true,
          barrierDismissible: false,
        );
      }

      try {
        // Prepare all items first (download files)
        final preparedItems = <_PreparedLibraryItem>[];

        for (final item in items) {
          if (item.type == 'note') {
            // Notes don't need download
            preparedItems.add(_PreparedLibraryItem(item: item, success: true));
          } else if (item.filePath != null) {
            // Download file if not cached
            try {
              final fullUrl = item.filePath!.toFullUrl;
              String? localPath = await MediaCacheManager().getLocalPath(
                fullUrl,
                filename: item.title,
              );

              // If not cached, download now
              if (localPath == null || !await File(localPath).exists()) {
                localPath = await MediaCacheManager().downloadFile(
                  fullUrl,
                  filename: item.title,
                );
              }

              // Verify file exists after download
              if (await File(localPath).exists()) {
                preparedItems.add(
                  _PreparedLibraryItem(
                    item: item,
                    localPath: localPath,
                    success: true,
                  ),
                );
              } else {
                preparedItems.add(
                  _PreparedLibraryItem(
                    item: item,
                    success: false,
                    error: 'فشل تحميل الملف',
                  ),
                );
              }
            } catch (e) {
              debugPrint('Failed to prepare library item ${item.title}: $e');
              preparedItems.add(
                _PreparedLibraryItem(
                  item: item,
                  success: false,
                  error: 'خطأ في التحميل: ${e.toString()}',
                ),
              );
            }
          }
        }

        // Close loading dialog
        if (context.mounted) {
          Navigator.pop(context);
        }

        // Check if any items failed to prepare
        final failedCount = preparedItems.where((p) => !p.success).length;
        if (failedCount > 0 && context.mounted) {
          AnimatedToast.error(
            context,
            'فشل تحضير $failedCount من ${preparedItems.length} عنصر',
          );
        }

        // Send all prepared items in parallel
        final sendFutures = <Future<void>>[];

        for (final prepared in preparedItems) {
          if (!prepared.success) continue;

          for (final chat in validChats) {
            if (prepared.item.type == 'note') {
              // Send note as structured attachment
              sendFutures.add(
                inputProvider
                    .sendNote(
                      chat.senderContact!,
                      chat.channel,
                      title: prepared.item.title,
                      content: prepared.item.content ?? '',
                    )
                    .catchError((e) {
                      debugPrint(
                        'Failed to send note ${prepared.item.title}: $e',
                      );
                      return false;
                    }),
              );
            } else if (prepared.localPath != null) {
              // Send file
              sendFutures.add(
                inputProvider
                    .sendFile(
                      chat.senderContact!,
                      chat.channel,
                      filePath: prepared.localPath!,
                      type: _getItemType(prepared.item),
                      fileName: prepared.item.title,
                    )
                    .catchError((e) {
                      debugPrint(
                        'Failed to send file ${prepared.item.title}: $e',
                      );
                      return false;
                    }),
              );
            }
          }
        }

        // Execute all sends in parallel
        if (sendFutures.isNotEmpty) {
          await Future.wait(sendFutures);

          if (context.mounted) {
            AnimatedToast.success(
              context,
              'تم إرسال ${preparedItems.length} عنصر إلى ${validChats.length} محادثة',
            );
          }
        } else if (context.mounted) {
          AnimatedToast.error(context, 'لا توجد عناصر صالحة للإرسال');
        }
      } catch (e) {
        // Close loading dialog if still open
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
          AnimatedToast.error(context, 'فشل الإرسال: ${e.toString()}');
        }
      }
    }
  }

  /// Helper to determine item type for sending
  String _getItemType(LibraryItem item) {
    if (item.type == 'image' || item.type == 'video' || item.type == 'audio') {
      return item.type;
    }
    return 'file';
  }

  static const _channel = MethodChannel(
    'com.royaraqamia.almudeer/intent_action',
  );
  StreamSubscription? _intentDataStreamSubscription;

  void initialize() {
    // For sharing coming from outside the app while the app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            _handleIncomingSharedContent(media: value);
          },
          onError: (err) {
            debugPrint('SharingService: getMediaStream error: $err');
            return;
          },
        );

    // For sharing coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _handleIncomingSharedContent(media: value);
      }
    });
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  /// Navigates to chat selection screen or viewer based on share type
  void _handleIncomingSharedContent({List<SharedMediaFile>? media}) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('SharingService: Navigator not ready, retrying in 500ms...');
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _handleIncomingSharedContent(media: media),
      );
      return;
    }

    if (media == null || media.isEmpty) return;

    // Get the actual native intent action to distinguish "Open with" vs "Share"
    String? intentAction;
    try {
      intentAction = await _channel.invokeMethod<String>('getIntentAction');
      debugPrint('SharingService: Native Intent Action: $intentAction');
    } catch (e) {
      debugPrint('SharingService: Error querying intent action: $e');
    }

    // Direct View Flow: If "Open with" (ACTION_VIEW), open viewer or browser directly
    if (intentAction == 'android.intent.action.VIEW' && media.length == 1) {
      final item = media.first;

      // Handle URL intents (Native Browser behavior)
      if (item.type == SharedMediaType.url) {
        navigator.pushNamedAndRemoveUntil(
          '/browser',
          (route) => route.isFirst,
          arguments: {'initialUrl': item.path},
        );
        return;
      }

      // Handle File intents
      if (item.type != SharedMediaType.text) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => UniversalViewerScreen(
              filePath: item.path,
              fileName: item.path.split('/').last,
              fileType: _mapItemType(item),
            ),
          ),
        );
        return;
      }
    }

    // Forward/Share Flow: If "Share" (ACTION_SEND) or multiple files, go to chat selection
    final result = await navigator.push(
      MaterialPageRoute(
        builder: (context) =>
            const ChatSelectionScreen(allowBulkSelection: true),
      ),
    );

    if (result != null && result is List<Conversation> && navigator.mounted) {
      final inputProvider = navigator.context.read<MessageInputProvider>();

      final List<Future> sendTasks = [];
      for (final conversation in result) {
        final senderContact = conversation.senderContact;
        if (senderContact == null) continue;

        // Handle items from media stream (files, text, or urls)
        for (final item in media) {
          if (item.type == SharedMediaType.text ||
              item.type == SharedMediaType.url) {
            sendTasks.add(
              inputProvider.sendMessageInBackground(
                senderContact,
                conversation.channel,
                item.path,
              ),
            );
          } else {
            sendTasks.add(
              inputProvider.sendFile(
                senderContact,
                conversation.channel,
                filePath: item.path,
                type: _mapItemType(item),
                fileName: item.path.split('/').last,
              ),
            );
          }
        }
      }

      // Execute all sends in parallel without blocking the UI thread sequentially
      if (sendTasks.isNotEmpty) {
        debugPrint(
          'SharingService: Sending ${sendTasks.length} items in parallel...',
        );
        Future.wait(sendTasks).catchError((e) {
          debugPrint('SharingService: Error during parallel send: $e');
          return [];
        });
      }
    }
  }

  String _mapItemType(SharedMediaFile item) {
    if (item.type == SharedMediaType.image) return 'image';
    if (item.type == SharedMediaType.video) return 'video';

    // If it's a file, check mime type and extension for audio specialized viewer
    final mime = item.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('audio/')) {
      return 'audio';
    }

    final path = item.path.toLowerCase();
    if (path.endsWith('.mp3') ||
        path.endsWith('.wav') ||
        path.endsWith('.aac') ||
        path.endsWith('.m4a') ||
        path.endsWith('.flac') ||
        path.endsWith('.ogg') ||
        path.endsWith('.wma')) {
      return 'audio';
    }

    return 'file';
  }

  /// Shows a menu to either forward a file to an Almudeer chat or share it with other apps.
  Future<void> showShareMenu(
    BuildContext context, {
    required String filePath,
    String? title,
    String? type,
  }) async {
    Haptics.selection();
    final name = title ?? p.basename(filePath);

    await PremiumBottomSheet.show(
      context: context,
      title: name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(
              SolarLinearIcons.plain3,
              color: AppColors.primary,
            ),
            title: const Text(
              'تحويل إلى محادثة',
              style: TextStyle(fontFamily: 'IBM Plex Sans Arabic'),
            ),
            onTap: () {
              Navigator.pop(context);
              // Construct a temporary LibraryItem for forwardItems
              final item = LibraryItem(
                id: -1,
                licenseKeyId: 0,
                title: name,
                type: type ?? 'file',
                filePath: filePath,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              forwardItems(context, [item]);
            },
          ),
          ListTile(
            leading: const Icon(
              SolarLinearIcons.share,
              color: AppColors.primary,
            ),
            title: const Text(
              'مشاركة عبر تطبيقات أخرى',
              style: TextStyle(fontFamily: 'IBM Plex Sans Arabic'),
            ),
            onTap: () {
              Navigator.pop(context);
              shareFile(filePath, title: name);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Helper class to store prepared library item data
class _PreparedLibraryItem {
  final LibraryItem item;
  final String? localPath;
  final bool success;
  final String? error;

  _PreparedLibraryItem({
    required this.item,
    this.localPath,
    this.success = true,
    this.error,
  });
}
