import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseType {
  fuel,
  service,
  tires,
  insurance,
  tax,
  wash,
  gosuslugi,
  other,
}

extension ExpenseTypeX on ExpenseType {
  String get label {
    switch (this) {
      case ExpenseType.fuel:
        return 'Топливо';
      case ExpenseType.service:
        return 'ТО / Ремонт';
      case ExpenseType.tires:
        return 'Шины';
      case ExpenseType.insurance:
        return 'Страховка';
      case ExpenseType.tax:
        return 'Налог';
      case ExpenseType.wash:
        return 'Мойка';
      case ExpenseType.gosuslugi:
        return 'Госуслуги';
      case ExpenseType.other:
        return 'Прочее';
    }
  }

  String get icon {
    switch (this) {
      case ExpenseType.fuel:
        return '⛽';
      case ExpenseType.service:
        return '🔧';
      case ExpenseType.tires:
        return '🛞';
      case ExpenseType.insurance:
        return '📄';
      case ExpenseType.tax:
        return '💰';
      case ExpenseType.wash:
        return '🚿';
      case ExpenseType.gosuslugi:
        return '🏛️';
      case ExpenseType.other:
        return '📦';
    }
  }
}

class Expense {
  final String id;
  final String carId;
  final ExpenseType type;
  final double amount;
  final int mileage;
  final DateTime date;
  final String note;
  final double? liters;
  final double? pricePerLiter;
  final String? serviceName;
  final String? receiptImagePath;

  Expense({
    required this.id,
    required this.carId,
    required this.type,
    required this.amount,
    required this.mileage,
    required this.date,
    required this.note,
    this.liters,
    this.pricePerLiter,
    this.serviceName,
    this.receiptImagePath,
  });

  factory Expense.fromMap(Map<String, dynamic> map, String id) {
    return Expense(
      id: id,
      carId: map['carId'] ?? '',
      type: ExpenseType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ExpenseType.other,
      ),
      amount: (map['amount'] ?? 0).toDouble(),
      mileage: map['mileage'] ?? 0,
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: map['note'] ?? '',
      liters: (map['liters'] as num?)?.toDouble(),
      pricePerLiter: (map['pricePerLiter'] as num?)?.toDouble(),
      serviceName: map['serviceName'] as String?,
      receiptImagePath: map['receiptImagePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'carId': carId,
      'type': type.name,
      'amount': amount,
      'mileage': mileage,
      'date': Timestamp.fromDate(date),
      'note': note,
      'liters': liters,
      'pricePerLiter': pricePerLiter,
      'serviceName': serviceName,
      'receiptImagePath': receiptImagePath,
    };
  }
}
