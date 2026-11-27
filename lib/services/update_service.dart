import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Информация о последнем релизе на GitHub.
class UpdateInfo {
  /// Версия без префикса «v»: например «1.1.1.31».
  final String version;

  /// Прямая ссылка на APK-файл.
  final String apkUrl;

  /// Имя APK-файла из ассета релиза.
  final String apkName;

  /// Комментарий к релизу. Пустая строка, если в релизе `body == null`.
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.apkName,
    required this.notes,
  });
}

/// Проверка обновлений, скачивание и установка APK поверх текущего приложения.
class UpdateService {
  /// Публичный репозиторий с релизами: OWNER/REPO.
  static const String defaultRepo = 'ak3301389/autodiary-releases';

  static const String _kLastCheck = 'update_last_check';
  static const String _kSkipVersion = 'update_skip_version';

  UpdateService({this.repo = defaultRepo});

  /// Можно переопределить в тестах или для второго окружения.
  final String repo;

  String get _apiUrl => 'https://api.github.com/repos/$repo/releases/latest';

  /// Проверяет последнюю версию на GitHub.
  /// Возвращает [UpdateInfo] или `null` при любой ошибке
  /// (нет сети / не-200 / нет `.apk` в ассетах).
  Future<UpdateInfo?> checkLatest() async {
    try {
      final resp = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawTag = (json['tag_name'] as String? ?? '').trim();
      if (rawTag.isEmpty) return null;

      final version = _stripVersionPrefix(rawTag);
      if (version.isEmpty) return null;

      // body в ответе GitHub может быть null — приводим к пустой строке.
      final notes = json['body'] as String? ?? '';
      final assets = json['assets'] as List? ?? [];

      // Ищем первый ассет с расширением .apk.
      String? apkUrl;
      String? apkName;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          final url = asset['browser_download_url'] as String?;
          if (url != null && url.isNotEmpty) {
            apkUrl = url;
            apkName = name;
            break;
          }
        }
      }
      if (apkUrl == null || apkName == null) return null;

      return UpdateInfo(
        version: version,
        apkUrl: apkUrl,
        apkName: apkName,
        notes: notes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Нужно ли проверять обновление сейчас.
  /// `true`, если прошло больше 24 часов с последней проверки.
  Future<bool> shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastCheck) ?? 0;
    if (last == 0) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 24 * 60 * 60 * 1000;
    return (now - last) > day;
  }

  /// Сохраняет дату последней проверки (сейчас).
  Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  /// Запоминает, что пользователь отложил обновление этой версии.
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkipVersion, version);
  }

  /// Проверяет, откладывал ли пользователь обновление этой версии.
  Future<bool> isSkipped(String version) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSkipVersion) == version;
  }

  /// Сравнивает две версии. `true`, если [latest] новее [current].
  /// Формат: «1.1.1.31» или «1.1.1+31» → берём до «+».
  bool isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    final len = l.length > c.length ? l.length : c.length;
    for (int i = 0; i < len; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  List<int> _parse(String v) {
    final clean = _stripVersionPrefix(v.trim())
        .split('+')
        .first
        .split('-')
        .first
        .trim();
    if (clean.isEmpty) return const [0];
    return clean.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  }

  /// Срезает ведущий префикс «v»/«V» («v1.1.1.31» → «1.1.1.31»).
  String _stripVersionPrefix(String value) {
    if (value.startsWith('v') || value.startsWith('V')) {
      return value.substring(1).trim();
    }
    return value;
  }

  /// Скачивает APK во внешнюю app-specific папку и открывает системный
  /// установщик. Прогресс отдаётся в диапазоне 0.0…1.0.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    // Внешняя app-specific папка: путь покрыт filepaths.xml open_filex,
    // поэтому установщик сможет прочитать файл через content://-URI.
    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) {
      throw Exception('Не удалось получить папку для скачивания');
    }

    final apkDir = Directory('${baseDir.path}/updates');
    if (!await apkDir.exists()) {
      await apkDir.create(recursive: true);
    }

    final file = File('${apkDir.path}/${info.apkName}');
    // Если файл уже есть — удаляем (докачка не поддерживается).
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    IOSink? sink;
    try {
      final resp = await client.send(
        http.Request('GET', Uri.parse(info.apkUrl)),
      );
      if (resp.statusCode != 200) {
        throw Exception('Сервер вернул ${resp.statusCode}');
      }

      final total = resp.contentLength ?? 0;
      var received = 0;

      sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception('Не удалось открыть установщик: ${result.message}');
      }

      // Системный установщик уже запущен — завершаем процесс приложения,
      // чтобы после установки рядом с новой версией не висело старое окно.
      // Установщик — отдельный процесс, поэтому его работа не прерывается.
      exit(0);
    } finally {
      await sink?.close();
      client.close();
    }
  }
}
