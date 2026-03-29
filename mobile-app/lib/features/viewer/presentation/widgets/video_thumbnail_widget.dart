import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';

class VideoThumbnailWidget extends StatelessWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const VideoThumbnailWidget({
    super.key,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      // ignore: discarded_futures
      future: VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400, // Higher res for sharing
        quality: 75,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
          );
        }

        return Container(
          width: width,
          height: height,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black26
              : Colors.grey[200],
          child: const Center(
            child: Icon(
              SolarLinearIcons.videocamera,
              color: Colors.grey,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
