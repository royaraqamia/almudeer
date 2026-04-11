import 'package:flutter/foundation.dart';
import '../../data/models/pos_product.dart';
import '../../data/models/pos_category.dart';
import '../../data/models/pos_transaction.dart';
import '../../data/services/pos_database_service.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double getTotalUSD(double exchangeRate) => product.sellingPriceUSD * quantity;
  double getTotalSYP(double exchangeRate) => product.getPriceInSYP(exchangeRate) * quantity;
}

class PosProvider extends ChangeNotifier {
  final PosDatabaseService _db = PosDatabaseService();

  double _exchangeRate = 12780.0;
  List<Product> _products = [];
  List<PosCategory> _categories = [];
  List<Transaction> _transactions = [];
  final List<CartItem> _cart = [];
  bool _isLoading = false;
  String? _error;

  double get exchangeRate => _exchangeRate;
  List<Product> get products => _products;
  List<PosCategory> get categories => _categories;
  List<Transaction> get transactions => _transactions;
  List<CartItem> get cart => _cart;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get cartSubtotalUSD => _cart.fold(0, (sum, item) => sum + item.getTotalUSD(_exchangeRate));
  double get cartSubtotalSYP => _cart.fold(0, (sum, item) => sum + item.getTotalSYP(_exchangeRate));
  int get cartItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _exchangeRate = await _db.getCurrentExchangeRate();
      await loadProducts();
      await loadCategories();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadProducts({int? categoryId}) async {
    try {
      _products = await _db.getProducts(categoryId: categoryId);
      notifyListeners();
    } catch (e) {
      _error = 'خطأ في تحميل المنتجات: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    try {
      _categories = await _db.getCategories();
      notifyListeners();
    } catch (e) {
      _error = 'خطأ في تحميل الفئات: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> loadTransactions({DateTime? startDate, DateTime? endDate}) async {
    try {
      _transactions = await _db.getTransactions(startDate: startDate, endDate: endDate);
      notifyListeners();
    } catch (e) {
      _error = 'خطأ في تحميل المعاملات: ${e.toString()}';
      notifyListeners();
    }
  }

  Product? findProductByBarcode(String barcode) {
    try {
      return _products.firstWhere((p) => p.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  void addToCart(Product product) {
    // Check if product is in stock
    if (product.stock <= 0) {
      return;
    }
    
    final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);
    if (existingIndex >= 0) {
      // Check if adding more would exceed stock
      if (_cart[existingIndex].quantity >= product.stock) {
        return;
      }
      _cart[existingIndex].quantity++;
    } else {
      _cart.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeFromCart(int index) {
    _cart.removeAt(index);
    notifyListeners();
  }

  void updateCartItemQuantity(int index, int quantity) {
    if (quantity <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index].quantity = quantity;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  Future<int> checkout({double discount = 0, PaymentMethod paymentMethod = PaymentMethod.cash, String? notes}) async {
    final subtotalUSD = cartSubtotalUSD;
    final subtotalSYP = cartSubtotalSYP;
    
    // Ensure discount doesn't exceed subtotal
    final validDiscount = discount.clamp(0.0, subtotalUSD);
    final totalUSD = subtotalUSD - validDiscount;
    final totalSYP = subtotalSYP - (validDiscount * _exchangeRate);

    final transaction = Transaction(
      items: _cart.map((item) => TransactionItem(
        productId: item.product.id!,
        productName: item.product.name,
        barcode: item.product.barcode,
        quantity: item.quantity,
        unitPriceUSD: item.product.sellingPriceUSD,
        unitPriceSYP: item.product.getPriceInSYP(_exchangeRate),
        totalUSD: item.getTotalUSD(_exchangeRate),
        totalSYP: item.getTotalSYP(_exchangeRate),
      )).toList(),
      subtotalUSD: subtotalUSD,
      subtotalSYP: subtotalSYP,
      discount: validDiscount,
      totalUSD: totalUSD,
      totalSYP: totalSYP,
      exchangeRate: _exchangeRate,
      paymentMethod: paymentMethod,
      notes: notes,
    );

    final id = await _db.addTransaction(transaction);
    clearCart();
    await loadProducts();
    return id;
  }

  Future<void> updateExchangeRate(double rate, {String? notes}) async {
    try {
      await _db.updateExchangeRate(rate, notes: notes);
      _exchangeRate = rate;
      notifyListeners();
    } catch (e) {
      _error = 'خطأ في تحديث سعر الصرف: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getTodayStats() async {
    return await _db.getSalesStats(date: DateTime.now());
  }

  Future<List<Product>> getLowStockProducts() async {
    return await _db.getLowStockProducts();
  }

  Future<void> addProduct(Product product) async {
    try {
      await _db.addProduct(product);
      await loadProducts();
    } catch (e) {
      _error = 'خطأ في إضافة المنتج: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      await _db.updateProduct(product);
      await loadProducts();
    } catch (e) {
      _error = 'خطأ في تحديث المنتج: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteProduct(int id) async {
    try {
      await _db.deleteProduct(id);
      await loadProducts();
    } catch (e) {
      _error = 'خطأ في حذف المنتج: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addCategory(PosCategory category) async {
    try {
      await _db.addCategory(category);
      await loadCategories();
    } catch (e) {
      _error = 'خطأ في إضافة الفئة: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> insertSampleData() async {
    await _db.insertSampleData();
    await loadCategories();
    await loadProducts();
  }
}