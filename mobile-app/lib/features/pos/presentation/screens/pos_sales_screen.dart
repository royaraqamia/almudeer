import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../../data/models/pos_product.dart';

class PosSalesScreen extends StatefulWidget {
  const PosSalesScreen({super.key});

  @override
  State<PosSalesScreen> createState() => _PosSalesScreenState();
}

class _PosSalesScreenState extends State<PosSalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final products = context.read<PosProvider>().products;
      setState(() => _filteredProducts = products);
    });
  }

  void _filterProducts(String query) {
    final products = context.read<PosProvider>().products;
    if (query.isEmpty) {
      setState(() => _filteredProducts = products);
    } else {
      setState(() {
        _filteredProducts = products.where((p) =>
          p.name.contains(query) || 
          p.barcode.contains(query) ||
          (p.nameEn?.contains(query) ?? false)
        ).toList();
      });
    }
  }

  void _addToCart(Product product) {
    context.read<PosProvider>().addToCart(product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة ${product.name}'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<PosProvider>().cart;
    final exchangeRate = context.watch<PosProvider>().exchangeRate;
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.pushNamed(context, '/pos/scanner'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الباركود...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: _filterProducts,
            ),
          ),
          Expanded(
            child: _filteredProducts.isEmpty
                ? const Center(child: Text('لا توجد منتجات'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return _buildProductCard(product, exchangeRate, numberFormat);
                    },
                  ),
          ),
          if (cart.isNotEmpty) _buildCartSummary(cart, exchangeRate, numberFormat),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, double exchangeRate, NumberFormat numberFormat) {
    final priceSYP = product.getPriceInSYP(exchangeRate);
    final inCart = context.watch<PosProvider>().cart.any((item) => item.product.id == product.id);

    return InkWell(
      onTap: () => _addToCart(product),
      child: Card(
        color: inCart ? Colors.green.shade50 : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2, size: 40, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '\$${product.sellingPriceUSD.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
              Text(
                '${numberFormat.format(priceSYP.round())} ل.س',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Text('المخزون: ${product.stock}', style: TextStyle(fontSize: 10, color: product.stock < 5 ? Colors.red : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartSummary(List cart, double exchangeRate, NumberFormat numberFormat) {
    final provider = context.read<PosProvider>();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${provider.cartItemCount} عناصر', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${numberFormat.format(provider.cartSubtotalSYP.round())} ل.س', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/pos/checkout'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('الدفع', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}