import 'package:flutter/foundation.dart';
import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';

class LinkPreview {
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  LinkPreview({this.title, this.description, this.image, this.siteName});

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      title: json['title'] as String?,
      description: json['description'] as String?,
      image: json['image'] as String?,
      siteName: json['site_name'] as String?,
    );
  }
}

class ScraperResult {
  final bool success;
  final String? title;
  final String? content;
  final int? fileId;
  final String? error;

  ScraperResult({
    required this.success,
    this.title,
    this.content,
    this.fileId,
    this.error,
  });

  factory ScraperResult.fromJson(Map<String, dynamic> json) {
    return ScraperResult(
      success: json['success'] as bool? ?? false,
      title: json['title'] as String?,
      content: json['content'] as String?,
      fileId: json['file_id'] as int?,
      error: json['error'] as String?,
    );
  }
}

class BrowserScraperService {
  static final BrowserScraperService _instance =
      BrowserScraperService._internal();
  factory BrowserScraperService() => _instance;
  BrowserScraperService._internal();

  final ApiClient _apiClient = ApiClient();
  final Map<String, LinkPreview> _previewCache = {};

  Future<ScraperResult> scrapeAndSave(
    String url, {
    String format = 'markdown',
    bool includeImages = true,
  }) async {
    try {
      final response = await _apiClient.post(
        Endpoints.browserScrape,
        body: {'url': url, 'format': format, 'include_images': includeImages},
      );

      return ScraperResult.fromJson(response);
    } catch (e) {
      debugPrint('[BrowserScraper] Error scraping $url: $e');
      return ScraperResult(success: false, error: e.toString());
    }
  }

  Future<LinkPreview?> getPreview(String url) async {
    if (_previewCache.containsKey(url)) {
      return _previewCache[url];
    }

    try {
      final response = await _apiClient.post(
        Endpoints.browserPreview,
        body: {'url': url},
        requiresAuth: false,
      );

      final preview = LinkPreview.fromJson(response);
      _previewCache[url] = preview;
      return preview;
    } catch (e) {
      debugPrint('[BrowserScraper] Error getting preview for $url: $e');
      return null;
    }
  }

  void clearCache() {
    _previewCache.clear();
  }
}
