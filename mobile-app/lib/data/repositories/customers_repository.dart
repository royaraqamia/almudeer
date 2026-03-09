import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/services/connectivity_service.dart';
import '../datasources/local/customers_local_datasource.dart';
import '../repositories/auth_repository.dart';

class CustomersRepository {
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;
  final CustomersLocalDataSource _localDataSource;
  bool _isRefreshing = false;
  DateTime? _lastPurgeTime; // Throttle DB cleanup

  // Add a StreamController to notify when sync completes
  final _syncController = StreamController<void>.broadcast();
  Stream<void> get syncStream => _syncController.stream;

  CustomersRepository({
    ApiClient? apiClient,
    ConnectivityService? connectivityService,
    CustomersLocalDataSource? localDataSource,
  }) : _apiClient = apiClient ?? ApiClient(),
       _connectivityService = connectivityService ?? ConnectivityService(),
       _localDataSource = localDataSource ?? CustomersLocalDataSource();

  // Getters for internal use if needed
  ApiClient get apiClient => _apiClient;
  CustomersLocalDataSource get localDataSource => _localDataSource;

  /// Get customers list (Local First)
  Future<Map<String, dynamic>> getCustomers({
    int page = 1,
    int pageSize = 20,
    String? search,
    bool triggerSync = true,
  }) async {
    // 1. Return Local Data Immediately (Optimistic)
    final localCustomers = await _localDataSource.getCustomers(
      search: search,
      limit: pageSize,
      offset: (page - 1) * pageSize,
    );

    // 2. Trigger Background Sync if Online (and first page)
    if (triggerSync && _connectivityService.isOnline && page == 1) {
      // Fire and forget sync (handled by SyncService usually, but we can do a targeted fetch)
      _refreshCustomersFromServer(page, pageSize, search);
    }

    // 3. IF we need pagination but local cache is empty, fetch synchronously
    if (localCustomers.isEmpty &&
        page > 1 &&
        triggerSync &&
        _connectivityService.isOnline) {
      await _refreshCustomersFromServer(page, pageSize, search);

      // Re-fetch from local DB after the sync finishes
      final reFetched = await _localDataSource.getCustomers(
        search: search,
        limit: pageSize,
        offset: (page - 1) * pageSize,
      );

      return {
        'results': reFetched
            .map((c) => {...c, 'id': c['remote_id'] ?? c['local_id']})
            .toList(),
        'count': reFetched.length, // Approximation
        'next': null,
        'previous': null,
      };
    }

    // Convert List<Map> to API Response Format
    return {
      'results': localCustomers
          .map((c) => {...c, 'id': c['remote_id'] ?? c['local_id']})
          .toList(),
      'count': localCustomers.length, // Approximation
      'next': null,
      'previous': null,
    };
  }

  /// Fetch from server and update local cache
  Future<void> _refreshCustomersFromServer(
    int page,
    int pageSize,
    String? search,
  ) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    // Security Guard: No sync if not authenticated
    try {
      if (!await AuthRepository().isAuthenticated()) {
        _isRefreshing = false;
        return;
      }
    } catch (_) {
      return;
    }

