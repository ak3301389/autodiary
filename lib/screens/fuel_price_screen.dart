import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/data_provider.dart';
import '../core/theme.dart';

class FuelPriceScreen extends StatefulWidget {
  const FuelPriceScreen({super.key});

  @override
  State<FuelPriceScreen> createState() => _FuelPriceScreenState();
}

class _FuelPriceScreenState extends State<FuelPriceScreen> {
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final allFuel =
        data.cars
            .expand((c) => data.expensesFor(c.id))
            .where(
              (e) =>
                  e.type == ExpenseType.fuel &&
                  e.liters != null &&
                  e.liters! > 0,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final filtered = allFuel.where((e) {
      if (_startDate != null && e.date.isBefore(_startDate!)) return false;
      if (_endDate != null &&
          e.date.isAfter(_endDate!.add(const Duration(days: 1))))
        return false;
      return true;
    }).toList();

    final fmt = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    return Scaffold(
      appBar: AppBar(title: const Text('Динамика цен')),
      body: Column(
        children: [
          _dateFilterButton(),
          if (filtered.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Нет данных за выбранный период',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statsRow(filtered, fmt),
                  const SizedBox(height: 16),
                  _lineChart(filtered),
                  const SizedBox(height: 16),
                  _priceList(filtered, fmt),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateFilterButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.date_range),
        label: Text(
          _startDate == null && _endDate == null
              ? 'Период: всё время'
              : '${DateFormat('dd.MM.yyyy').format(_startDate!)} — ${DateFormat('dd.MM.yyyy').format(_endDate!)}',
        ),
        onPressed: _pickDateRange,
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Widget _statsRow(List<Expense> expenses, fmt) {
    final prices = expenses
        .map((e) => e.pricePerLiter ?? (e.amount / e.liters!))
        .toList();
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    final avg = prices.reduce((a, b) => a + b) / prices.length;

    return Row(
      children: [
        _statCard('Мин', fmt.format(min), Colors.green),
        const SizedBox(width: 8),
        _statCard('Сред', fmt.format(avg), AppTheme.primary),
        const SizedBox(width: 8),
        _statCard('Макс', fmt.format(max), Colors.red),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineChart(List<Expense> expenses) {
    final spots = <FlSpot>[];
    for (int i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      final price = e.pricePerLiter ?? (e.amount / e.liters!);
      spots.add(FlSpot(i.toDouble(), price));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minY: minY - padding,
          maxY: maxY + padding,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final e = expenses[spot.x.toInt()];
                  return LineTooltipItem(
                    '${DateFormat('dd.MM.yyyy').format(e.date)}\n${spot.y.toStringAsFixed(2)} ₽/л',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.accent,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accent.withValues(alpha: 0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toStringAsFixed(0)} ₽',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (expenses.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= expenses.length)
                    return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('dd.MM.yy').format(expenses[index].date),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _priceList(List<Expense> expenses, fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'История заправок',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...expenses.reversed.map((e) {
          final price = e.pricePerLiter ?? (e.amount / e.liters!);
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: const Text('⛽', style: TextStyle(fontSize: 20)),
              title: Text(
                '${e.liters!.toStringAsFixed(1)} л × ${price.toStringAsFixed(2)} ₽',
              ),
              subtitle: Text(
                DateFormat('dd.MM.yyyy').format(e.date),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              trailing: Text(
                fmt.format(e.amount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
      ],
    );
  }
}
