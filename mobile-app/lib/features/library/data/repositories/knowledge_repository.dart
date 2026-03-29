import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:almudeer_mobile_app/core/api/api_client.dart';
import 'package:almudeer_mobile_app/core/api/endpoints.dart';
import 'package:almudeer_mobile_app/core/services/persistent_cache_service.dart';
import '../models/knowledge_document.dart';
import '../models/knowledge_constants.dart';

class KnowledgeRepository {
  final ApiClient _apiClient;
  final PersistentCacheService _cache = PersistentCacheService();

  KnowledgeRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Issue #7: Get knowledge base documents with specific cache key prefix
  Future<List<KnowledgeDocument>> getKnowledgeDocuments() async {
    final accountHash = await _apiClient.getAccountCacheHash();
    // Issue #7: Use specific cache key to prevent collisions
    final cacheKey = '${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents';

    try {
      final response = await _apiClient.get(Endpoints.knowledgeDocuments);
      // Backend returns {success: true, data: {documents: [...]}}
      final data = response['data'] as Map<String, dynamic>? ?? response;
      if (data['documents'] != null) {
        final docs = (data['documents'] as List)
            .map((doc) => KnowledgeDocument.fromJson(doc))
            .toList();

        // Cache the raw response data
        await _cache.put(
          PersistentCacheService.boxKnowledge,
          cacheKey,
          response,
        );
        return docs;
      }
      return [];
    } catch (e) {
      final cached = await _cache.get<Map<String, dynamic>>(
        PersistentCacheService.boxKnowledge,
        cacheKey,
      );
      if (cached != null && cached['documents'] != null) {
        return (cached['documents'] as List)
            .map((doc) => KnowledgeDocument.fromJson(doc))
            .toList();
      }
      rethrow;
    }
  }

  /// Invalidate cache with retry mechanism
  /// Issue #5: Non-blocking cache invalidation to prevent race conditions
  Future<void> _invalidateCacheWithRetry(String cacheKey, {int maxRetries = 3}) async {
    // Issue #5: Fire-and-forget cache invalidation
    // We don't await this to avoid blocking the main operation
    // The invalidation will complete in the background
    unawaited(_executeCacheInvalidation(cacheKey, maxRetries));
  }

  /// Execute cache invalidation with retry logic
  Future<void> _executeCacheInvalidation(String cacheKey, int maxRetries) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        await _cache.delete(PersistentCacheService.boxKnowledge, cacheKey);
        return; // Success
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          // Log but don't throw - cache invalidation failure is not critical
          debugPrint('[KnowledgeRepository] Cache invalidation failed after $maxRetries attempts: $e');
        } else {
          // Wait before retry with exponential backoff
          await Future.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    }
  }

  /// Add text document to knowledge base
  /// Issue #6: Added input validation
  Future<void> addKnowledgeDocument(String text) async {
    // Issue #6: Validate input
    if (text.trim().isEmpty) {
      throw ArgumentError('ط§ظ„ظ†طµ ظ„ط§ ظٹظ…ظƒظ† ط£ظ† ظٹظƒظˆظ† ظپط§ط±ط؛ط§ظ‹');
    }
    
    // Note: Backend also validates max length, but we validate here for better UX
    if (text.length > KnowledgeBaseConstants.maxTextLength) {
      throw ArgumentError('ط§ظ„ظ†طµ ط·ظˆظٹظ„ ط¬ط¯ط§ظ‹ (ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ${KnowledgeBaseConstants.maxTextLength} ط­ط±ظپ)');
    }
    
    await _apiClient.post(
      Endpoints.knowledgeDocuments,
      body: {
        'text': text,
        'metadata': {
          'source': KnowledgeSource.mobileApp.value,
          'created_at': DateTime.now().toIso8601String(),
        },
      },
    );
    // Invalidate cache AFTER successful API call with retry
    final accountHash = await _apiClient.getAccountCacheHash();
    await _invalidateCacheWithRetry('${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents');
  }

  /// Update text document in knowledge base
  /// Issue #6: Added input validation
  Future<void> updateKnowledgeDocument(String documentId, String text) async {
    // Issue #6: Validate input
    if (text.trim().isEmpty) {
      throw ArgumentError('ط§ظ„ظ†طµ ظ„ط§ ظٹظ…ظƒظ† ط£ظ† ظٹظƒظˆظ† ظپط§ط±ط؛ط§ظ‹');
    }
    
    if (text.length > KnowledgeBaseConstants.maxTextLength) {
      throw ArgumentError('ط§ظ„ظ†طµ ط·ظˆظٹظ„ ط¬ط¯ط§ظ‹ (ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ${KnowledgeBaseConstants.maxTextLength} ط­ط±ظپ)');
    }
    
    final numericId = int.tryParse(documentId) ?? documentId;
    await _apiClient.put(
      '/api/knowledge/documents/$numericId',
      body: {
        'text': text,
        'metadata': {
          'source': KnowledgeSource.mobileApp.value,
          'created_at': DateTime.now().toIso8601String(),
        },
      },
    );
    // Invalidate cache AFTER successful API call with retry
    final accountHash = await _apiClient.getAccountCacheHash();
    await _invalidateCacheWithRetry('${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents');
  }

  /// Upload file to knowledge base
  /// Issue #9: Added auto-retry for transient failures
  /// Issue #4: Added file extension validation before upload
  Future<void> uploadKnowledgeFile(
    String filePath, {
    void Function(double progress)? onProgress,
    int maxRetries = 2,
  }) async {
    // Issue #4: Validate file extension before upload for better UX
    final fileExtension = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
    if (!KnowledgeBaseConstants.allowedFileExtensions.contains(fileExtension)) {
      throw ArgumentError(
        'ظ†ظˆط¹ ط§ظ„ظ…ظ„ظپ ط؛ظٹط± ظ…ط¯ط¹ظˆظ…. ط§ظ„ط£ظ†ظˆط§ط¹ ط§ظ„ظ…ط¯ط¹ظˆظ…ط©: ${KnowledgeBaseConstants.allowedFileExtensions.join(', ')}'
      );
    }

    int attempt = 0;
    Exception? lastException;

    while (attempt <= maxRetries) {
      try {
        await _apiClient.uploadFile(
          Endpoints.knowledgeUpload,
          filePath: filePath,
          fieldName: 'file',
          onProgress: onProgress,
        );
        // Invalidate cache AFTER successful API call with retry
        final accountHash = await _apiClient.getAccountCacheHash();
        await _invalidateCacheWithRetry('${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents');
        return; // Success
      } catch (e) {
        lastException = e as Exception;
        attempt++;

        // Don't retry on last attempt
        if (attempt > maxRetries) {
          debugPrint('[KnowledgeRepository] Upload failed after $maxRetries retries: $e');
          throw lastException;
        }

        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  /// Delete a knowledge document
  Future<void> deleteKnowledgeDocument(String documentId) async {
    // Backend expects int in path, but returns string in response
    // Try to parse the string ID as int for the delete call
    final numericId = int.tryParse(documentId) ?? documentId;
    await _apiClient.delete('/api/knowledge/documents/$numericId');
    // Invalidate cache AFTER successful API call with retry
    final accountHash = await _apiClient.getAccountCacheHash();
    await _invalidateCacheWithRetry('${KnowledgeBaseConstants.cacheKeyPrefix}${accountHash}_documents');
  }
}
