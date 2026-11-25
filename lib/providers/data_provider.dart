import 'package:flutter/material.dart';

import '../models/car.dart';
import '../models/expense.dart';
import '../models/service_item.dart';

import 'package:uuid/uuid.dart';

import '../services/db_service.dart';

class DataProvider extends ChangeNotifier {
  final DbService _db = DbService();
  final String userId;

  DataProvider(this.userId) {
    _init();
  }

  List<Car> _cars = [];
  bool _carsLoading = true;
  Map<String, List<Expense>> _expenses = {};
  List<UserService> _userServices = [];

  List<Car> get cars => _cars;
  bool get carsLoading => _carsLoading;

  List<Expense> expensesFor(String carId) => _expenses[carId] ?? [];

  void _init() {
    _db.watchCars(userId).listen((cars) {
      _cars = cars;
      _carsLoading = false;
      notifyListeners();
    });

    _db.watchUserServices(userId).listen((services) {
      _userServices = services;
      notifyListeners();
    });
  }

  Future<void> addCar(Car car) async {
    await _db.addCar(car);
  }

  Future<void> updateCar(Car car) async {
    await _db.updateCar(car);
  }

  Future<void> deleteCar(String id) async {
    await _db.deleteCar(id);
  }

  void subscribeToExpenses(String carId) {
    _db.watchExpenses(carId).listen((list) {
      final local = _expenses[carId] ?? [];
      final localIds = local.map((e) => e.id).toSet();
      final cloudIds = list.map((e) => e.id).toSet();

      final hasLocalOnly =
          localIds.difference(cloudIds).isNotEmpty ||
          cloudIds.difference(localIds).isNotEmpty;

      if (hasLocalOnly && local.isNotEmpty) {
        final merged = <String, Expense>{
          for (final e in list) e.id: e,
          for (final e in local)
            if (!cloudIds.contains(e.id)) e.id: e,
        }.values.toList()..sort((a, b) => b.date.compareTo(a.date));

        _expenses[carId] = merged;
      } else {
        _expenses[carId] = list;
      }
      notifyListeners();
    });
  }

  Future<void> addExpense(Expense expense) async {
    final list = List<Expense>.from(_expenses[expense.carId] ?? []);
    list.insert(0, expense);
    list.sort((a, b) => b.date.compareTo(a.date));
    _expenses[expense.carId] = list;
    notifyListeners();

    try {
      await _db.addExpense(expense);
    } catch (e) {
      debugPrint('Ошибка сохранения расхода в облако: $e');
    }
  }

  Future<void> updateExpense(Expense expense) async {
    final list = List<Expense>.from(_expenses[expense.carId] ?? []);
    final index = list.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      list[index] = expense;
      list.sort((a, b) => b.date.compareTo(a.date));
      _expenses[expense.carId] = list;
      notifyListeners();
    }

    try {
      await _db.updateExpense(expense);
    } catch (e) {
      debugPrint('Ошибка обновления расхода в облако: $e');
    }
  }

  Future<void> deleteExpense(String id) async {
    String? carId;
    for (final entry in _expenses.entries) {
      if (entry.value.any((e) => e.id == id)) {
        carId = entry.key;
        break;
      }
    }

    if (carId != null) {
      final list = List<Expense>.from(_expenses[carId] ?? []);
      list.removeWhere((e) => e.id == id);
      _expenses[carId] = list;
      notifyListeners();
    }

    try {
      await _db.deleteExpense(id);
    } catch (e) {
      debugPrint('Ошибка удаления расхода из облака: $e');
    }
  }

  List<UserService> get userServices => _userServices;

  Future<void> addUserService(String groupTitle, String name) async {
    final service = UserService(
      id: const Uuid().v4(),
      groupTitle: groupTitle,
      name: name,
    );
    _userServices = List.from(_userServices)..add(service);
    notifyListeners();
    await _db.addUserService(userId, service);
  }

  Future<void> deleteUserService(String id) async {
    _userServices = _userServices.where((s) => s.id != id).toList();
    notifyListeners();
    await _db.deleteUserService(id);
  }

  Future<void> updateUserService(
    String id,
    String groupTitle,
    String name,
  ) async {
    final index = _userServices.indexWhere((s) => s.id == id);
    if (index != -1) {
      final updated = UserService(id: id, groupTitle: groupTitle, name: name);
      _userServices = List.from(_userServices)..[index] = updated;
      notifyListeners();
      await _db.updateUserService(updated);
    }
  }
}
