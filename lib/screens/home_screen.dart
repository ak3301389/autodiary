import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../core/theme.dart';
import '../services/update_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _appVersion = '';
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version} (${info.buildNumber})';
      });
    }
  }

  Future<void> _checkUpdate({bool showNoUpdateMessage = false}) async {
    if (!showNoUpdateMessage) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;

    final updateInfo = await UpdateService.checkForUpdate();

    if (!mounted) return;

    if (updateInfo != null && updateInfo['hasUpdate'] == true) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Новая версия: ${updateInfo['latestVersion']}'),
              const SizedBox(height: 8),
              const Text(
                'Что нового:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(updateInfo['releaseNotes'] ?? ''),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                UpdateService.openDownloadPage(updateInfo['downloadUrl']);
              },
              child: const Text('Скачать'),
            ),
          ],
        ),
      );
    } else if (showNoUpdateMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('У вас последняя версия')));
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('О приложении'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('АвтоДневник'),
            const SizedBox(height: 8),
            Text('Версия: $_appVersion'),
            const SizedBox(height: 8),
            const Text('Учёт расходов и обслуживания автомобиля.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkUpdate(showNoUpdateMessage: true);
            },
            child: const Text('Проверить обновления'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои автомобили'),
        leading: IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: _showAboutDialog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Статистика',
            onPressed: () => context.push('/stats'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: data.carsLoading
          ? const Center(child: CircularProgressIndicator())
          : data.cars.isEmpty
          ? _emptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: data.cars.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return _buildHeader(data);
                final car = data.cars[i - 1];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.directions_car,
                        color: AppTheme.primary,
                      ),
                    ),
                    title: Text(
                      car.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${car.plate} • ${car.mileage} км • ${car.year} г.',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppTheme.textMuted,
                    ),
                    onTap: () => context.push('/car/${car.id}'),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/car/add'),
        icon: const Icon(Icons.add),
        label: const Text('Добавить авто'),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 80,
              color: AppTheme.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Пока нет автомобилей',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте первый автомобиль,\nчтобы начать учёт расходов',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DataProvider data) {
    final totalMileage = data.cars.fold<int>(
      0,
      (sum, car) => sum + car.mileage,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppTheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _headerStat('${data.cars.length}', 'Авто'),
            Container(width: 1, height: 40, color: Colors.white24),
            _headerStat('$totalMileage км', 'Пробег'),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
