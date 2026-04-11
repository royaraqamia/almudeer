import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../../data/models/pos_transaction.dart';

class PosCheckoutScreen extends StatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  State<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends State<PosCheckoutScreen> {
  final TextEditingController _discountController = TextEditingController();
  PaymentMethod _selectedPayment = PaymentMethod.cash;
  bool _isProcessing = false;

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  double get _discount => double.tryParse(_discountController.text) ?? 0;

  Future<void> _processCheckout() async {
    if (_isProcessing) return;
    
    // Validate discount doesn't exceed subtotal
    final provider = context.read<PosProvider>();
    if (_discount > provider.cartSubtotalUSD) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الخصم لا يمكن أن يتجاوز المجموع'), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() => _isProcessing = true);

    try {
      await context.read<PosProvider>().checkout(
        discount: _discount,
        paymentMethod: _selectedPayment,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت المعاملة بنجاح!'), backgroundColor: Colors.green),
        );
        Navigator.popUntil(context, (route) => route.isFirst || route.settings.name == '/pos/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<PosProvider>().cart;
    final exchangeRate = context.watch<PosProvider>().exchangeRate;
    final numberFormat = NumberFormat('#,###');
    final provider = context.read<PosProvider>();

    final subtotalUSD = provider.cartSubtotalUSD;
    final subtotalSYP = provider.cartSubtotalSYP;
    final totalUSD = subtotalUSD - _discount;
    final totalSYP = subtotalSYP - (_discount * exchangeRate);

    return Scaffold(
      appBar: AppBar(title: const Text('الدفع'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: cart.length,
              itemBuilder: (context, index) {
                final item = cart[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('${item.quantity}')),
                  title: Text(item.product.name),
                  subtitle: Text(item.product.barcode),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('\$${item.getTotalUSD(exchangeRate).toStringAsFixed(2)}'),
                      Text('${numberFormat.format(item.getTotalSYP(exchangeRate).round())} ل.س', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  onTap: () => _showQuantityDialog(index, item.quantity),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('المجموع:', style: TextStyle(fontSize: 16)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('\$${subtotalUSD.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${numberFormat.format(subtotalSYP.round())} ل.س', style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'خصم (دولار)', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الإجمالي:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('\$${totalUSD.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                          Text('${numberFormat.format(totalSYP.round())} ل.س', style: const TextStyle(color: Colors.green)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('طريقة الدفع:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildPaymentOption(PaymentMethod.cash, 'نقدي', Icons.money)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPaymentOption(PaymentMethod.mobileWallet, 'محفظة', Icons.phone_android)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPaymentOption(PaymentMethod.qrCode, 'QR', Icons.qr_code)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (cart.isEmpty || _isProcessing || _discount > subtotalUSD) ? null : _processCheckout,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                      child: _isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Text('تأكيد الدفع', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(PaymentMethod method, String label, IconData icon) {
    final isSelected = _selectedPayment == method;
    return InkWell(
      onTap: () => setState(() => _selectedPayment = method),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade100 : Colors.grey.shade100,
          border: Border.all(color: isSelected ? Colors.green : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.green : Colors.grey),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.green : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  void _showQuantityDialog(int index, int currentQty) {
    showDialog(
      context: context,
      builder: (ctx) {
        int quantity = currentQty;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تعديل الكمية'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove), 
                    onPressed: quantity > 1 ? () {
                      setDialogState(() => quantity--);
                      context.read<PosProvider>().updateCartItemQuantity(index, quantity);
                    } : null,
                  ),
                  Text('$quantity', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add), 
                    onPressed: () {
                      setDialogState(() => quantity++);
                      context.read<PosProvider>().updateCartItemQuantity(index, quantity);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    context.read<PosProvider>().removeFromCart(index);
                    Navigator.pop(ctx);
                    // Trigger UI update
                    setState(() {});
                  }, 
                  child: const Text('حذف', style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: () {
                    if (quantity <= 0) {
                      context.read<PosProvider>().removeFromCart(index);
                    }
                    Navigator.pop(ctx);
                    // Trigger UI update
                    setState(() {});
                  }, 
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}