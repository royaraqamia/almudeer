import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/customers_repository.dart';
import '../../core/services/persistent_cache_service.dart';
import '../../core/services/websocket_service.dart';

class CustomersProvider extends ChangeNotifier {
  final CustomersRepository _repository;
  final WebSocketService _webSocketService;

  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _isDisposed = false;

  // Pagination
  int _currentPage = 1;
  bool _hasNextPage = false;

  // Filters
  String _searchQuery = '';
  Timer? _debounceTimer;
  StreamSubscription? _syncSubscription;

  // Selection Mode
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  // Username Lookup State
  bool _isCheckingUsername = false;
  String? _foundUsernameDetails;
  bool _usernameNotFound = false;
  Timer? _usernameLookupTimer;

  // Getters
  List<Customer> get customers => _customers;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasNextPage => _hasNextPage;
  String get searchQuery => _searchQuery;

  /// Get filtered customers based on search query
  List<Customer> get filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final query = _searchQuery.toLowerCase();
    return _customers.where((c) {
      final name = c.name?.toLowerCase() ?? '';
      final phone = c.phone?.toLowerCase() ?? '';
      final company = c.company?.toLowerCase() ?? '';
      final username = c.username?.toLowerCase() ?? '';
      final contact = c.contact.toLowerCase();
      return name.contains(query) ||
          phone.contains(query) ||
          company.contains(query) ||
          username.contains(query) ||
          contact.contains(query);
    }).toList();
  }

  /// Find a customer by contact (phone or username)
  Customer? getCustomerByContact(String? contact) {
    if (contact == null || contact.isEmpty) return null;
    try {
      return _customers.firstWhere(
        (c) =>
            c.phone == contact ||
            c.username == contact ||
            c.contact == contact,
      );
    } catch (e) {
      return null;
    }
  }

  bool get isSelectionMode => _isSelectionMode;
  Set<int> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;

  bool get isCheckingUsername => _isCheckingUsername;
  String? get foundUsernameDetails => _foundUsernameDetails;
  bool get usernameNotFound => _usernameNotFound;

  void toggleSelectionMode(bool enabled) {
    if (_isSelectionMode == enabled) return;
    _isSelectionMode = enabled;
    if (!enabled) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelection(int id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<void> bulkDelete() async {
    if (_selectedIds.isEmpty) return;

    try {
      final idsToDelete = _selectedIds.toList();

      // Optimistic removal
      _customers.removeWhere((c) => _selectedIds.contains(c.id));
      clearSelection();

      // Perform deletion efficiently in one API call
      final result = await _repository.bulkDeleteCustomers(idsToDelete);

      if (result['success'] == false) {
        // Revert optimistic deletion on failure
        _error = result['message'] ?? 'فشل الحذف';
        notifyListeners();
        loadCustomers(refresh: true);
      } else {
        notifyListeners();
      }
    } catch (e) {
      _error = 'فشل حذف بعض العناصر';
      notifyListeners();
      loadCustomers(refresh: true);
    }
  }

  CustomersProvider({
    CustomersRepository? repository,
    WebSocketService? webSocketService,
  }) : _repository = repository ?? CustomersRepository(),
       _webSocketService = webSocketService ?? WebSocketService() {
    _init();
  }

  void _init() {
    _syncSubscription = _repository.syncStream.listen((_) {
      loadCustomers(refresh: true, triggerSync: false);
    });

    // Listen to WebSocket events for real-time customer updates from admin
    _webSocketService.stream.listen((event) {
      if (event['event'] == 'customer_updated') {
        final data = event['data'] as Map<String, dynamic>? ?? {};
        final senderContact = data['sender_contact'] as String?;
        final updatedFields = data['updated_fields'] as Map<String, dynamic>?;

        if (senderContact != null && updatedFields != null) {
          debugPrint(
            '[CustomersProvider] Customer updated from admin: $senderContact',
          );
          _handleRemoteCustomerUpdate(senderContact, updatedFields);
        }
      }
    });

    loadCustomers();
  }

  void _handleRemoteCustomerUpdate(
    String contact,
    Map<String, dynamic> updatedFields,
  ) async {
    // Support for username change migration
    final oldContact = updatedFields['old_sender_contact'] as String?;

    // 1. Update in-memory list - find by either old or new contact
    int index = _customers.indexWhere((c) => c.contact == contact);
    if (index == -1 && oldContact != null) {
      index = _customers.indexWhere((c) => c.contact == oldContact);
    }

    if (index != -1) {
      final oldCustomer = _customers[index];

      // Map incoming fields from backend (full_name, profile_image_url, username) to mobile customer fields
      String? newName = oldCustomer.name;
      String? newImage = oldCustomer.image;
      String? newUsername = oldCustomer.username;

      if (updatedFields.containsKey('full_name')) {
        newName = updatedFields['full_name'];
      }
      if (updatedFields.containsKey('profile_image_url')) {
        newImage = updatedFields['profile_image_url'];
      }
      if (updatedFields.containsKey('username')) {
        newUsername = updatedFields['username'];
      }

      final updatedCustomer = oldCustomer.copyWith(
        name: newName,
        image: newImage,
        username: newUsername,
      );

      _customers[index] = updatedCustomer;
      notifyListeners();

      // 2. Update local database cache
      try {
        await _repository.updateCustomerLocally(updatedCustomer.id, {
          'name': updatedCustomer.name,
          'image': updatedCustomer.image,
          'username': updatedCustomer.username,
        });
      } catch (e) {
        debugPrint('Failed to update customer locally: $e');
      }
    }
  }

  Future<void> loadCustomers({
    bool refresh = false,
    bool triggerSync = true,
  }) async {
    _error = null;

    if (refresh) {
      _currentPage = 1;
      _hasNextPage = false;
    } else if (_isLoading) {
      return;
    }

    // 1. Instant Cache Peek for first page
    if (_currentPage == 1 && _customers.isEmpty) {
      try {
        final cache = PersistentCacheService();
        final accountHash = await _repository.apiClient.getAccountCacheHash();
        final cacheKey = '${accountHash}_list_${_currentPage}_$_searchQuery';
        final cachedData = await cache.get<Map<String, dynamic>>(
          PersistentCacheService.boxCustomers,
          cacheKey,
        );

        if (cachedData != null) {
          final responseModel = CustomersResponse.fromJson(cachedData);
          _customers = responseModel.customers;
          _hasNextPage = responseModel.hasMore;
          notifyListeners();
        } else {
          _isLoading = true;
          notifyListeners();
        }
      } catch (_) {
        _isLoading = true;
        notifyListeners();
      }
    } else if (refresh && _customers.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }

    // 2. Fresh Data Sync
    try {
      final response = await _repository.getCustomers(
        page: _currentPage,
        search: _searchQuery,
        triggerSync: triggerSync,
      );

      final responseModel = CustomersResponse.fromJson(response);

      if (_currentPage == 1) {
        _customers = responseModel.customers;
      } else {
        _customers.addAll(responseModel.customers);
      }

      _hasNextPage = responseModel.hasMore;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // Don't show error for offline - just keep showing cached data
      if (_customers.isEmpty) {
        // Show empty state instead of error for offline scenarios
      }
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      final response = await _repository.getCustomers(
        page: nextPage,
        search: _searchQuery,
      );

      final responseModel = CustomersResponse.fromJson(response);

      _customers.addAll(responseModel.customers);
      _currentPage = nextPage;
      _hasNextPage = responseModel.hasMore;
      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      _isLoadingMore = false;
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      loadCustomers(refresh: true);
    });
  }

  void lookupUsername(String username) {
    _usernameLookupTimer?.cancel();

    final trimmedUsername = username.trim().replaceAll('@', '');
    if (trimmedUsername.length < 3) {
      clearUsernameLookup();
      return;
    }

    _usernameLookupTimer = Timer(const Duration(milliseconds: 500), () async {
      _isCheckingUsername = true;
      _foundUsernameDetails = null;
      _usernameNotFound = false;
      notifyListeners();

      try {
        final result = await _repository.checkUsername(trimmedUsername);
        if (_isDisposed) return;

        if (result['exists'] == true) {
          _foundUsernameDetails =
              result['full_name'] ?? result['company_name'] ?? 'مستخدم معروف';
          _usernameNotFound = false;
        } else {
          _foundUsernameDetails = null;
          _usernameNotFound = true;
        }
      } catch (e) {
        if (_isDisposed) return;
        debugPrint('Username lookup failed: $e');
        _foundUsernameDetails = null;
        _usernameNotFound = true;
      } finally {
        if (!_isDisposed) {
          _isCheckingUsername = false;
          notifyListeners();
        }
      }
    });
  }

  void clearUsernameLookup() {
    _foundUsernameDetails = null;
    _isCheckingUsername = false;
    _usernameNotFound = false;
    if (_usernameLookupTimer?.isActive ?? false) _usernameLookupTimer!.cancel();
    notifyListeners();
  }

  void refresh() {
    loadCustomers(refresh: true);
  }

  /// Reset provider state (for account switching)
  void reset() {
    _customers = [];
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    _currentPage = 1;
    _hasNextPage = false;
    _searchQuery = '';
    clearUsernameLookup();
  }

  Future<Map<String, dynamic>> addCustomer(Map<String, dynamic> data) async {
    // Sanitize inputs
    final sanitizedData = Map<String, dynamic>.from(data);
    if (sanitizedData['phone'] != null) {
      sanitizedData['phone'] = (sanitizedData['phone'] as String).replaceAll(
        RegExp(r'[^\d+]'),
        '',
      );
    }
    if (sanitizedData['username'] != null) {
      sanitizedData['username'] = (sanitizedData['username'] as String)
          .trim()
          .replaceAll('@', '');
    }

    try {
      final result = await _repository.addCustomer(sanitizedData);
      final isSuccess =
          result['success'] == true ||
          result.containsKey('id') ||
          result.containsKey('customer');

      if (isSuccess) {
        final customerData = result['customer'] ?? result;
        try {
          final newCus = Customer.fromJson(
            customerData as Map<String, dynamic>,
          );

          // Check if already exists in list (avoid duplicates)
          final existingIndex = _customers.indexWhere((c) => c.id == newCus.id);
          if (existingIndex == -1) {
            _customers.insert(0, newCus);
          } else {
            _customers[existingIndex] = newCus;
          }

          notifyListeners();
        } catch (e) {
          debugPrint('Error parsing added customer: $e');
          // Fallback to refresh if parsing fails
          await loadCustomers(refresh: true);
        }

        return {
          'success': true,
          'message': result['message'] ?? 'تمَّ إضافة الشَّخص بنجاح',
        };
      }

      return {
        'success': false,
        'message': result['error'] ?? result['message'] ?? 'فشلت الإضافة',
      };
    } catch (e) {
      debugPrint('Add customer failed: $e');
      return {'success': false, 'message': 'حدث خطأ غير متوقع أثناء الإضافة'};
    }
  }

  void updateCustomerInList(Map<String, dynamic> updatedData) {
    final id = updatedData['id'];
    if (id == null) return;

    final index = _customers.indexWhere((c) => c.id == id);
    if (index != -1) {
      _customers[index] = _customers[index].copyWith(
        name: updatedData['name'],
        phone: updatedData['phone'],
        username: updatedData['username'],
        isAlmudeerUser:
            updatedData['is_almudeer_user'] == true ||
            updatedData['is_almudeer_user'] == 1 ||
            updatedData['isAlmudeerUser'] == true ||
            updatedData['isAlmudeerUser'] == 1,
      );
      notifyListeners();
    }
  }

  void removeCustomerFromList(dynamic id) {
    _customers.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Find customer by contact info
  Future<Customer?> findCustomer({
    String? phone,
    String? username,
  }) async {
    final result = await _repository.findCustomerByContact(
      phone: phone,
      username: username,
    );

    if (result != null) {
      return Customer.fromJson(result);
    }
    return null;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    _syncSubscription?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
