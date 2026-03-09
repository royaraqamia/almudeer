import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/services/persistent_cache_service.dart';

class IntegrationsRepository {
  final ApiClient _apiClient;
  final PersistentCacheService _cache = PersistentCacheService();

  IntegrationsRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Get connected accounts status (with offline caching)
  Future<Map<String, dynamic>> getAccountsStatus() async {
    final accountHash = await _apiClient.getAccountCacheHash();
    final cacheKey = '${accountHash}_accounts_status';
    try {
      final response = await _apiClient.get(Endpoints.integrationAccounts);
      // Cache response
      await _cache.put(
        PersistentCacheService.boxIntegrations,
        cacheKey,
        response,
      );
      return response;
    } catch (e) {
      // Try to load from cache
      final cached = await _cache.get<Map<String, dynamic>>(
        PersistentCacheService.boxIntegrations,
        cacheKey,
      );
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  /// Get Email configuration
  Future<Map<String, dynamic>> getEmailConfig() async {
    final response = await _apiClient.get(Endpoints.emailConfig);
    return response;
  }

  /// Get Telegram configuration
  Future<Map<String, dynamic>> getTelegramConfig() async {
    final response = await _apiClient.get(Endpoints.telegramConfig);
    return response;
  }

  /// Get WhatsApp configuration
  Future<Map<String, dynamic>> getWhatsappConfig() async {
    final response = await _apiClient.get(Endpoints.whatsappConfig);
    return response;
  }

  /// Save Telegram Bot configuration
  Future<Map<String, dynamic>> saveTelegramConfig(String token) async {
    final response = await _apiClient.post(
      Endpoints.telegramConfig,
      body: {'token': token, 'type': 'bot'},
    );
    return response;
  }

  /// Save WhatsApp configuration
  Future<Map<String, dynamic>> saveWhatsappConfig(
    String phoneNumberId,
    String accessToken,
  ) async {
    final response = await _apiClient.post(
      Endpoints.whatsappConfig,
      body: {'phone_number_id': phoneNumberId, 'access_token': accessToken},
    );
    return response;
  }

  /// Start Telegram Phone login (send code)
  Future<Map<String, dynamic>> startTelegramPhoneLogin(
    String phoneNumber,
  ) async {
    final response = await _apiClient.post(
      Endpoints.telegramPhoneStart,
      body: {'phone_number': phoneNumber},
    );
    return response;
  }

  /// Verify Telegram Phone code
  Future<Map<String, dynamic>> verifyTelegramPhoneCode(
    String phoneNumber,
    String code, {
    String? sessionId,
    String? password,
  }) async {
    final response = await _apiClient.post(
      Endpoints.telegramPhoneVerify,
      body: {
        'phone_number': phoneNumber,
        'code': code,
        'session_id': sessionId,
        'password': password,
      },
    );
    return response;
  }

  /// Update channel settings (e.g. notifications)
  Future<void> updateChannelSettings(
    String type,
    Map<String, dynamic> data,
  ) async {
    final endpoint = '${Endpoints.integrationAccounts}/$type';
    await _apiClient.patch(endpoint, body: data);
  }

  /// Disconnect a channel
  Future<void> disconnectChannel(String type) async {
    // Delete generic integration account by type
    final endpoint = '${Endpoints.integrationAccounts}/$type';
    await _apiClient.delete(endpoint);
  }

  /// Fetch Email OAuth URL from backend
  Future<String> fetchGmailAuthUrl() async {
    final response = await _apiClient.get(Endpoints.emailOAuthUrl);
    if (response['authorization_url'] != null) {
      return response['authorization_url'];
    }
    throw Exception('Failed to get authorization URL');
  }
}
