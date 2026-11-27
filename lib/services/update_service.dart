import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // ЗАМЕНИ 'YOUR_GITHUB_USERNAME' на свой логин GitHub, а 'autodiary' на имя репозитория
  static const String repoOwner = 'ak3301389';
  static const String repoName = 'autodiary-releases';

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion =
          '${packageInfo.version}.${packageInfo.buildNumber}';

      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
        ),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersionTag =
            data['tag_name'] as String; // например, "v1.0.1"
        final cleanLatestVersion = latestVersionTag.startsWith('v')
            ? latestVersionTag.substring(1)
            : latestVersionTag;

        if (_isNewerVersion(cleanLatestVersion, currentVersion)) {
          return {
            'hasUpdate': true,
            'latestVersion': cleanLatestVersion,
            'releaseNotes': data['body'] ?? 'Исправления и улучшения',
            'downloadUrl': data['html_url'], // Ссылка на релиз на GitHub
          };
        }
      }
      return {'hasUpdate': false};
    } catch (e) {
      print('Ошибка проверки обновлений: $e');
      return {'hasUpdate': false};
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    String clean(String v) {
      return v.replaceAll(RegExp(r'[^0-9.]'), '').trim();
    }

    final latestParts = clean(latest)
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final currentParts = clean(current)
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final l = latestParts.length > i ? latestParts[i] : 0;
      final c = currentParts.length > i ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Ошибка при открытии ссылки: $e');
    }
  }
}
