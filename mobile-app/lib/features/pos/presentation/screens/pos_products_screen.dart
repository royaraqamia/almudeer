import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../../data/models/pos_product.dart';

class PosProductsScreen extends StatefulWidget {
  const PosProductsScreen({super.key});

  @override
  State<PosProductsScreen> createState() => _PosProductsScreenState();
}

class _PosProductsScreenState extends State<PosProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _filteredProducts = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterProducts('');
    });
  }

  void _filterProducts(String query) {
    final products = context.read<PosProvider>().products;
    if (query.isEmpty && _selectedCategoryId == null) {
      setState(() => _filteredProducts = products);
    } else {
      setState(() {
        _filteredProducts = products.where((p) {
          final matchesQuery = query.isEmpty || 
            p.name.contains(query) || 
            p.barcode.contains(query) ||
            (p.nameEn?.contains(query) ?? false);
          final matchesCategory = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
          return matchesQuery && matchesCategory;
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<PosProvider>().categories;
    final exchangeRate = context.watch<PosProvider>().exchangeRate;
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showProductDialog()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: _filterProducts,
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                FilterChip(
                  label: const Text('الكل'),
                  selected: _selectedCategoryId == null,
                  onSelected: (_) {
                    setState(() => _selectedCategoryId = null);
                    _filterProducts(_searchController.text);
                  },
                ),
                const SizedBox(width: 8),
                ...categories.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat.name),
                    selected: _selectedCategoryId == cat.id,
                    onSelected: (_) {
                      setState(() => _selectedCategoryId = cat.id);
                      _filterProducts(_searchController.text);
                    },
                  ),
                )),
              ],
            ),
          ),
          Expanded(
            child: _filteredProducts.isEmpty
                ? const Center(child: Text('لا توجد منتجات'))
                : ListView.builder(
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return _buildProductTile(product, exchangeRate, numberFormat);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTile(Product product, double exchangeRate, NumberFormat numberFormat) {
    final priceSYP = product.getPriceInSYP(exchangeRate);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.inventory_2, color: Colors.grey),
        ),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.barcode, style: const TextStyle(fontSize: 12)),
            Row(
              children: [
                Text('\$${product.sellingPriceUSD.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const Text(' | ', style: TextStyle(color: Colors.grey)),
                Text('${numberFormat.format(priceSYP.round())} ل.س', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${product.stock}', style: TextStyle(
              fontWeight: FontWeight.bold,
              color: product.stock < product.minStock ? Colors.red : Colors.green,
            )),
            const Text('المخزون', style: TextStyle(fontSize: 10)),
          ],
        ),
        onTap: () => _showProductDialog(product: product),
        onLongPress: () => _showDeleteDialog(product),
      ),
    );
  }

  void _showProductDialog({Product? product}) {
    final isEdit = product != null;
    final nameController = TextEditingController(text: product?.name ?? '');
    final barcodeController = TextEditingController(text: product?.barcode ?? '');
    final priceUSDController = TextEditingController(text: product?.sellingPriceUSD.toString() ?? '');
    final costController = TextEditingController(text: product?.costPrice.toString() ?? '');
    final stockController = TextEditingController(text: product?.stock.toString() ?? '0');
    final minStockController = TextEditingController(text: product?.minStock.toString() ?? '5');
    final categories = context.read<PosProvider>().categories;
    int? selectedCategory = product?.categoryId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'تعديل منتج' : 'إضافة منتج'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'الاسم')),
                const SizedBox(height: 8),
                TextField(controller: barcodeController, decoration: const InputDecoration(labelText: 'الباركود')),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                  items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategory = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: priceUSDController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع (دولار)')),
                const SizedBox(height: 8),
                TextField(controller: costController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر التكلفة (دولار)')),
                const SizedBox(height: 8),
                TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المخزون')),
                const SizedBox(height: 8),
                TextField(controller: minStockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأدنى')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || barcodeController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال الاسم والباركود')));
                  return;
                }

                final newProduct = Product(
                  id: product?.id,
                  barcode: barcodeController.text,
                  name: nameController.text,
                  sellingPriceUSD: double.tryParse(priceUSDController.text) ?? 0,
                  costPrice: double.tryParse(costController.text) ?? 0,
                  stock: int.tryParse(stockController.text) ?? 0,
                  minStock: int.tryParse(minStockController.text) ?? 5,
                  categoryId: selectedCategory,
                );

                final provider = context.read<PosProvider>();
                if (isEdit) {
                  await provider.updateProduct(newProduct);
                } else {
                  await provider.addProduct(newProduct);
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _filterProducts(_searchController.text);
              },
              child: Text(isEdit ? 'تحديث' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text('هل أنت متأكد من حذف "${product.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await context.read<PosProvider>().deleteProduct(product.id!);
              if (ctx.mounted) Navigator.pop(ctx);
              _filterProducts(_searchController.text);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}