import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';

class PosDashboardScreen extends StatefulWidget {
  const PosDashboardScreen({super.key});

  @override
  State<PosDashboardScreen> createState() => _PosDashboardScreenState();
}

class _PosDashboardScreenState extends State<PosDashboardScreen> {
  Map<String, dynamic>? _todayStats;
  List<dynamic>? _lowStockProducts;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final provider = context.read<PosProvider>();
    final stats = await provider.getTodayStats();
    final lowStock = await provider.getLowStockProducts();
    if (mounted) {
      setState(() {
        _todayStats = stats;
        _lowStockProducts = lowStock;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<PosProvider>().exchangeRate;
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاط البيع'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/pos/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildExchangeRateCard(exchangeRate, numberFormat),
              const SizedBox(height: 16),
              _buildTodaySalesCard(numberFormat),
              const SizedBox(height: 16),
              _buildQuickActions(context),
              const SizedBox(height: 16),
              if (_lowStockProducts != null && _lowStockProducts!.isNotEmpty)
                _buildLowStockCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExchangeRateCard(double exchangeRate, NumberFormat numberFormat) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.currency_exchange, size: 40, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('سعر الصرف', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  Text(
                    '1 USD = ${numberFormat.format(exchangeRate)} SYP',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.pushNamed(context, '/pos/settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySalesCard(NumberFormat numberFormat) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text('مبيعات اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            if (_todayStats == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('عدد المعاملات:'),
                  Text('${_todayStats!['count']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي (دولار):'),
                  Text(
                    '\$${_todayStats!['totalUSD'].toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي (ليرة):'),
                  Text(
                    '${numberFormat.format(_todayStats!['totalSYP'].round())} ل.س',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('إجراءات سريعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                context,
                icon: Icons.point_of_sale,
                label: 'مبيعات',
                color: Colors.blue,
                onTap: () => Navigator.pushNamed(context, '/pos/sales'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                context,
                icon: Icons.inventory,
                label: 'المنتجات',
                color: Colors.orange,
                onTap: () => Navigator.pushNamed(context, '/pos/products'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                context,
                icon: Icons.qr_code_scanner,
                label: 'مسح',
                color: Colors.purple,
                onTap: () => Navigator.pushNamed(context, '/pos/scanner'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text('نقص المخزون', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ..._lowStockProducts!.take(5).map((product) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(product.name)),
                    Text('${product.stock} متبقي', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
            if (_lowStockProducts!.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('+${_lowStockProducts!.length - 5} أكثر', style: const TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}