    try {
      final Map<String, String> queryParams = {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final response = await _apiClient.get(
        Endpoints.customers,
        queryParams: queryParams,
      );

      final List<dynamic>? results =
          response['results'] ?? response['customers'];
      if (results != null) {
        final List<Map<String, dynamic>> customers = results
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        
        // P2-1 FIX: Cache customers FIRST before any cleanup
        await _localDataSource.cacheCustomers(customers);

        // If it's the first page and no filters, clear old local cache
        // to remove records that might have been deleted on the server.
        // P2-1 FIX: Extended throttle to 6 hours and moved AFTER caching
        // P2-1 FIX: Pass server IDs to only delete truly orphaned records
        if (page == 1 && (search == null || search.isEmpty)) {
          final now = DateTime.now();
          if (_lastPurgeTime == null ||
              now.difference(_lastPurgeTime!).inHours >= 6) {
            debugPrint(
              '[CustomersRepo] Page 1 refresh, clearing orphaned local synced customers...',
            );
            // Extract server customer IDs for safe cleanup
            final serverIds = customers
                .map((c) => c['id'] as int?)
                .whereType<int>()
                .toList();
            
            // Fire-and-forget: Don't await the DELETE to avoid blocking
            _localDataSource.clearSyncedCustomers(serverCustomerIds: serverIds);
            _lastPurgeTime = now;
          }
        }

        // Notify UI of updates
        _syncController.add(null);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Background refresh failed: $e');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Get customer details with background sync support
  Future<Map<String, dynamic>> getCustomerDetail(
    int id, {
    bool triggerSync = true,
  }) async {
    // 1. Check local first
    final local = await _localDataSource.getCustomer(id);

    // 2. Trigger Background Sync if Online
    if (triggerSync && _connectivityService.isOnline) {
      // Fire and forget: Fetch from server and update local DB
      // The UI can listen to syncStream to know when to re-fetch
      _refreshCustomerDetailFromServer(id);
    }

    if (local != null) {
      return {...local, 'id': local['remote_id'] ?? local['local_id']};
    }

    // 3. If missing locally, fetch synchronously
    try {
      final response = await _apiClient.get(Endpoints.customer(id));
      await _localDataSource.cacheCustomer(response);
      return response;
    } catch (e) {
      if (_connectivityService.isOffline) {
        throw Exception(
          'Customer not found locally and no internet connection.',
        );
      }
      rethrow;
    }
  }

  /// Background refresh for a single customer
  Future<void> _refreshCustomerDetailFromServer(int id) async {
    try {
      final response = await _apiClient.get(Endpoints.customer(id));
      await _localDataSource.cacheCustomer(response);
      _syncController.add(null);
    } catch (e) {
      // Silently ignore 404 errors (customer may have been deleted)
      final errorStr = e.toString().toLowerCase();
      if (!errorStr.contains('404') && !errorStr.contains('not found')) {
        debugPrint('[CustomersRepo] Background detail refresh failed: $e');
      }
    }
  }

  /// Find customer by contact info
  Future<Map<String, dynamic>?> findCustomerByContact({
    String? phone,
    String? email,
    String? username,
  }) async {
    return await _localDataSource.getCustomerByContact(
      phone: phone,
      email: email,
      username: username,
    );
  }

  /// Add a new customer (with duplicate detection)
  Future<Map<String, dynamic>> addCustomer(Map<String, dynamic> data) async {
    final phone = data['phone']?.toString();

    // Check for duplicate phone/email locally first (Optimized)
    if ((phone != null && phone.isNotEmpty) ||
        (data['email']?.toString().isNotEmpty ?? false)) {
      final exists = await _localDataSource.existsByContact(
        phone: phone,
        email: data['email']?.toString(),
      );

      if (exists) {
        debugPrint(
          '[CustomersRepo] Duplicate customer detected: $phone / ${data['email']}',
        );
        return {
          'success': true,
          'message': 'العميل موجود مسبقاً',
          'duplicate': true,
        };
      }
    }

    // 1. Save Locally (Optimistic)
    final localId = await _localDataSource.addCustomerLocally(data);

    if (_connectivityService.isOffline) {
      return {
        'success': true,
        'message': 'تمت إضافة العميل محليًا، سيتم المزامنة تلقائيًا',
        'pending': true,
        'customer': {
          'id': localId,
          ...data,
          'is_pending': true,
        },
      };
    }

    // 2. Sync Immediately if Online
    final result = await _apiClient.post(Endpoints.customers, body: data);

    // Update Local with Real ID from Server
    final serverCustomer = result['customer'];
    if (serverCustomer != null && serverCustomer['id'] != null) {
      await _localDataSource.markAsSynced(
        localId,
        remoteId: serverCustomer['id'],
      );
      await _localDataSource.cacheCustomer(serverCustomer);
    }
    return result;
  }

  /// Update customer details (Delta Sync Support)
  /// If customer doesn't exist on server (404), falls back to CREATE.
  Future<Map<String, dynamic>> updateCustomer(
    int id,
    Map<String, dynamic> data,
  ) async {
    // 1. Save Locally (Optimistic)
    await _localDataSource.updateCustomerLocally(id, data);

    if (_connectivityService.isOffline) {
      return {
        'success': true,
        'message': 'تم تحديث البيانات محلياً',
        'pending': true,
      };
    }

    // 2. Sync Immediately if Online
    try {
      final result = await _apiClient.patch(Endpoints.customer(id), body: data);
      if (result['customer'] != null) {
        await _localDataSource.cacheCustomer(result['customer']);
      }
      return result;
    } catch (e) {
      // Handle 404 (customer deleted on server) - convert to CREATE
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('404') || errorStr.contains('not found')) {
        debugPrint(
          '[CustomersRepo] Customer $id not found on server, creating new...',
        );

        // Create new customer on server with the updated data
        final createData = {...data};
        createData.remove('id'); // Don't send old ID

        try {
          final result = await _apiClient.post(
            Endpoints.customers,
            body: createData,
          );

          // Update local record with new server ID
          final serverCustomer = result['customer'];
          if (serverCustomer != null && serverCustomer['id'] != null) {
            await _localDataSource.markAsSynced(
              id,
              remoteId: serverCustomer['id'],
            );
            await _localDataSource.cacheCustomer(serverCustomer);
          }
          return result;
        } catch (createError) {
          debugPrint(
            '[CustomersRepo] Create fallback also failed: $createError',
          );
          // P0-3 FIX: Return proper error status instead of false success
          return {
            'success': false,
            'error': createError.toString(),
            'message': 'فشل تحديث العميل: $createError',
            'pending': true,
          };
        }
      }

      // P0-3 FIX: Return proper error status for network errors
      // Don't return false success - let OfflineSyncService handle retry
      return {
        'success': false,
        'error': e.toString(),
        'message': 'فشل الاتصال بالخادم، سيتم المحاولة لاحقاً',
        'pending': true, // Queue for retry
        'retryable': true,
      };
    }
  }

  /// Get all customer phone numbers for duplicate detection
  Future<Set<String>> getAllCustomerPhones() async {
    return await _localDataSource.getAllCustomerPhones();
  }

  /// Delete a customer
  Future<Map<String, dynamic>> deleteCustomer(int id) async {
    // 1. Get customer info before deleting locally (to handle potential ID mismatch fallback)
    final existing = await _localDataSource.getCustomer(id);

    // 2. Delete Locally
    await _localDataSource.deleteCustomerLocally(id);

    if (_connectivityService.isOffline) {
      return {
        'success': true,
        'message': 'تم حذف الشَّخص محلياً',
        'pending': true,
      };
    }

    // 3. Sync Immediately if Online
    try {
      final result = await _apiClient.delete(Endpoints.customer(id));
      return result;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('404') || errorStr.contains('not found')) {
        // ID mismatch fallback: If we have contact info, try to find the real ID and delete it
        if (existing != null) {
          final name = existing['name'] ?? 'Unknown';
          final phone = existing['phone'];
          final email = existing['email'];

          if ((phone != null && phone.isNotEmpty) ||
              (email != null && email.isNotEmpty)) {
            debugPrint(
              '[CustomersRepo] Delete failed (404), attempting to re-sync ID for $name...',
            );
            try {
              // Try to find the correct ID on the server
              final syncResult = await _apiClient.post(
                Endpoints.customers,
                body: {'name': name, 'phone': phone, 'email': email},
              );

              final serverId = syncResult['customer']?['id'];
              if (serverId != null && serverId != id) {
                debugPrint(
                  '[CustomersRepo] Found correct remote ID $serverId, retrying delete...',
                );
                return await _apiClient.delete(Endpoints.customer(serverId));
              }
            } catch (syncErr) {
              debugPrint(
                '[CustomersRepo] Re-sync delete fallback failed: $syncErr',
              );
            }
          }
        }

        // If we reach here, either we couldn't re-sync or the ID was already correct (and it's already gone)
        // Since we already deleted locally, we can return success if it's a 404
        return {
          'success': true,
          'message': 'تم الحذف بنجاح (العميل غير موجود على الخادم)',
        };
      }

      return {
        'success': true,
        'message': 'تم حذف الشَّخص محلياً وسيتم المزامنة لاحقاً',
        'pending': true,
      };
    }
  }

  /// Delete multiple customers
  Future<Map<String, dynamic>> bulkDeleteCustomers(List<int> ids) async {
    if (ids.isEmpty) return {'success': true};

    // 1. Delete Locally First (Optimistic)
    await _localDataSource.deleteCustomersLocally(ids);

    if (_connectivityService.isOffline) {
      return {
        'success': true,
        'message': 'تم حذف الأشخاص محلياً وسيتم المزامنة لاحقاً',
        'pending': true,
      };
    }

    // 2. Sync Immediately if Online
    try {
      final result = await _apiClient.post(
        '/api/customers/bulk-delete',
        body: {'customer_ids': ids},
      );
      return result;
    } catch (e) {
      debugPrint('[CustomersRepo] Bulk delete failed: $e');
      return {'success': false, 'message': 'حدث خطأ أثناء الاتصال بالخادم'};
    }
  }

  /// Check if a username exists on Almudeer
  Future<Map<String, dynamic>> checkUsername(String username) async {
    try {
      final response = await _apiClient.get(
        '/api/admin/subscription/check-username/$username',
      );
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('Username check failed: $e');
      }
      return {'exists': false, 'error': e.toString()};
    }
  }

  /// Update customer locally only (used for background sync/websocket)
  Future<void> updateCustomerLocally(int id, Map<String, dynamic> data) async {
    await _localDataSource.updateCustomerLocally(id, data);
  }

  void dispose() {
    _syncController.close();
  }
}
