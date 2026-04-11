import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/pos_category.dart';
import '../models/pos_product.dart';
import '../models/pos_transaction.dart' as model;
import '../models/pos_exchange_rate.dart';

class PosDatabaseService {
  static Database? _database;
  static const String _dbName = 'syrian_pos.db';
  static const int _dbVersion = 1;

  static const double initialExchangeRate = 12780.0;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        nameEn TEXT,
        description TEXT,
        imagePath TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        nameEn TEXT,
        costPrice REAL NOT NULL DEFAULT 0,
        sellingPriceUSD REAL NOT NULL DEFAULT 0,
        categoryId INTEGER,
        stock INTEGER NOT NULL DEFAULT 0,
        minStock INTEGER NOT NULL DEFAULT 5,
        imagePath TEXT,
        description TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (categoryId) REFERENCES categories (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        items TEXT NOT NULL,
        subtotalUSD REAL NOT NULL,
        subtotalSYP REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        totalUSD REAL NOT NULL,
        totalSYP REAL NOT NULL,
        exchangeRate REAL NOT NULL,
        paymentMethod TEXT NOT NULL,
        customerId INTEGER,
        notes TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rate REAL NOT NULL,
        notes TEXT,
        effectiveDate TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_category ON products(categoryId)');
    await db.execute('CREATE INDEX idx_transactions_date ON transactions(createdAt)');

    final now = DateTime.now().toIso8601String();
    await db.insert('exchange_rates', {
      'rate': initialExchangeRate,
      'notes': 'Initial rate',
      'effectiveDate': now,
      'createdAt': now,
    });
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<double> getCurrentExchangeRate() async {
    final db = await database;
    final result = await db.query(
      'exchange_rates',
      orderBy: 'effectiveDate DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return (result.first['rate'] as num).toDouble();
    }
    return initialExchangeRate;
  }

  Future<void> updateExchangeRate(double rate, {String? notes}) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert('exchange_rates', {
      'rate': rate,
      'notes': notes,
      'effectiveDate': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });
  }

  Future<List<ExchangeRate>> getExchangeRateHistory() async {
    final db = await database;
    final result = await db.query(
      'exchange_rates',
      orderBy: 'effectiveDate DESC',
    );
    return result.map((e) => ExchangeRate.fromMap(e)).toList();
  }

  Future<int> addCategory(PosCategory category) async {
    final db = await database;
    return await db.insert('categories', category.toMap()..remove('id'));
  }

  Future<List<PosCategory>> getCategories() async {
    final db = await database;
    final result = await db.query('categories', orderBy: 'name ASC');
    return result.map((e) => PosCategory.fromMap(e)).toList();
  }

  Future<void> updateCategory(PosCategory category) async {
    final db = await database;
    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteCategory(int id) async {
    final db = await database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addProduct(Product product) async {
    final db = await database;
    return await db.insert('products', product.toMap()..remove('id'));
  }

  Future<List<Product>> getProducts({int? categoryId, bool? activeOnly}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    if (categoryId != null || activeOnly == true) {
      final conditions = <String>[];
      whereArgs = [];

      if (categoryId != null) {
        conditions.add('categoryId = ?');
        whereArgs.add(categoryId);
      }
      if (activeOnly == true) {
        conditions.add('isActive = 1');
      }

      where = conditions.join(' AND ');
    }

    final result = await db.query(
      'products',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map((e) => Product.fromMap(e)).toList();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return Product.fromMap(result.first);
    }
    return null;
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateProductStock(int productId, int newStock) async {
    final db = await database;
    await db.update(
      'products',
      {'stock': newStock, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> addTransaction(model.Transaction transaction) async {
    final db = await database;
    final map = transaction.toMap()..remove('id');
    map['items'] = jsonEncode(transaction.items.map((e) => e.toMap()).toList());
    final id = await db.insert('transactions', map);

    for (final item in transaction.items) {
      final product = await getProductById(item.productId);
      if (product != null) {
        await updateProductStock(item.productId, product.stock - item.quantity);
      }
    }

    return id;
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return Product.fromMap(result.first);
    }
    return null;
  }

  Future<List<model.Transaction>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    if (startDate != null || endDate != null) {
      final conditions = [];
      whereArgs = [];

      if (startDate != null) {
        conditions.add('createdAt >= ?');
        whereArgs.add(startDate.toIso8601String());
      }
      if (endDate != null) {
        conditions.add('createdAt <= ?');
        whereArgs.add(endDate.toIso8601String());
      }

      where = conditions.join(' AND ');
    }

    final result = await db.query(
      'transactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return result.map((e) {
      final map = Map<String, dynamic>.from(e);
      map['items'] = jsonDecode(e['items'] as String) as List;
      return model.Transaction.fromMap(map);
    }).toList();
  }

  Future<Map<String, dynamic>> getSalesStats({DateTime? date}) async {
    final db = await database;
    String where = '';
    List<dynamic>? whereArgs;

    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      where = 'createdAt >= ? AND createdAt < ?';
      whereArgs = [startOfDay.toIso8601String(), endOfDay.toIso8601String()];
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count, SUM(totalUSD) as totalUSD, SUM(totalSYP) as totalSYP FROM transactions ${where.isNotEmpty ? 'WHERE $where' : ''}',
      whereArgs,
    );

    if (result.isNotEmpty) {
      return {
        'count': result.first['count'] ?? 0,
        'totalUSD': (result.first['totalUSD'] as num?)?.toDouble() ?? 0.0,
        'totalSYP': (result.first['totalSYP'] as num?)?.toDouble() ?? 0.0,
      };
    }

    return {'count': 0, 'totalUSD': 0.0, 'totalSYP': 0.0};
  }

  Future<List<Product>> getLowStockProducts() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT * FROM products WHERE stock <= minStock AND isActive = 1 ORDER BY stock ASC',
    );
    return result.map((e) => Product.fromMap(e)).toList();
  }

