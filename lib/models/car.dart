import 'package:cloud_firestore/cloud_firestore.dart';

class Car {
  final String id;
  final String userId;
  final String brand;
  final String model;
  final int year;
  final String plate;
  final int mileage;
  final DateTime createdAt;

  Car({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    required this.year,
    required this.plate,
    required this.mileage,
    required this.createdAt,
  });

  String get title => '$brand $model';

  factory Car.fromMap(Map<String, dynamic> map, String id) {
    return Car(
      id: id,
      userId: map['userId'] ?? '',
      brand: map['brand'] ?? '',
      model: map['model'] ?? '',
      year: map['year'] ?? 0,
      plate: map['plate'] ?? '',
      mileage: map['mileage'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'brand': brand,
      'model': model,
      'year': year,
      'plate': plate,
      'mileage': mileage,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
