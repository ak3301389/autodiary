import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/data_provider.dart';
import '../core/theme.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final allExpenses = data.cars
        .expand((c) => data.expensesFor(c.id))
        .toList();

    final byType = <ExpenseType, double>{};
    for (final e in allExpenses) {
      byType[e.type] = (byType[e.type] ?? 0) + e.amount;
    }
    final total = byType.values.fold<double>(0, (s, v) => s + v);
    final fmt = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: allExpenses.isEmpty
          ? const Center(
              child: Text(
                'Нет данных',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Всего потрачено',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fmt.format(total),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sections: _sections(byType, total),
                              centerSpaceRadius: 40,
                              sectionsSpace: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...byType.entries.map((e) => _row(e.key, e.value, total, fmt)),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Расходы по месяцам',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _monthlyChart(allExpenses, fmt),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Цена за литр топлива',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _priceChart(allExpenses),
              ],
            ),
    );
  }

  Widget _priceChart(List<Expense> expenses) {
    final fuelExpenses =
        expenses
            .where(
              (e) =>
                  e.type == ExpenseType.fuel &&
                  e.liters != null &&
                  e.liters! > 0,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (fuelExpenses.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Нужно минимум 2 заправки для графика',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < fuelExpenses.length; i++) {
      final e = fuelExpenses[i];
      final price = e.pricePerLiter ?? (e.amount / e.liters!);
      spots.add(FlSpot(i.toDouble(), price));
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: minY - padding,
            maxY: maxY + padding,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) {
                  return spots.map((spot) {
                    final e = fuelExpenses[spot.x.toInt()];
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
                dotData: FlDotData(show: true),
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
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= fuelExpenses.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('dd.MM').format(fuelExpenses[index].date),
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
      ),
    );
  }

  Widget _monthlyChart(List<Expense> expenses, fmt) {
    final byMonth = <String, double>{};
    for (final e in expenses) {
      final key = DateFormat('MM.yyyy').format(e.date);
      byMonth[key] = (byMonth[key] ?? 0) + e.amount;
    }
    final sortedKeys = byMonth.keys.toList()..sort();

    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: byMonth.values.reduce((a, b) => a > b ? a : b) * 1.2,
            barGroups: sortedKeys.asMap().entries.map((entry) {
              final amount = byMonth[entry.value] ?? 0.0;
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: amount,
                    color: AppTheme.primary,
                    width: 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= sortedKeys.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        sortedKeys[index],
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _sections(
    Map<ExpenseType, double> byType,
    double total,
  ) {
    final colors = [
      AppTheme.primary,
      AppTheme.accent,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
    ];
    int i = 0;
    return byType.entries.map((e) {
      final pct = (e.value / total * 100);
      return PieChartSectionData(
        value: e.value,
        color: colors[i++ % colors.length],
        title: '${pct.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );
    }).toList();
  }

  Widget _row(ExpenseType type, double value, double total, fmt) {
    final pct = (value / total * 100).toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(type.icon, style: const TextStyle(fontSize: 24)),
        title: Text(type.label),
        subtitle: Text('$pct%'),
        trailing: Text(
          fmt.format(value),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