  Future<void> insertSampleData() async {
    final categories = [
      {'name': 'مشروبات', 'nameEn': 'Beverages'},
      {'name': 'مأكولات', 'nameEn': 'Food'},
      {'name': 'أجهزة إلكترونية', 'nameEn': 'Electronics'},
      {'name': 'ملابس', 'nameEn': 'Clothing'},
      {'name': 'منتجات تنظيف', 'nameEn': 'Cleaning'},
    ];

    final db = await database;
    for (final cat in categories) {
      await db.insert('categories', {
        ...cat,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }

    final products = [
      {'barcode': '5000112637922', 'name': 'كوكا كولا 330 مل', 'nameEn': 'Coca Cola 330ml', 'sellingPriceUSD': 0.5, 'costPrice': 0.35, 'categoryId': 1, 'stock': 50},
      {'barcode': '5000112637923', 'name': 'بيبسي 330 مل', 'nameEn': 'Pepsi 330ml', 'sellingPriceUSD': 0.5, 'costPrice': 0.35, 'categoryId': 1, 'stock': 45},
      {'barcode': '4006381333931', 'name': 'شيبس ليز كيس صغير', 'nameEn': 'Lays Chips Small', 'sellingPriceUSD': 1.0, 'costPrice': 0.6, 'categoryId': 2, 'stock': 30},
      {'barcode': '5000159484695', 'name': 'شوكولاتة كيت كات', 'nameEn': 'Kit Kat', 'sellingPriceUSD': 0.75, 'costPrice': 0.5, 'categoryId': 2, 'stock': 40},
      {'barcode': '8711327543534', 'name': 'آيفون شاحن', 'nameEn': 'iPhone Charger', 'sellingPriceUSD': 5.0, 'costPrice': 3.0, 'categoryId': 3, 'stock': 10},
      {'barcode': '6901234567890', 'name': 'كبل USB', 'nameEn': 'USB Cable', 'sellingPriceUSD': 1.5, 'costPrice': 0.8, 'categoryId': 3, 'stock': 25},
      {'barcode': '8901234567891', 'name': 'تيشيرت أبيض', 'nameEn': 'White T-Shirt', 'sellingPriceUSD': 3.0, 'costPrice': 1.5, 'categoryId': 4, 'stock': 20},
      {'barcode': '8901234567892', 'name': 'جينز', 'nameEn': 'Jeans', 'sellingPriceUSD': 8.0, 'costPrice': 5.0, 'categoryId': 4, 'stock': 15},
      {'barcode': '6001234567890', 'name': 'سائل جلي', 'nameEn': 'Dish Soap', 'sellingPriceUSD': 1.0, 'costPrice': 0.6, 'categoryId': 5, 'stock': 35},
      {'barcode': '6001234567891', 'name': 'مسحوق غسيل', 'nameEn': 'Detergent', 'sellingPriceUSD': 2.5, 'costPrice': 1.5, 'categoryId': 5, 'stock': 20},
    ];

    for (final prod in products) {
      await db.insert('products', {
        ...prod,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }
}