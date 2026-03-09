import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:solar_icon_pack/solar_icon_pack.dart';
import 'package:almudeer_mobile_app/presentation/providers/calculator_provider.dart';
import 'package:almudeer_mobile_app/presentation/widgets/calculator/calculator_button.dart';
import 'package:almudeer_mobile_app/presentation/widgets/calculator/calculator_display.dart';
import 'package:almudeer_mobile_app/core/constants/colors.dart';
import 'package:almudeer_mobile_app/presentation/widgets/premium_bottom_sheet.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  bool _isScientific = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalculatorProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: theme.brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
          statusBarBrightness: theme.brightness == Brightness.light
              ? Brightness.light
              : Brightness.dark,
        ),
        title: Text(
          'الحاسبة',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(SolarLinearIcons.arrowRight, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isScientific
                  ? SolarLinearIcons.calculator
                  : SolarLinearIcons.sidebarCode,
              size: 24,
              color: _isScientific ? AppColors.primary : null,
            ),
            onPressed: () => setState(() => _isScientific = !_isScientific),
            tooltip: _isScientific ? 'الوضع العادي' : 'الوضع العلمي',
          ),
          IconButton(
            icon: const Icon(SolarLinearIcons.history, size: 24),
            onPressed: () => _showHistory(context, provider),
            tooltip: 'السجل',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: _isScientific ? 2 : 3,
            child: CalculatorDisplay(
              expression: provider.expression,
              result: provider.result,
            ),
          ),
          Expanded(
            flex: 5,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  children: [
                    if (_isScientific) ..._buildScientificRows(provider),
                    ..._buildStandardRows(provider),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStandardRows(CalculatorProvider provider) {
    return [
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(
              text: 'AC',
              onTap: () => provider.clear(),
              color: Colors.orange[100],
              textColor: Colors.orange[900],
            ),
            CalculatorButton(
              text: 'DEL',
              onTap: () => provider.delete(),
              color: Colors.orange[100],
              textColor: Colors.orange[900],
            ),
            CalculatorButton(
              text: '%',
              onTap: () => provider.append('%'),
              color: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary,
            ),
            CalculatorButton(
              text: '÷',
              onTap: () => provider.append('÷'),
              color: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary,
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(text: '7', onTap: () => provider.append('7')),
            CalculatorButton(text: '8', onTap: () => provider.append('8')),
            CalculatorButton(text: '9', onTap: () => provider.append('9')),
            CalculatorButton(
              text: '×',
              onTap: () => provider.append('×'),
              color: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary,
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(text: '4', onTap: () => provider.append('4')),
            CalculatorButton(text: '5', onTap: () => provider.append('5')),
            CalculatorButton(text: '6', onTap: () => provider.append('6')),
            CalculatorButton(
              text: '-',
              onTap: () => provider.append('-'),
              color: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary,
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(text: '1', onTap: () => provider.append('1')),
            CalculatorButton(text: '2', onTap: () => provider.append('2')),
            CalculatorButton(text: '3', onTap: () => provider.append('3')),
            CalculatorButton(
              text: '+',
              onTap: () => provider.append('+'),
              color: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary,
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(
              text: '0',
              onTap: () => provider.append('0'),
              isLarge: true,
            ),
            CalculatorButton(text: '.', onTap: () => provider.append('.')),
            CalculatorButton(
              text: '=',
              onTap: () => provider.evaluate(),
              color: AppColors.primary,
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildScientificRows(CalculatorProvider provider) {
    return [
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(
              text: 'sin',
              onTap: () => provider.append('sin('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: 'cos',
              onTap: () => provider.append('cos('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: 'tan',
              onTap: () => provider.append('tan('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: 'log',
              onTap: () => provider.append('log('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CalculatorButton(
              text: '(',
              onTap: () => provider.append('('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: ')',
              onTap: () => provider.append(')'),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: '√',
              onTap: () => provider.append('sqrt('),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
            CalculatorButton(
              text: '^',
              onTap: () => provider.append('^'),
              color: Colors.blueGrey[50],
              textColor: Colors.blueGrey[800],
            ),
          ],
        ),
      ),
    ];
  }

  void _showHistory(BuildContext context, CalculatorProvider provider) {
    PremiumBottomSheet.show(
      context: context,
      title: 'سجلُّ العمليَّات',
      maxHeight: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'السِّجلُّ فارغ',
                style: TextStyle(
                  fontFamily: 'IBM Plex Sans Arabic',
                  color: Colors.grey,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: provider.history.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                itemBuilder: (context, index) {
                  final entry = provider.history[index];
                  return ListTile(
                    title: Text(
                      entry,
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'IBM Plex Sans Arabic',
                      ),
                      textAlign: TextAlign.start,
                    ),
                    onTap: () {
                      provider.restoreFromHistory(entry);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
