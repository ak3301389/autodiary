import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/car.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';

class AddCarScreen extends StatefulWidget {
  final Car? car;
  const AddCarScreen({super.key, this.car});

  @override
  State<AddCarScreen> createState() => _AddCarScreenState();
}

class _AddCarScreenState extends State<AddCarScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.car != null) {
      _brandCtrl.text = widget.car!.brand;
      _modelCtrl.text = widget.car!.model;
      _yearCtrl.text = widget.car!.year.toString();
      _plateCtrl.text = widget.car!.plate;
      _mileageCtrl.text = widget.car!.mileage.toString();
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _plateCtrl.dispose();
    _mileageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final car = Car(
      id: widget.car?.id ?? const Uuid().v4(),
      userId: context.read<AuthProvider>().user!.uid,
      brand: _brandCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      year: int.tryParse(_yearCtrl.text) ?? DateTime.now().year,
      plate: _plateCtrl.text.trim(),
      mileage: int.tryParse(_mileageCtrl.text) ?? 0,
      createdAt: widget.car?.createdAt ?? DateTime.now(),
    );

    if (widget.car != null) {
      await context.read<DataProvider>().updateCar(car);
    } else {
      await context.read<DataProvider>().addCar(car);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.car != null ? 'Редактировать авто' : 'Новый автомобиль',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('Марка', _brandCtrl),
            const SizedBox(height: 12),
            _field('Модель', _modelCtrl),
            const SizedBox(height: 12),
            _field('Год выпуска', _yearCtrl, keyboard: TextInputType.number),
            const SizedBox(height: 12),
            _field('Гос. номер', _plateCtrl),
            const SizedBox(height: 12),
            _field('Пробег (км)', _mileageCtrl, keyboard: TextInputType.number),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _save, child: const Text('Сохранить')),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
    );
  }
}
