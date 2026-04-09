import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../../data/models/pos_category.dart';

class PosSettingsScreen extends StatefulWidget {
  const PosSettingsScreen({super.key});

  @override
  State<PosSettingsScreen> createState() => _PosSettingsScreenState();
}

class _PosSettingsScreenState extends State<PosSettingsScreen> {
  final TextEditingController _rateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rate = context.read<PosProvider>().exchangeRate;
      _rateController.text = rate.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<PosProvider>().exchangeRate;
    final categories = context.watch<PosProvider>().categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [Icon(Icons.currency_exchange), SizedBox(width: 8), Text('سعر الصرف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر الصرف (ليرة للدولار)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('السعر الحالي: 1 USD = $exchangeRate SYP', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onUpdateRate,
                      child: const Text('تحديث السعر'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [Icon(Icons.category), SizedBox(width: 8), Text('الفئات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
                  ),
                  const SizedBox(height: 16),
                  if (categories.isEmpty)
                    const Text('لا توجد فئات', style: TextStyle(color: Colors.grey))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((cat) => Chip(label: Text(cat.name))).toList(),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _showAddCategoryDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة فئة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [Icon(Icons.backup), SizedBox(width: 8), Text('النسخ الاحتياطي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
                  ),
                  const SizedBox(height: 16),
                  const Text('تصدير البيانات إلى ملف JSON أو Excel للمحافظة عليها.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ميزة النسخ الاحتياطي coming soon!')));
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('تصدير البيانات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [Icon(Icons.data_array), SizedBox(width: 8), Text('بيانات تجريبية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
                  ),
                  const SizedBox(height: 16),
                  const Text('إضافة منتجات وفئات تجريبية للاختبار.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _onInsertSampleData,
                      icon: const Icon(Icons.add_box),
                      label: const Text('إضافة بيانات تجريبية'),
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

  Future<void> _onUpdateRate() async {
    final newRate = double.tryParse(_rateController.text);
    if (newRate == null || newRate <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال سعر صرف صحيح')));
      return;
    }
    await context.read<PosProvider>().updateExchangeRate(newRate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث سعر الصرف'), backgroundColor: Colors.green));
  }

  Future<void> _onInsertSampleData() async {
    await context.read<PosProvider>().insertSampleData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة البيانات التجريبية'), backgroundColor: Colors.green));
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة فئة'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'اسم الفئة'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              await context.read<PosProvider>().addCategory(
                PosCategory(name: nameController.text),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}