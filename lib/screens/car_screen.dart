import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/data_provider.dart';
import '../models/expense.dart';
import '../models/car.dart';
import '../models/service_item.dart';
import '../screens/add_car_screen.dart';
import '../core/theme.dart';

class CarScreen extends StatefulWidget {
  final String carId;
  const CarScreen({super.key, required this.carId});

  @override
  State<CarScreen> createState() => _CarScreenState();
}

class _CarScreenState extends State<CarScreen> {
  ExpenseType? _selectedFilter;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    context.read<DataProvider>().subscribeToExpenses(widget.carId);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final car = data.cars.firstWhere((c) => c.id == widget.carId);
    final allExpenses = data.expensesFor(widget.carId);
    final filteredByType = _selectedFilter == null
        ? allExpenses
        : allExpenses.where((e) => e.type == _selectedFilter).toList();

    final expenses = filteredByType.where((e) {
      if (_startDate != null && e.date.isBefore(_startDate!)) return false;
      if (_endDate != null &&
          e.date.isAfter(_endDate!.add(const Duration(days: 1))))
        return false;
      return true;
    }).toList();

    final total = expenses.fold<double>(0, (s, e) => s + e.amount);
    final fuelTotal = allExpenses
        .where((e) => e.type == ExpenseType.fuel)
        .fold<double>(0, (s, e) => s + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(car.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddCarScreen(car: car)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Удалить авто?'),
                  content: const Text('Все записи будут удалены.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await data.deleteCar(car.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _summary(total, fuelTotal, allExpenses),
          _upcomingServices(data, car),
          _filterChips(),
          Expanded(
            child: expenses.isEmpty
                ? const Center(
                    child: Text(
                      'Пока нет записей',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: expenses.length,
                    itemBuilder: (_, i) {
                      final e = expenses[i];
                      final fmt = NumberFormat.currency(
                        locale: 'ru_RU',
                        symbol: '₽',
                      );
                      final dateFmt = DateFormat('dd.MM.yyyy');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              e.type.icon,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          title: Text(
                            e.serviceName ?? e.type.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            e.type == ExpenseType.fuel && e.liters != null
                                ? '${dateFmt.format(e.date)} • ${e.liters!.toStringAsFixed(1)} л • ${fmt.format(e.amount)}'
                                : '${dateFmt.format(e.date)} • ${e.mileage} км',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.receiptImagePath != null)
                                IconButton(
                                  icon: const Icon(
                                    Icons.attach_file,
                                    size: 18,
                                    color: AppTheme.textMuted,
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        child: InteractiveViewer(
                                          child: Image.network(
                                            e.receiptImagePath!,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if (e.receiptImagePath != null)
                                const SizedBox(width: 4),

                              // Кнопка редактирования
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                                onPressed: () => context.push(
                                  '/expense/add/${widget.carId}',
                                  extra: e,
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Кнопка удаления
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () => data.deleteExpense(e.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expense/add/${widget.carId}'),
        icon: const Icon(Icons.add),
        label: const Text('Добавить расход'),
      ),
    );
  }

  Widget _summary(double total, double fuelTotal, List<Expense> expenses) {
    final fmt = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');
    double lPer100 = 0;

    final fuelExpenses = expenses
        .where((e) => e.type == ExpenseType.fuel)
        .toList();
    if (fuelExpenses.length >= 2) {
      fuelExpenses.sort((a, b) => a.mileage.compareTo(b.mileage));
      final first = fuelExpenses.first;
      final last = fuelExpenses.last;
      final distance = last.mileage - first.mileage;
      if (distance > 0) {
        final totalLiters = fuelExpenses.fold<double>(
          0,
          (sum, e) => sum + (e.liters ?? 0),
        );
        lPer100 = (totalLiters / distance) * 100;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _statChip('Всего', fmt.format(total), Icons.payments),
          const SizedBox(width: 8),
          _statChip('Топливо', fmt.format(fuelTotal), Icons.local_gas_station),
          const SizedBox(width: 8),
          _statChip(
            'Расход',
            lPer100 > 0 ? '${lPer100.toStringAsFixed(1)} л/100' : '-',
            Icons.speed,
          ),
        ],
      ),
    );
  }

  Widget _upcomingServices(DataProvider data, Car car) {
    final expenses = data.expensesFor(widget.carId);
    final upcoming = <Widget>[];

    for (final item in ServiceItem.defaults) {
      Expense? last;
      for (final e in expenses) {
        if (e.serviceName == item.id) {
          last = e;
          break;
        }
      }

      if (last != null && item.defaultIntervalKm != null) {
        final nextMileage = last.mileage + item.defaultIntervalKm!.toInt();
        final remaining = nextMileage - car.mileage;

        if (remaining > 0 && remaining < 5000) {
          final isUrgent = remaining < 1000;
          upcoming.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isUrgent
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'через $remaining км',
                    style: TextStyle(
                      fontSize: 11,
                      color: isUrgent ? Colors.red : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView(scrollDirection: Axis.horizontal, children: upcoming),
    );
  }

  Widget _filterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _startDate == null && _endDate == null
                        ? 'Период: Все время'
                        : '${_startDate != null ? DateFormat('dd.MM').format(_startDate!) : '...'} - ${_endDate != null ? DateFormat('dd.MM').format(_endDate!) : '...'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickDateRange,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Все'),
                selected: _selectedFilter == null,
                onSelected: (_) => setState(() => _selectedFilter = null),
              ),
              ...ExpenseType.values.map((type) {
                return FilterChip(
                  label: Text('${type.icon} ${type.label}'),
                  selected: _selectedFilter == type,
                  onSelected: (_) => setState(() {
                    _selectedFilter = _selectedFilter == type ? null : type;
                  }),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
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

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
