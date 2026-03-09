import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/services/persistent_cache_service.dart';

class SubscriptionsRepository {
  final ApiClient _apiClient;
  final PersistentCacheService _cache = PersistentCacheService();

  SubscriptionsRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Create a new subscription
  Future<Map<String, dynamic>> createSubscription(
    Map<String, dynamic> data,
  ) async {
    final response = await _apiClient.post(
      Endpoints.subscriptionCreate,
      body: data,
    );
    // Invalidate list cache for current account
    final hash = await _apiClient.getAccountCacheHash();
    await _cache.deleteByPrefix(PersistentCacheService.boxSubscriptions, hash);
    return response;
  }

  /// List subscriptions
  Future<Map<String, dynamic>> getSubscriptions({
    bool activeOnly = false,
    int limit = 100,
  }) async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_list_${activeOnly}_$limit';
    try {
      final response = await _apiClient.get(
        Endpoints.subscriptionList,
        queryParams: {
          'active_only': activeOnly.toString(),
          'limit': limit.toString(),
        },
      );
      await _cache.put(
        PersistentCacheService.boxSubscriptions,
        cacheKey,
        response,
      );
      return response;
    } catch (e) {
      final cached = await _cache.get<Map<String, dynamic>>(
        PersistentCacheService.boxSubscriptions,
        cacheKey,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Get subscription details
  Future<Map<String, dynamic>> getSubscription(int id) async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_detail_$id';
    try {
      final response = await _apiClient.get(Endpoints.subscriptionDetail(id));
      await _cache.put(
        PersistentCacheService.boxSubscriptions,
        cacheKey,
        response,
      );
      return response;
    } catch (e) {
      final cached = await _cache.get<Map<String, dynamic>>(
        PersistentCacheService.boxSubscriptions,
        cacheKey,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Update subscription
  Future<Map<String, dynamic>> updateSubscription(
    int id,
    Map<String, dynamic> data,
  ) async {
    final response = await _apiClient.patch(
      Endpoints.subscriptionDetail(id),
      body: data,
    );
    // Invalidate specific cache and lists for current account
    final accountHash = await _apiClient.getAccountCacheHash();
    await _cache.deleteByPrefix(
      PersistentCacheService.boxSubscriptions,
      accountHash,
    );
    return response;
  }
}
