import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../models/expense.dart';
import '../models/service_item.dart';
import '../providers/data_provider.dart';
import '../core/theme.dart';
import '../services/ocr_service.dart';
import 'service_picker_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  final String carId;
  final Expense? expenseToEdit;
  const AddExpenseScreen({super.key, required this.carId, this.expenseToEdit});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final OcrService _ocrService = OcrService();
  final ImagePicker _picker = ImagePicker();

  ExpenseType _type = ExpenseType.fuel;
  final _amountCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _litersCtrl = TextEditingController();
  final _pricePerLiterCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  String? _selectedServiceId;
  bool _isCustomService = false;
  final _customServiceCtrl = TextEditingController();

  final Set<String> _selectedTire = {};
  final Set<String> _selectedInsurance = {};
  final Set<String> _selectedWash = {};
  bool _isCustomInsurance = false;
  bool _isCustomWash = false;
  final _customInsuranceCtrl = TextEditingController();
  final _customWashCtrl = TextEditingController();
  String? _selectedTax;

  final Set<String> _selectedGosuslugi = {};
  bool _isCustomGosuslugi = false;
  final _customGosuslugiCtrl = TextEditingController();

  bool _isScanning = false;
  String? _receiptImagePath;

  @override
  void initState() {
    super.initState();
    final e = widget.expenseToEdit;
    if (e == null) return;

    _type = e.type;
    _amountCtrl.text = e.amount.toString();
    _mileageCtrl.text = e.mileage.toString();
    _noteCtrl.text = e.note;
    _date = e.date;
    _receiptImagePath = e.receiptImagePath;

    if (e.liters != null) _litersCtrl.text = e.liters.toString();
    if (e.pricePerLiter != null) {
      _pricePerLiterCtrl.text = e.pricePerLiter!.toStringAsFixed(2);
    }

    switch (e.type) {
      case ExpenseType.service:
        final match = ServiceItem.defaults
            .where((item) => item.id == e.serviceName)
            .toList();
        if (match.isNotEmpty) {
          _selectedServiceId = match.first.id;
        } else if (e.serviceName != null && e.serviceName!.isNotEmpty) {
          _isCustomService = true;
          _customServiceCtrl.text = e.serviceName!;
        }
        break;
      case ExpenseType.tires:
        if (e.serviceName != null) {
          _selectedTire.addAll(
            e.serviceName!.split(', ').where((s) => TireItem.names.contains(s)),
          );
        }
        break;
      case ExpenseType.insurance:
        if (e.serviceName != null) {
          final parts = e.serviceName!.split(', ');
          for (final p in parts) {
            if (InsuranceItem.names.contains(p)) {
              _selectedInsurance.add(p);
            } else if (p.isNotEmpty) {
              _isCustomInsurance = true;
              _customInsuranceCtrl.text = p;
            }
          }
        }
        break;
      case ExpenseType.wash:
        if (e.serviceName != null) {
          final parts = e.serviceName!.split(', ');
          for (final p in parts) {
            if (WashItem.names.contains(p)) {
              _selectedWash.add(p);
            } else if (p.isNotEmpty) {
              _isCustomWash = true;
              _customWashCtrl.text = p;
            }
          }
        }
        break;
      case ExpenseType.tax:
        _selectedTax = e.serviceName;
        break;
      case ExpenseType.gosuslugi:
        if (e.serviceName != null) {
          final parts = e.serviceName!.split(', ');
          for (final p in parts) {
            if (GosuslugiItem.names.contains(p)) {
              _selectedGosuslugi.add(p);
            } else if (p.isNotEmpty) {
              _isCustomGosuslugi = true;
              _customGosuslugiCtrl.text = p;
            }
          }
        }
        break;
      case ExpenseType.other:
        _customServiceCtrl.text = e.serviceName ?? '';
        break;
      case ExpenseType.fuel:
        break;
    }
  }

  void _calculatePrice() {
    final amountText = _amountCtrl.text.trim().replaceAll(',', '.');
    final litersText = _litersCtrl.text.trim().replaceAll(',', '.');

    if (amountText.isEmpty || litersText.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Заполните оба поля')));
      return;
    }

    final amount = double.tryParse(amountText);
    final liters = double.tryParse(litersText);

    if (amount != null && liters != null && liters > 0) {
      setState(() {
        _pricePerLiterCtrl.text = (amount / liters).toStringAsFixed(2);
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _mileageCtrl.dispose();
    _noteCtrl.dispose();
    _litersCtrl.dispose();
    _pricePerLiterCtrl.dispose();
    _customServiceCtrl.dispose();
    _customInsuranceCtrl.dispose();
    _customWashCtrl.dispose();
    _customGosuslugiCtrl.dispose();
    if (!kIsWeb) {
      _ocrService.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    double amount = double.parse(_amountCtrl.text.replaceAll(',', '.'));
    double? liters = _litersCtrl.text.isNotEmpty
        ? double.parse(_litersCtrl.text.replaceAll(',', '.'))
        : null;
    double? pricePerLiter = _pricePerLiterCtrl.text.isNotEmpty
        ? double.parse(_pricePerLiterCtrl.text.replaceAll(',', '.'))
        : null;

    if (_type == ExpenseType.fuel &&
        liters != null &&
        liters > 0 &&
        pricePerLiter == null) {
      pricePerLiter = amount / liters;
    } else if (_type == ExpenseType.fuel &&
        liters != null &&
        pricePerLiter != null &&
        _amountCtrl.text.isEmpty) {
      amount = liters * pricePerLiter;
    }

    final expense = Expense(
      id: widget.expenseToEdit?.id ?? const Uuid().v4(),
      carId: widget.carId,
      type: _type,
      amount: amount,
      mileage: int.parse(_mileageCtrl.text),
      date: _date,
      note: _noteCtrl.text.trim(),
      liters: liters,
      pricePerLiter: pricePerLiter,
      serviceName: _buildServiceName(),
      receiptImagePath: _receiptImagePath,
    );

    if (widget.expenseToEdit != null) {
      await context.read<DataProvider>().updateExpense(expense);
    } else {
      await context.read<DataProvider>().addExpense(expense);
    }

    if (mounted) context.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _scanReceipt() async {
    setState(() => _isScanning = true);
    try {
      final result = await _ocrService.scanReceipt();
      if (result != null) {
        if (result['amount'] != null)
          _amountCtrl.text = result['amount'].toString();
        if (result['liters'] != null)
          _litersCtrl.text = result['liters'].toString();
        if (result['date'] != null) setState(() => _date = result['date']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка сканирования: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    setState(() {
      _receiptImagePath = null;
    });

    final url = await _ocrService.uploadToCloudinary(bytes);
    if (url != null && mounted) {
      setState(() => _receiptImagePath = url);
    }
  }

  String get _serviceDisplayName {
    if (_isCustomService) {
      return _customServiceCtrl.text.trim().isEmpty
          ? 'Свой вариант...'
          : _customServiceCtrl.text.trim();
    }
    if (_selectedServiceId == null) return 'Выбрать работу';
    for (final group in ServiceCatalog.groups) {
      for (final item in group.items) {
        if (item.id == _selectedServiceId) return item.name;
      }
    }
    for (final item in ServiceItem.defaults) {
      if (item.id == _selectedServiceId) return item.name;
    }
    return 'Выбрать работу';
  }

  Future<void> _pickService() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServicePickerScreen()),
    );
    if (result == null) return;
    setState(() {
      if (result == 'custom') {
        _isCustomService = true;
        _selectedServiceId = null;
      } else if (result is ServiceItem) {
        _isCustomService = false;
        _selectedServiceId = result.id;
      }
    });
  }

  String? _buildServiceName() {
    switch (_type) {
      case ExpenseType.service:
        return _isCustomService
            ? _customServiceCtrl.text.trim()
            : _selectedServiceId;
      case ExpenseType.tires:
        return _selectedTire.isEmpty ? null : _selectedTire.join(', ');
      case ExpenseType.insurance:
        final parts = <String>[..._selectedInsurance];
        if (_isCustomInsurance && _customInsuranceCtrl.text.trim().isNotEmpty) {
          parts.add(_customInsuranceCtrl.text.trim());
        }
        return parts.isEmpty ? null : parts.join(', ');
      case ExpenseType.wash:
        final parts = <String>[..._selectedWash];
        if (_isCustomWash && _customWashCtrl.text.trim().isNotEmpty) {
          parts.add(_customWashCtrl.text.trim());
        }
        return parts.isEmpty ? null : parts.join(', ');
      case ExpenseType.tax:
        return _selectedTax;
      case ExpenseType.gosuslugi:
        final parts = <String>[..._selectedGosuslugi];
        if (_isCustomGosuslugi && _customGosuslugiCtrl.text.trim().isNotEmpty) {
          parts.add(_customGosuslugiCtrl.text.trim());
        }
        return parts.isEmpty ? null : parts.join(', ');
      case ExpenseType.other:
        return _customServiceCtrl.text.trim().isEmpty
            ? null
            : _customServiceCtrl.text.trim();
      case ExpenseType.fuel:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.expenseToEdit != null
              ? 'Редактировать расход'
              : 'Новый расход',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ExpenseType.values.map((t) {
                final selected = t == _type;
                return ChoiceChip(
                  label: Text('${t.icon} ${t.label}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'Сумма (₽)',
                    _amountCtrl,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    required: true,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Сканировать чек',
                  onPressed: _isScanning ? null : _scanReceipt,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              'Пробег (км)',
              _mileageCtrl,
              keyboard: TextInputType.number,
              required: true,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(
                '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            if (_type == ExpenseType.fuel) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      'Литры',
                      _litersCtrl,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 32,
                    ),
                    tooltip: 'Посчитать цену за литр',
                    onPressed: _calculatePrice,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pricePerLiterCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Цена за литр (₽)',
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.trending_up,
                      color: AppTheme.primary,
                    ),
                    tooltip: 'Динамика цен',
                    onPressed: () {
                      context.push('/stats');
                    },
                  ),
                ],
              ),
            ],
            if (_type != ExpenseType.fuel) ...[
              const SizedBox(height: 12),
              if (_type == ExpenseType.service) ...[
                InkWell(
                  onTap: _pickService,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Наименование',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      _serviceDisplayName,
                      style: TextStyle(
                        color: _selectedServiceId == null && !_isCustomService
                            ? AppTheme.textMuted
                            : AppTheme.textDark,
                      ),
                    ),
                  ),
                ),
                if (_isCustomService) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customServiceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Введите наименование',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Обязательное поле'
                        : null,
                  ),
                ],
              ],
              if (_type == ExpenseType.tires) ...[
                const Text('Выберите шины'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TireItem.names.map((name) {
                    final selected = _selectedTire.contains(name);
                    return FilterChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedTire.add(name);
                        } else {
                          _selectedTire.remove(name);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],
              if (_type == ExpenseType.insurance) ...[
                const Text('Выберите страховку'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...InsuranceItem.names.map((name) {
                      final selected = _selectedInsurance.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedInsurance.add(name);
                          } else {
                            _selectedInsurance.remove(name);
                          }
                        }),
                      );
                    }),
                    FilterChip(
                      label: const Text('➕ Свой вариант'),
                      selected: _isCustomInsurance,
                      onSelected: (v) => setState(() => _isCustomInsurance = v),
                    ),
                  ],
                ),
                if (_isCustomInsurance) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customInsuranceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Свой вариант страховки',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              if (_type == ExpenseType.wash) ...[
                const Text('Выберите тип мойки'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...WashItem.names.map((name) {
                      final selected = _selectedWash.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedWash.add(name);
                          } else {
                            _selectedWash.remove(name);
                          }
                        }),
                      );
                    }),
                    FilterChip(
                      label: const Text('➕ Свой вариант'),
                      selected: _isCustomWash,
                      onSelected: (v) => setState(() => _isCustomWash = v),
                    ),
                  ],
                ),
                if (_isCustomWash) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customWashCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Свой вариант мойки',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              if (_type == ExpenseType.tax) ...[
                DropdownButtonFormField<String>(
                  value: _selectedTax,
                  decoration: const InputDecoration(labelText: 'Тип налога'),
                  items: TaxItem.names.map((name) {
                    return DropdownMenuItem(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedTax = val),
                ),
              ],
              if (_type == ExpenseType.gosuslugi) ...[
                const Text('Выберите услугу'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...GosuslugiItem.names.map((name) {
                      final selected = _selectedGosuslugi.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedGosuslugi.add(name);
                          } else {
                            _selectedGosuslugi.remove(name);
                          }
                        }),
                      );
                    }),
                    FilterChip(
                      label: const Text('➕ Свой вариант'),
                      selected: _isCustomGosuslugi,
                      onSelected: (v) => setState(() => _isCustomGosuslugi = v),
                    ),
                  ],
                ),
                if (_isCustomGosuslugi) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customGosuslugiCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Свой вариант',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              if (_type == ExpenseType.other) ...[
                TextFormField(
                  controller: _customServiceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            _field('Заметка', _noteCtrl, maxLines: 3),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _receiptImagePath == null
                    ? 'Прикрепить фото чека'
                    : 'Фото прикреплено ✓',
              ),
            ),
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
    bool required = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? 'Обязательное поле' : null
          : null,
    );
  }
}
