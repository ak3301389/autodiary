import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/service_item.dart';
import '../providers/data_provider.dart';
import '../core/theme.dart';

class ServicePickerScreen extends StatefulWidget {
  const ServicePickerScreen({super.key});

  @override
  State<ServicePickerScreen> createState() => _ServicePickerScreenState();
}

class _ServicePickerScreenState extends State<ServicePickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final userServices = data.userServices;
    final query = _query.trim().toLowerCase();

    final mergedGroups = <ServiceGroup>[];
    for (final baseGroup in ServiceCatalog.groups) {
      final baseItems = baseGroup.items.toList();

      final userItems = userServices
          .where((us) => us.groupTitle == baseGroup.title)
          .map(
            (us) => ServiceItem(
              id: us.id,
              name: '${us.name} *',
              category: us.groupTitle,
            ),
          )
          .toList();

      final allItems = [...baseItems, ...userItems];

      final filtered = query.isEmpty
          ? allItems
          : allItems
                .where((i) => i.name.toLowerCase().contains(query))
                .toList();

      if (filtered.isNotEmpty) {
        mergedGroups.add(ServiceGroup(title: baseGroup.title, items: filtered));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Выбор работы')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Поиск работы...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: mergedGroups.isEmpty
                ? const Center(
                    child: Text(
                      'Ничего не найдено',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView(
                    children: [
                      ...mergedGroups.map((g) => _buildGroup(g)),
                      ListTile(
                        leading: const Icon(Icons.add, color: AppTheme.primary),
                        title: const Text(
                          'Свой вариант...',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _showAddCustomDialog,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(ServiceGroup group) {
    return ExpansionTile(
      title: Text(
        group.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      children: group.items.map((item) {
        final isUserService = item.name.endsWith(' *');
        final cleanName = isUserService
            ? item.name.substring(0, item.name.length - 2)
            : item.name;

        return ListTile(
          contentPadding: const EdgeInsets.only(left: 32, right: 16),
          title: Text(item.name),
          onTap: () => Navigator.pop(context, item),
          trailing: isUserService
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      onPressed: () =>
                          _editUserService(item.id, group.title, cleanName),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: () => _deleteUserService(item.id),
                    ),
                  ],
                )
              : null,
        );
      }).toList(),
    );
  }

  Future<void> _showAddCustomDialog() async {
    final nameCtrl = TextEditingController();
    String selectedGroup = ServiceCatalog.groups.first.title;
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Свой вариант'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Название работы',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: 'В какую группу добавить?',
                      border: OutlineInputBorder(),
                    ),
                    items: ServiceCatalog.groups.map((g) {
                      return DropdownMenuItem(
                        value: g.title,
                        child: Text(g.title),
                      );
                    }).toList(),
                    onChanged: isLoading
                        ? null
                        : (v) {
                            if (v != null) setState(() => selectedGroup = v);
                          },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          setState(() => isLoading = true);
                          try {
                            await context.read<DataProvider>().addUserService(
                              selectedGroup,
                              nameCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Работа сохранена'),
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() => isLoading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Ошибка: $e')),
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteUserService(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить работу?'),
        content: const Text('Она исчезнет из списка навсегда.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await context.read<DataProvider>().deleteUserService(id);
    }
  }

  Future<void> _editUserService(
    String id,
    String currentGroup,
    String currentName,
  ) async {
    final nameCtrl = TextEditingController(text: currentName);
    String selectedGroup = currentGroup;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать работу'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название работы',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedGroup,
              decoration: const InputDecoration(
                labelText: 'Группа',
                border: OutlineInputBorder(),
              ),
              items: ServiceCatalog.groups.map((g) {
                return DropdownMenuItem(value: g.title, child: Text(g.title));
              }).toList(),
              onChanged: (v) {
                if (v != null) selectedGroup = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await context.read<DataProvider>().updateUserService(
                id,
                selectedGroup,
                nameCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Изменения сохранены')));
    }
  }
}
