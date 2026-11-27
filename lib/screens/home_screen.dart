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

  // Обновления
  final UpdateService _updateService = UpdateService();
  UpdateInfo? _pendingUpdate;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
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

  Future<void> _checkForUpdate({bool manual = false}) async {
    // Антифлуд: автоматическая проверка не чаще 1 раза в 24 часа.
    if (!manual) {
      final should = await _updateService.shouldCheck();
      if (!should) return;
    }

    // Фиксируем дату проверки до сетевого запроса (как в референсе).
    await _updateService.markChecked();

    final info = await _updateService.checkLatest();
    if (info == null) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось проверить обновления')),
        );
      }
      return;
    }

    // Пользователь уже откладывал эту версию? (ручную проверку не блокируем)
    if (!manual) {
      final skipped = await _updateService.isSkipped(info.version);
      if (skipped) return;
    }

    // Сравниваем с текущей версией приложения: "<version>.<buildNumber>".
    final pkg = await PackageInfo.fromPlatform();
    final current = '${pkg.version}.${pkg.buildNumber}';

    if (!_updateService.isNewer(info.version, current)) {
      if (manual && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('У вас последняя версия')));
      }
      return;
    }

    if (!mounted) return;
    setState(() => _pendingUpdate = info);
  }

  Future<void> _downloadAndInstall() async {
    final info = _pendingUpdate;
    if (info == null) return;

    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      await _updateService.downloadAndInstall(
        info,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = 0;
        });
      }
    }
  }

  Future<void> _skipUpdate() async {
    final info = _pendingUpdate;
    if (info == null) return;
    await _updateService.skipVersion(info.version);
    if (!mounted) return;
    setState(() => _pendingUpdate = null);
  }

  Widget _buildUpdateBanner(BuildContext context) {
    final info = _pendingUpdate!;

    return Material(
      color: AppTheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.system_update_alt,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Доступно обновление v${info.version}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _downloading ? null : _skipUpdate,
                  tooltip: 'Позже',
                ),
              ],
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.notes,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Скачивание... ${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _downloadAndInstall,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Обновить',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
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
              _checkForUpdate(manual: true);
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
      body: Column(
        children: [
          if (_pendingUpdate != null) _buildUpdateBanner(context),
          Expanded(
            child: data.carsLoading
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
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.1,
                            ),
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
          ),
        ],
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
