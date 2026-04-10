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
    _products = await _db.getProducts(categoryId: categoryId);
    notifyListeners();
  }

  Future<void> loadCategories() async {
    _categories = await _db.getCategories();
    notifyListeners();
  }

  Future<void> loadTransactions({DateTime? startDate, DateTime? endDate}) async {
    _transactions = await _db.getTransactions(startDate: startDate, endDate: endDate);
    notifyListeners();
  }

  Product? findProductByBarcode(String barcode) {
    try {
      return _products.firstWhere((p) => p.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  void addToCart(Product product) {
    final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);
    if (existingIndex >= 0) {
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
    final totalUSD = subtotalUSD - discount;
    final totalSYP = subtotalSYP - (discount * _exchangeRate);

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
      discount: discount,
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
    await _db.updateExchangeRate(rate, notes: notes);
    _exchangeRate = rate;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getTodayStats() async {
    return await _db.getSalesStats(date: DateTime.now());
  }

  Future<List<Product>> getLowStockProducts() async {
    return await _db.getLowStockProducts();
  }

  Future<void> addProduct(Product product) async {
    await _db.addProduct(product);
    await loadProducts();
  }

  Future<void> updateProduct(Product product) async {
    await _db.updateProduct(product);
    await loadProducts();
  }

  Future<void> deleteProduct(int id) async {
    await _db.deleteProduct(id);
    await loadProducts();
  }

  Future<void> addCategory(PosCategory category) async {
    await _db.addCategory(category);
    await loadCategories();
  }

  Future<void> insertSampleData() async {
    await _db.insertSampleData();
    await loadCategories();
    await loadProducts();
  }
}