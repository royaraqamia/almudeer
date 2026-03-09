import 'package:flutter/material.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/core/models/download_task.dart';
import 'package:almudeer_mobile_app/core/services/browser_download_manager.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import 'package:almudeer_mobile_app/presentation/widgets/custom_dialog.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = BrowserDownloadManager();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'التحميلات',
          style: TextStyle(
            fontFamily: 'IBM Plex Sans Arabic',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(SolarLinearIcons.trashBin),
            onPressed: () => _clearCompleted(context, manager),
          ),
        ],
      ),
      body: StreamBuilder<List<DownloadTask>>(
        initialData: manager.currentTasks,
        stream: manager.tasksStream,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    SolarLinearIcons.download,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا يوجد تحميلات حالياً',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _DownloadItem(task: task);
            },
          );
        },
      ),
    );
  }

  void _clearCompleted(BuildContext context, BrowserDownloadManager manager) {
    CustomDialog.show(
      context,
      title: 'حذف المكتملة',
      message: 'هل تريد حذف جميع التحميلات المكتملة؟',
      type: DialogType.warning,
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      onConfirm: () {
        for (var task in manager.currentTasks) {
          if (task.status == DownloadStatus.completed) {
            manager.cancelDownload(task.id);
          }
        }
      },
    );
  }
}

class _DownloadItem extends StatefulWidget {
  final DownloadTask task;

  const _DownloadItem({required this.task});

  @override
  State<_DownloadItem> createState() => _DownloadItemState();
}

class _DownloadItemState extends State<_DownloadItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final manager = BrowserDownloadManager();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Circular Progress Indicator
              _buildCircularProgress(widget.task),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.task.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatBytes(widget.task.currentSize)} / ${_formatBytes(widget.task.totalSize)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                    if (widget.task.status == DownloadStatus.downloading) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${(widget.task.networkSpeed / 1024).toStringAsFixed(1)} KB/s',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.task.timeRemaining != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'المتبقي: ${_formatDuration(widget.task.timeRemaining!)}',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _buildActions(context, manager),
            ],
          ),
          const SizedBox(height: 12),
          // Linear progress bar (secondary visual)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.task.progress,
              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
              color: _getStatusColor(widget.task.status),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getStatusText(widget.task.status),
                style: TextStyle(
                  color: _getStatusColor(widget.task.status),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                DateFormat('yyyy/MM/dd HH:mm').format(widget.task.timestamp),
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularProgress(DownloadTask task) {
    final percentage = (task.progress * 100).toStringAsFixed(0);
    final isComplete = task.status == DownloadStatus.completed;
    
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: task.progress,
              strokeWidth: 3,
              color: _getStatusColor(task.status),
              backgroundColor: Colors.grey[300],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isComplete)
                const Icon(
                  SolarBoldIcons.checkCircle,
                  color: Colors.green,
                  size: 20,
                )
              else
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(task.status),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, BrowserDownloadManager manager) {
    if (widget.task.status == DownloadStatus.downloading) {
      return IconButton(
        icon: const Icon(
          SolarLinearIcons.pause,
          size: 20,
          color: Colors.orange,
        ),
        onPressed: () => manager.pauseDownload(widget.task.id),
      );
    } else if (widget.task.status == DownloadStatus.paused ||
        widget.task.status == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(
          SolarLinearIcons.play,
          size: 20,
          color: AppColors.primary,
        ),
        onPressed: () => manager.resumeDownload(widget.task.id),
      );
    } else if (widget.task.status == DownloadStatus.completed) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(
              SolarLinearIcons.eye,
              size: 20,
              color: Colors.green,
            ),
            onPressed: () {
              // Open file with system handler (APK files will use native Android installer)
              OpenFilex.open(widget.task.savedPath);
            },
          ),
          IconButton(
            icon: const Icon(
              SolarLinearIcons.trashBinMinimalistic,
              size: 20,
              color: Colors.red,
            ),
            onPressed: () => manager.cancelDownload(widget.task.id),
          ),
        ],
      );
    }
    return IconButton(
      icon: const Icon(
        SolarLinearIcons.closeCircle,
        size: 20,
        color: Colors.grey,
      ),
      onPressed: () => manager.cancelDownload(widget.task.id),
    );
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return AppColors.primary;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.paused:
        return Colors.orange;
      case DownloadStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return 'جاري التحميل...';
      case DownloadStatus.completed:
        return 'تم التحميل';
      case DownloadStatus.paused:
        return 'متوقف مؤقتاً';
      case DownloadStatus.failed:
        return 'فشل التحميل';
      default:
        return 'ملغى';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double dBytes = bytes.toDouble();
    int iSafety = 0;
    while (dBytes >= 1024 && iSafety < suffixes.length - 1) {
      dBytes /= 1024;
      iSafety++;
    }
    return '${dBytes.toStringAsFixed(iSafety == 0 ? 0 : 1)} ${suffixes[iSafety]}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} ساعة ${d.inMinutes.remainder(60)} دقيقة';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes} دقيقة';
    } else {
      return '${d.inSeconds} ثانية';
    }
  }
}
