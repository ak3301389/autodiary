import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/car.dart';
import '../models/expense.dart';
import '../models/service_item.dart';

class DbService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // === АВТОМОБИЛИ ===
  Stream<List<Car>> watchCars(String userId) {
    return _db
        .collection('cars')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => Car.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<String> addCar(Car car) async {
    final ref = await _db.collection('cars').add(car.toMap());
    return ref.id;
  }

  Future<void> updateCar(Car car) async {
    await _db.collection('cars').doc(car.id).update(car.toMap());
  }

  Future<void> deleteCar(String carId) async {
    await _db.collection('cars').doc(carId).delete();
    // Удаляем все расходы этой машины
    final expenses = await _db
        .collection('expenses')
        .where('carId', isEqualTo: carId)
        .get();
    for (final doc in expenses.docs) {
      await doc.reference.delete();
    }
  }

  // === РАСХОДЫ ===
  Stream<List<Expense>> watchExpenses(String carId) {
    return _db
        .collection('expenses')
        .where('carId', isEqualTo: carId)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Expense.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> addExpense(Expense expense) async {
    await _db.collection('expenses').add(expense.toMap());
  }

  Future<void> deleteExpense(String expenseId) async {
    await _db.collection('expenses').doc(expenseId).delete();
  }

  Future<void> updateExpense(Expense expense) async {
    await _db.collection('expenses').doc(expense.id).update(expense.toMap());
  }

  Stream<List<UserService>> watchUserServices(String userId) {
    return _db
        .collection('user_services')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => UserService.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Future<void> addUserService(String userId, UserService service) async {
    final map = service.toMap();
    map['userId'] = userId;
    await _db.collection('user_services').doc(service.id).set(map);
  }

  Future<void> deleteUserService(String id) async {
    await _db.collection('user_services').doc(id).delete();
  }

  Future<void> updateUserService(UserService service) async {
    await _db
        .collection('user_services')
        .doc(service.id)
        .update(service.toMap());
  }
}
