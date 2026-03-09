import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/services/persistent_cache_service.dart';
import '../models/knowledge_document.dart';

class KnowledgeRepository {
  final ApiClient _apiClient;
  final PersistentCacheService _cache = PersistentCacheService();

  KnowledgeRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Get knowledge base documents
  Future<List<KnowledgeDocument>> getKnowledgeDocuments() async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_documents';
    try {
      final response = await _apiClient.get(Endpoints.knowledgeDocuments);
      if (response['documents'] != null) {
        final docs = (response['documents'] as List)
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

  /// Add text document to knowledge base
  Future<void> addKnowledgeDocument(String text) async {
    await _apiClient.post(
      Endpoints.knowledgeDocuments,
      body: {
        'text': text,
        'metadata': {
          'source': 'mobile_app',
          'created_at': DateTime.now().toIso8601String(),
        },
      },
    );
    // Invalidate cache AFTER successful API call
    final accountHash = await _apiClient.getAccountCacheHash();
    await _cache.delete(
      PersistentCacheService.boxKnowledge,
      '${accountHash}_documents',
    );
  }

  /// Update text document in knowledge base
  Future<void> updateKnowledgeDocument(String documentId, String text) async {
    final numericId = int.tryParse(documentId) ?? documentId;
    await _apiClient.put(
      '/api/knowledge/documents/$numericId',
      body: {
        'text': text,
        'metadata': {
          'source': 'mobile_app',
          'created_at': DateTime.now().toIso8601String(),
        },
      },
    );
    // Invalidate cache AFTER successful API call
    final accountHash = await _apiClient.getAccountCacheHash();
    await _cache.delete(
      PersistentCacheService.boxKnowledge,
      '${accountHash}_documents',
    );
  }

  /// Upload file to knowledge base
  Future<void> uploadKnowledgeFile(
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    await _apiClient.uploadFile(
      Endpoints.knowledgeUpload,
      filePath: filePath,
      fieldName: 'file',
      onProgress: onProgress,
    );
    // Invalidate cache AFTER successful API call
    final accountHash = await _apiClient.getAccountCacheHash();
    await _cache.delete(
      PersistentCacheService.boxKnowledge,
      '${accountHash}_documents',
    );
  }

  /// Delete a knowledge document
  Future<void> deleteKnowledgeDocument(String documentId) async {
    // Backend expects int in path, but returns string in response
    // Try to parse the string ID as int for the delete call
    final numericId = int.tryParse(documentId) ?? documentId;
    await _apiClient.delete('/api/knowledge/documents/$numericId');
    // Invalidate cache AFTER successful API call
    final accountHash = await _apiClient.getAccountCacheHash();
    await _cache.delete(
      PersistentCacheService.boxKnowledge,
      '${accountHash}_documents',
    );
  }
}
