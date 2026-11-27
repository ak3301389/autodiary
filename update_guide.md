# ТЗ: механизм самообновления приложения (APK) для Flutter-проекта

Документ описывает рабочую реализацию «обновления поверх установленного APK» (без Google Play / RuStore)
и содержит пошаговый чеклист переноса в другое Flutter-приложение.

**Референсная реализация (проект `dimontazh`):**

| Файл | Роль |
|---|---|
| `lib/data/repositories/update_service.dart` | проверка последней версии, сравнение версий, хранение «отложенных» версий, скачивание APK с прогрессом, запуск системного установщика |
| `lib/features/home/home_screen.dart` | вызов проверки при старте (`initState`), баннер «Доступно обновление», прогресс загрузки, ошибки |
| `pubspec.yaml` | зависимости механизма: `package_info_plus`, `http`, `path_provider`, `open_filex`, `shared_preferences` |
| `android/app/src/main/AndroidManifest.xml` | разрешение `REQUEST_INSTALL_PACKAGES` |

**Ограничения (важно проговорить с заказчиком):**

* Механизм **только для Android**. iOS не позволяет устанавливать сборки извне (только TestFlight/App Store), iOS-ветки обновления в проекте нет.
* Версия берётся из GitHub Releases, а не из стора → приложение распространяется сайдлоадом (APK/сайт/Telegram). Для Google Play `REQUEST_INSTALL_PACKAGES` — sensitive permission, публикация будет затруднена.
* Обновление ставится **поверх** установленного приложения: нужны тот же `applicationId`, та же подпись (keystore) и **больший** `versionCode`.
* Откат на старую версию невозможен (Android блокирует downgrade).

---

## 1. Архитектура потока

```
HomeScreen.initState()
   └─ UpdateService.markChecked()                 // фиксируем дату проверки
   └─ UpdateService.shouldCheck()                 // (опционально) прошло > 24 ч ?
   └─ UpdateService.checkLatest()                 // GET https://api.github.com/.../releases/latest
         └─ null  → тихо выходим (нет сети / нет релиза / нет .apk в assets)
   └─ UpdateService.isSkipped(info.version)       // пользователь нажал «Позже» для этой версии?
   └─ PackageInfo.fromPlatform()                  // текущая версия: "<version>.<buildNumber>"
   └─ UpdateService.isNewer(latest, current)      // поразрядное числовое сравнение
   └─ setState(() => _pendingUpdate = info)       // показываем баннер
         └─ «Обновить» → UpdateService.downloadAndInstall(onProgress: ...)
               └─ GET apkUrl в /storage/emulated/0/Android/data/<pkg>/files/updates/<name>.apk
               └─ OpenFilex.open(path)            // системный диалог установки APK
```

Публичный API сервиса (как в референсе):

| Метод | Назначение | Возвращает |
|---|---|---|
| `Future<UpdateInfo?> checkLatest()` | запрос последнего релиза | `UpdateInfo` или `null` при любой ошибке |
| `Future<bool> shouldCheck()` | антифлуд: не чаще 1 раза в 24 часа | `true/false` |
| `Future<void> markChecked()` | запомнить время проверки | — |
| `Future<void> skipVersion(String v)` | «Позже» для конкретной версии | — |
| `Future<bool> isSkipped(String v)` | откладывал ли пользователь эту версию | `true/false` |
| `bool isNewer(String latest, String current)` | сравнение версий | `true`, если `latest` новее |
| `Future<void> downloadAndInstall(UpdateInfo info, {void Function(double)? onProgress})` | скачать APK и открыть установщик | `Future`, прогресс 0.0…1.0 |

---

## 2. Где хранится информация о новой версии

### 2.1 Источник

Информация хранится **не внутри приложения**, а в **публичном GitHub-репозитории релизов**
(отдельный репозиторий, чтобы не смешивать его с репозиторием исходников): в проекте это
`ak3301389/dimontazh-releases`.

* Эндпоинт (константа `_apiUrl` в `update_service.dart`):
  `https://api.github.com/repos/ak3301389/dimontazh-releases/releases/latest`
* Метод: `GET`, заголовок `Accept: application/vnd.github+json`.
* `releases/latest` возвращает **последний опубликованный** релиз; `draft` и `prerelease` не учитываются.
* Авторизация не нужна (публичный репозиторий), но действует лимит GitHub API: 60 запросов/час на IP
  без токена — поэтому в проде проверка ограничена 24 часами (см. `shouldCheck`).

### 2.2 Формат JSON и обязательные поля

Ответ — стандартный объект GitHub Release. Используются только 4 поля:

```json
{
  "tag_name": "v3.7.1.26",
  "name": "3.7.1.26",
  "body": "- Исправлен расчёт потолка с нишей\n- Ускорена синхронизация заказов",
  "draft": false,
  "prerelease": false,
  "assets": [
    {
      "name": "dimontazh-3.7.1.26.apk",
      "size": 48231456,
      "content_type": "application/vnd.android.package-archive",
      "browser_download_url": "https://github.com/ak3301389/dimontazh-releases/releases/download/v3.7.1.26/dimontazh-3.7.1.26.apk"
    }
  ]
}
```

| Поле | Обязательно | Как используется |
|---|---|---|
| `tag_name` | **да** | версия; из строки удаляется первый символ `v` (`replaceFirst('v', '')`). Если поля нет — версия `''` |
| `body` | нет | текст «что нового» в баннере. Пустая строка → блок описания не показывается |
| `assets[].name` | **да** | поиск APK: берётся первый ассет, имя которого в нижнем регистре заканчивается на `.apk` |
| `assets[].browser_download_url` | **да** | прямая ссылка на скачивание APK |

Правила, без которых обновление не сработает:

1. В релиз **должен быть приложен файл с расширением `.apk`** (иначе `checkLatest()` вернёт `null`).
2. `tag_name` должен быть в формате `<version>.<buildNumber>`, т.е. совпадать с тем, что даёт
   `'${pkg.version}.${pkg.buildNumber}'`. В проекте `pubspec.yaml`: `version: 3.7.1+26` → текущая версия
   в приложении `"3.7.1.26"`, значит тег релиза — `v3.7.1.26` (допустимо и без `v`).
3. Релиз должен быть опубликован (`draft: false`), иначе `/releases/latest` его не отдаст.

> Типичная ошибка: тег `v3.7.1` при `version: 3.7.1+26`. Сравнение `3.7.1` vs `3.7.1.26` даст «не новее»,
> баннер не появится. Тег обязан содержать номер сборки.

### 2.3 Если нужен свой источник (не GitHub)

Сервис читает GitHub-специфичные поля, поэтому для собственного хостинга достаточно отдать
аналогичный JSON и поправить один метод. Пример своего ответа:

```json
{
  "version": "3.7.1.26",
  "apk_url": "https://cdn.example.com/app/dimontazh-3.7.1.26.apk",
  "apk_name": "dimontazh-3.7.1.26.apk",
  "notes": "- Исправлен расчёт потолка с нишей",
  "mandatory": false
}
```

Замена `checkLatest()` для такого ответа (сравнение, UI и скачивание не меняются):

```dart
Future<UpdateInfo?> checkLatest() async {
  try {
    final resp = await http.get(Uri.parse('https://example.com/app/version.json'));
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final version = (json['version'] as String? ?? '').trim();
    final apkUrl = json['apk_url'] as String?;
    if (version.isEmpty || apkUrl == null || apkUrl.isEmpty) return null;

    final name = (json['apk_name'] as String? ?? '').trim();
    return UpdateInfo(
      version: version,
      apkUrl: apkUrl,
      apkName: name.isNotEmpty ? name : 'update.apk',
      notes: json['notes'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}
```

Плюсы своего источника: можно отдать флаг `mandatory` (принудительное обновление), не зависеть от лимитов
GitHub и не публиковать APK в открытом репозитории.

---

## 3. Логика проверки, сравнения версий и UI-уведомление

### 3.1 Триггер проверки

Проверка запускается из `initState()` главного экрана (`HomeScreen`), т.е. **один раз за жизнь виджета**
(при запуске приложения и при повторном входе на главный экран после пересоздания виджета).

Фактический код референса (`home_screen.dart`):

```dart
Future<void> _checkForUpdate() async {
  // ВРЕМЕННО: проверяем всегда
  // final should = await _updateService.shouldCheck();
  // if (!should) return;
  await _updateService.markChecked();

  final info = await _updateService.checkLatest();
  if (info == null) return;

  // Пользователь уже откладывал эту версию?
  final skipped = await _updateService.isSkipped(info.version);
  if (skipped) return;

  // Сравниваем с текущей
  final pkg = await PackageInfo.fromPlatform();
  final current = '${pkg.version}.${pkg.buildNumber}';

  if (!_updateService.isNewer(info.version, current)) return;

  if (!mounted) return;
  setState(() => _pendingUpdate = info);
}
```

Антифлуд (`shouldCheck` — не чаще 1 раза в 24 часа) в референсе **закомментирован**: проверка идёт при каждом
старте. Для продакшена включить:

```dart
final should = await _updateService.shouldCheck();
if (!should) return;
await _updateService.markChecked();
```

Правила, заложенные в код (их нужно сохранить при переносе):

* `markChecked()` вызывается **до** сетевого запроса. Побочный эффект: неудачная проверка (офлайн) тоже
  «съедает» сутки. Если нужен повтор при появлении сети — вызывать `markChecked()` только после
  успешного `checkLatest() != null`.
* `checkLatest()` **никогда не бросает исключение**: любая ошибка / не-200 / отсутствие `.apk` → `null`
  и полное молчание для пользователя (никаких снекбаров «не удалось проверить обновления»).
* Отложенная версия (`skipVersion`) не показывается повторно. Хранится **одна** строка —
  последняя отложенная версия; после выхода новой версии баннер появится снова.
* `PackageInfo` запрашивается лениво (только после успешного ответа API), чтобы не тратить время
  при отсутствии релиза.

### 3.2 Условия показа баннера (все должны выполниться)

1. `GET /releases/latest` вернул `200`.
2. В `assets` найден файл с именем, заканчивающимся на `.apk`.
3. `info.version != skip_version` из SharedPreferences.
4. `isNewer(info.version, '<version>.<buildNumber>') == true`.
5. Виджет ещё в дереве (`mounted`), затем `setState(() => _pendingUpdate = info)`.

### 3.3 Сравнение версий

Реализация (`update_service.dart`):

```dart
/// Сравнивает две версии. true, если latest новее current.
/// Формат: «1.0.0.6» или «1.0.0+6» → берём до «+».
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
  // Убираем «v», «+build» и всё лишнее
  final clean = v.replaceFirst('v', '').split('+').first.trim();
  return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}
```

Алгоритм: строка режется по точкам на числа, отсутствующие сегменты считаются `0`, сравнение идёт
по сегментам слева направо. Сравнивать строки напрямую нельзя (`'3.10.0' < '3.9.0'` как строки, но новее как версия).

Примеры (текущая версия — `3.7.1.26`):

| latest | current | результат | причина |
|---|---|---|---|
| `v3.7.1.27` | `3.7.1.26` | обновление | 27 > 26 |
| `3.7.2` | `3.7.1.26` | обновление | 2 > 1 в 3-м сегменте |
| `3.7.1` | `3.7.1.26` | **нет** | 4-й сегмент latest = 0 < 26 |
| `3.7.1.26` | `3.7.1.26` | нет | равно |
| `3.6.9.99` | `3.7.1.26` | нет | 6 < 7 |
| `4` | `3.7.1.26` | обновление | 4 > 3 |

Ограничения текущего парсера (можно улучшить при переносе):

* `replaceFirst('v', '')` удаляет первую `v` в любом месте строки (для тега `version3.7` даст `ersion3.7`).
* Pre-release-суффиксы не поддерживаются: `1.2.0-beta` → сегмент `0-beta` → `int.tryParse` → `0`,
  т.е. `1.2.0-beta` считается равным `1.2.0`.
* Нет валидации формата: мусорный тег (`release-latest`) превратится в `[0]`, и обновление не покажется.

Более безопасный вариант парсера (совместим по поведению с текущими тегами):

```dart
List<int> _parse(String v) {
  var clean = v.trim();
  if (clean.startsWith('v') || clean.startsWith('V')) {
    clean = clean.substring(1);
  }
  clean = clean.split('+').first.split('-').first; // 1.2.3+4, 1.2.3-beta
  return clean.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
}
```

### 3.4 UI-уведомление пользователя

Реализовано как **встроенный баннер над контентом** главного экрана (не диалог и не снекбар): не блокирует
работу, но остаётся на виду, пока пользователь не обновит приложение или не нажмёт «Позже».

Компоновка (`home_screen.dart`):

```dart
Scaffold(
  body: Column(
    children: [
      if (_pendingUpdate != null) _buildUpdateBanner(context), // баннер
      Expanded(
        child: PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _index = i),
          children: _screens,
        ),
      ),
    ],
  ),
  bottomNavigationBar: /* NavigationBar */,
)
```

Внешний вид и поведение баннера:

| Элемент | Реализация |
|---|---|
| Фон | `Material(color: Color(0xFF10B981))` — фирменный зелёный |
| Статус-бар | `SafeArea(bottom: false)`, padding `EdgeInsets.fromLTRB(12, 8, 8, 8)` |
| Заголовок | `Icons.system_update_alt` (белая, 22) + `'Доступно обновление v${info.version}'` (белый, 14, w600) |
| «Позже» | `IconButton(Icons.close)`, tooltip `'Позже'`; при `_downloading` — `onPressed: null` |
| Описание | если `info.notes` не пусто: контейнер `Colors.white.withValues(alpha: 0.15)`, радиус 8, белый текст 13/1.4 |
| Кнопка | `TextButton` «Обновить»: белый фон, зелёный текст, `FontWeight.w700` |
| Прогресс | вместо кнопки при `_downloading`: `LinearProgressIndicator(value: _progress)` + `'Скачивание... ${(_progress * 100).toStringAsFixed(0)}%'` |
| Ошибка | `ScaffoldMessenger.showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')))` |

Состояния экрана:

| Состояние | Поля | UI |
|---|---|---|
| обновлений нет | `_pendingUpdate == null` | баннера нет |
| обновление найдено | `_pendingUpdate != null`, `_downloading == false` | баннер с кнопкой «Обновить» |
| идёт загрузка | `_downloading == true`, `_progress` 0…1 | прогресс-бар, крестик заблокирован |
| ошибка загрузки | `_downloading == false` | снекбар, баннер остаётся (можно повторить) |

> `withValues(alpha: …)` доступен с Flutter 3.27; в более старых версиях — `withOpacity(0.15)`.

---

## 4. Скачивание и запуск установки APK

### 4.1 Пакеты (`pubspec.yaml`)

| Пакет | Версия в `pubspec.yaml` | Фактически в `pubspec.lock` | Зачем нужен |
|---|---|---|---|
| `package_info_plus` | `^8.1.1` | 8.3.1 | текущие `version` / `buildNumber` приложения |
| `http` | `^1.2.2` | 1.6.0 | запрос релиза и потоковое скачивание APK |
| `path_provider` | `^2.1.5` | 2.1.6 | `getExternalStorageDirectory()` — каталог для APK |
| `open_filex` | `^4.6.0` | 4.7.0 | передача файла системному установщику (`Intent.ACTION_VIEW`) |
| `shared_preferences` | `^2.3.3` | — | дата последней проверки, «отложенная» версия |

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Версия приложения
  package_info_plus: ^8.1.1

  # Обновления
  http: ^1.2.2
  path_provider: ^2.1.5
  open_filex: ^4.6.0
  shared_preferences: ^2.3.3
```

Ничего, кроме этих пяти пакетов, для механизма не требуется. `flutter pub add package_info_plus http path_provider open_filex shared_preferences`.

### 4.2 Куда скачивается файл

* Каталог: `getExternalStorageDirectory()` → `/storage/emulated/0/Android/data/<applicationId>/files`
  (app-specific external storage; **разрешения на чтение/запись не нужны** на всех API 21+).
* Подкаталог: `updates`, файл — `info.apkName` (имя ассета из GitHub).
* Если файл уже существует — удаляется перед скачиванием (докачка/resume не поддерживается,
  поэтому нельзя случайно установить «половину» прошлой попытки).
* `getExternalStorageDirectory()` может вернуть `null` (редко, отдельные прошивки) — тогда бросается
  `Exception('Не удалось получить папку для скачивания')`, пользователь видит снекбар.

Почему не `getTemporaryDirectory()`: на части устройств установщик не может прочитать APK из внутреннего
кэша приложения. Внешний app-specific каталог доступен установщику через `content://`-URI FileProvider.

### 4.3 Реализация скачивания с прогрессом

Референс (`update_service.dart`), приведён с закрытием ресурсов и проверкой результата:

```dart
/// Скачивает APK во внешнюю папку приложения и открывает системный установщик.
Future<void> downloadAndInstall(
  UpdateInfo info, {
  void Function(double progress)? onProgress,
}) async {
  // Внешняя app-specific папка: путь должен попадать в разрешённые пути FileProvider
  final baseDir = await getExternalStorageDirectory();
  if (baseDir == null) {
    throw Exception('Не удалось получить папку для скачивания');
  }

  final apkDir = Directory('${baseDir.path}/updates');
  if (!await apkDir.exists()) {
    await apkDir.create(recursive: true);
  }

  final file = File('${apkDir.path}/${info.apkName}');
  if (await file.exists()) {
    await file.delete();
  }

  final client = http.Client();
  IOSink? sink;
  try {
    final req = http.Request('GET', Uri.parse(info.apkUrl));
    final resp = await client.send(req);
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
  } finally {
    await sink?.close();
    client.close();
  }
}
```

Особенности:

* Прогресс (`0.0…1.0`) отдаётся только если сервер сообщил `Content-Length` (`resp.contentLength > 0`);
  иначе индикатор остаётся на 0 %, но скачивание идёт.
* `OpenFilex.open()` возвращает `OpenResult` с `ResultType`: `done`, `fileNotFound`, `noAppToOpen`,
  `permissionDenied`, `error`. В оригинале результат игнорируется — лучше проверять (как выше), иначе
  пользователь не узнает, почему ничего не произошло.
* Загрузка выполняется в UI-изоляте: `await for` по чанкам не блокирует кадры, но `setState` на каждый чанк
  для APK на 40–60 МБ — это сотни перестроений. При желании троттлить: обновлять прогресс не чаще 1 раза
  на 1 % или через `Timer` (100 мс).
* Отмены загрузки в референсе нет. Если нужна — хранить `http.Client` и вызывать `client.close()`
  по кнопке «Отмена» (загрузка завершится исключением `ClientException`), затем удалить файл.
* Обрыв сети → исключение из `resp.stream` → пользователь видит снекбар, частичный файл будет удалён
  при следующем запуске скачивания.

### 4.4 Android: разрешения и FileProvider

**`android/app/src/main/AndroidManifest.xml` референса** (для обновлений значима только первая строка):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Для установки обновлений APK -->
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
    ...
    <application android:label="Димонтаж" android:name="${applicationName}" ...>
        ...
    </application>
</manifest>
```

`REQUEST_INSTALL_PACKAGES` (API 26+) — единственное разрешение, которое добавляет сам проект.
Без него `OpenFilex.open()` по APK завершится ошибкой (`ResultType.permissionDenied`/`error`),
а система не покажет диалог установки.

**FileProvider в манифесте проекта НЕ объявлен — и это работает.** `open_filex` 4.x сам приносит
провайдер через манифест библиотеки (manifest merging). Фактический merged-manifest release-сборки
проекта содержит:

```xml
<provider
    android:name="com.crazecoder.openfile.FileProvider"
    android:authorities="com.dimontazh.dimontazh.fileProvider.com.crazecoder.openfile"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/filepaths" />
</provider>
```

Плагин передаёт установщику `content://com.dimontazh.dimontazh.fileProvider.com.crazecoder.openfile/...`
(в Java: `FileProvider.getUriForFile(context, packageName + ".fileProvider.com.crazecoder.openfile", file)`)
и прикладывает собственный `res/xml/filepaths.xml`:

```xml
<paths>
    <external-path name="external-path" path="." />
    <external-cache-path name="external-cache-path" path="." />
    <external-files-path name="external-files-path" path="." />
    <files-path name="files_path" path="." />
    <cache-path name="cache-path" path="." />
    <root-path name="root" path="." />
</paths>
```

Каталог из п. 4.2 (`/storage/emulated/0/Android/data/<pkg>/files/updates`) попадает в
`<external-files-path path=".">` → URI выдаётся корректно. **Дополнительных правок манифеста не нужно.**

Если в новом проекте по каким-то причинам нужно объявить свой FileProvider (старая версия плагина,
свой нативный код открытия APK), добавьте в `<application>`:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileProvider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/filepaths" />
</provider>
```

и файл `android/app/src/main/res/xml/filepaths.xml` с содержимым из блока выше. Важно: **authority должен быть
уникальным** — если другой плагин уже занял `${applicationId}.fileProvider`, будет ошибка сборки
`Manifest merger failed` (лечится `tools:replace="android:authorities"` или сменой суффикса).
При использовании своего провайдера в Java/Dart-коде нужно строить URI именно с его authority.

**`INTERNET`.** В манифесте референса разрешения `INTERNET` нет, но в merged release-манифесте оно есть:
его приносят зависимости (Firebase/уведомления/прочее). В новом проекте **объявите явно**, иначе release-сборка
(где не подключается `debug/AndroidManifest.xml` с `INTERNET`) не сможет ни получить релиз, ни скачать APK:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" /> <!-- опционально -->
```

Итоговый минимум для модуля обновлений:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

**«Установка неизвестных приложений» (Android 8+).** Разрешение `REQUEST_INSTALL_PACKAGES` не выдаётся
автоматически: при первом запуске установщика система показывает экран «Разрешить установку из этого источника?».
Если пользователь откажет — установщик покажет «Приложение не установлено». Для MVP (как в референсе)
это не обрабатывается: достаточно подсказки в описании релиза/баннере.

Опционально можно заранее проверить и открыть настройки. Dart-часть:

```dart
// lib/data/services/install_permission.dart (опционально)
import 'package:flutter/services.dart';

class InstallPermission {
  static const _channel = MethodChannel('app/install');

  /// true, если приложению разрешено устанавливать APK
  static Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  /// Открыть настройки «Установка неизвестных приложений» для этого приложения
  static Future<void> openSettings() async {
    await _channel.invokeMethod<void>('openInstallSettings');
  }
}
```

Kotlin-часть (`android/app/src/main/kotlin/.../MainActivity.kt`):

```kotlin
package com.example.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "app/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            packageManager.canRequestPackageInstalls() else true
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

Тогда перед скачиванием: `if (!await InstallPermission.canInstall()) { ...подсказка + openSettings()... }`.

### 4.5 Требования к самому APK

| Требование | Почему |
|---|---|
| `applicationId` совпадает с установленным приложением | иначе Android поставит второе приложение рядом |
| Та же подпись (тот же keystore / `signingConfig`) | иначе `INSTALL_FAILED_UPDATE_INCOMPATIBLE` («Приложение не установлено») |
| `versionCode` больше установленного | Android блокирует downgrade (`INSTALL_FAILED_VERSION_DOWNGRADE`) |
| Сборка `--release` и подписана | release-APK из `flutter build apk --release` (если настроен `signingConfig`, иначе — debug-ключ, и обновление сломается при переходе на свой ключ) |
| Файл в релизе имеет расширение `.apk` | по расширению ищется ассет |

Команды сборки и проверки версии:

```bash
flutter build apk --release
# версия берётся из pubspec.yaml: version: 3.7.1+26  → versionName 3.7.1, versionCode 26
# перед публикацией версию нужно увеличить, иначе обновление не предложится
```

> Если приложение уже опубликовано в Google Play или подписано Play App Signing — установка APK,
> подписанного другим ключом, невозможна. Механизм применим только к сайдлоад-дистрибуции.

---

## 5. Пошаговый чеклист внедрения в новое приложение

Шаги 1–6 — порядок действий; полные листинги кода — в п. 5.1 (сервис) и 5.2 (экран);
справочные материалы — в п. 5.3–5.5.

### Шаг 1. Зависимости

```bash
flutter pub add package_info_plus http path_provider open_filex shared_preferences
```

Проверить в `pubspec.yaml` блок `dependencies` (см. п. 4.1).

### Шаг 2. Сервис обновлений

Создать `lib/data/repositories/update_service.dart` — полный код ниже (п. 5.1).
Заменить `defaultRepo` на `OWNER/REPO` своего репозитория релизов.

### Шаг 3. Android-манифест

В `android/app/src/main/AndroidManifest.xml` перед `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

FileProvider отдельно добавлять **не нужно** при `open_filex >= 4.6` (провайдер приходит из плагина).
Проверка: `flutter build apk --release`, затем в
`build/app/intermediates/merged_manifests/release/.../AndroidManifest.xml` найти
`REQUEST_INSTALL_PACKAGES`, `INTERNET` и `com.crazecoder.openfile.FileProvider`.

### Шаг 4. Репозиторий релизов на GitHub

1. Создать **публичный** репозиторий `OWNER/REPO-releases` (без кода, только релизы).
2. Поднять версию в `pubspec.yaml` (`version: X.Y.Z+N`), собрать `flutter build apk --release`.
3. Создать Release: тег `vX.Y.Z.N` (совпадает с `X.Y.Z.N`), приложить `.apk`, заполнить описание
   (оно станет текстом `body` → `info.notes` в баннере), опубликовать (не draft).
4. Проверить API в браузере:
   `https://api.github.com/repos/OWNER/REPO-releases/releases/latest` — должны быть `tag_name` и `assets[].browser_download_url` с `.apk`.

### Шаг 5. Интеграция в экран

Вставить в `State` главного экрана (пример — п. 5.2): поля состояния, `_checkForUpdate()` в `initState`,
`_downloadAndInstall()`, `_skipUpdate()`, баннер в `build()`.

### Шаг 6. Проверка сценариев

| # | Сценарий | Ожидаемо |
|---|---|---|
| 1 | Установлена версия N, релиз N+1 с APK | баннер «Доступно обновление vN+1», текст из `body` |
| 2 | Нажать «Обновить» | прогресс-бар, % растёт, затем системный установщик |
| 3 | Подтвердить установку | приложение обновлено, баннер исчез (перезапуск) |
| 4 | Нажать «Позже» | баннер скрыт; повторный старт — баннера нет (версия в `update_skip_version`) |
| 5 | Выйти новая версия N+2 | баннер появился снова (skip хранит только одну версию) |
| 6 | Нет сети / GitHub 404 | тишина, никаких ошибок, приложение работает |
| 7 | В релизе нет `.apk` | `checkLatest() == null`, баннера нет |
| 8 | Тег без номера сборки (`v3.7.1`) | баннера нет (см. п. 2.2) |
| 9 | Отказ в «установке из неизвестных источников» | установщик: «Приложение не установлено»; после разрешения в настройках — повтор работает |
| 10 | APK подписан другим ключом | установщик: «Приложение не установлено» (ожидаемо) |
| 11 | Прервать загрузку (свернуть/убить приложение) | при повторном запуске файл удаляется и качается заново |

Для чистого теста «Позже»: очистить данные приложения (настройки Android → Приложение → Память → Очистить)
или изменить версию в релизе.

### 5.1 Готовый код сервиса

`lib/data/repositories/update_service.dart` целиком:

```dart
// lib/data/repositories/update_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Информация о последнем релизе на GitHub.
class UpdateInfo {
  /// Версия (без «v»): например «3.7.1.26»
  final String version;

  /// Ссылка на APK-файл
  final String apkUrl;

  /// Имя APK-файла
  final String apkName;

  /// Комментарий к релизу
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.apkName,
    required this.notes,
  });
}

class UpdateService {
  /// Публичный репозиторий с релизами: OWNER/REPO
  static const String defaultRepo = 'ak3301389/dimontazh-releases';

  static const String _kLastCheck = 'update_last_check';
  static const String _kSkipVersion = 'update_skip_version';

  UpdateService({this.repo = defaultRepo});

  /// Можно переопределить в тестах или для второго окружения
  final String repo;

  String get _apiUrl => 'https://api.github.com/repos/$repo/releases/latest';

  /// Проверяет последнюю версию на GitHub.
  /// Возвращает UpdateInfo или null, если не удалось.
  Future<UpdateInfo?> checkLatest() async {
    try {
      final resp = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
      final body = json['body'] as String? ?? '';
      final assets = json['assets'] as List? ?? [];

      // Ищем APK
      String? apkUrl;
      String? apkName;
      for (final a in assets) {
        final name = a['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          apkName = name;
          break;
        }
      }
      if (apkUrl == null || apkName == null) return null;

      return UpdateInfo(
        version: tag,
        apkUrl: apkUrl,
        apkName: apkName,
        notes: body,
      );
    } catch (_) {
      return null;
    }
  }

  /// Нужно ли проверять обновление сейчас.
  /// true, если прошло больше 24 часов с последней проверки.
  Future<bool> shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastCheck) ?? 0;
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

  /// Сравнивает две версии. true, если latest новее current.
  /// Формат: «1.0.0.6» или «1.0.0+6» → берём до «+».
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
    // Убираем «v», «+build» и всё лишнее
    final clean = v.replaceFirst('v', '').split('+').first.trim();
    return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  /// Скачивает APK во внешнюю папку и открывает системный установщик.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    // Сохраняем в external app-specific папку: путь входит в filepaths.xml open_filex,
    // поэтому установщик сможет прочитать файл через content://-URI
    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) {
      throw Exception('Не удалось получить папку для скачивания');
    }

    final apkDir = Directory('${baseDir.path}/updates');
    if (!await apkDir.exists()) {
      await apkDir.create(recursive: true);
    }
    final file = File('${apkDir.path}/${info.apkName}');

    // Если файл уже есть — удаляем старый
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final resp = await client.send(req);
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

      // Открываем системный установщик
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception('Не удалось открыть установщик: ${result.message}');
      }
    } finally {
      await sink?.close();
      client.close();
    }
  }
}
```

> Отличие от оригинала: добавлены проверка `resp.statusCode`, закрытие `IOSink`/`http.Client` в `finally`
> и проверка `OpenFilex.open(...).type`. Поведение и сигнатуры совместимы с `home_screen.dart` референса.

### 5.2 Готовый код интеграции в экран

Импорты и поля `State`:

```dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/repositories/update_service.dart';

class _HomeScreenState extends State<HomeScreen> {
  // Обновления
  final UpdateService _updateService = UpdateService();
  UpdateInfo? _pendingUpdate;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _checkForUpdate(); // не await: проверка не должна задерживать первый кадр
  }
```

Методы:

```dart
  Future<void> _checkForUpdate() async {
    // Антифлуд (включить для прода): не чаще 1 раза в 24 часа
    // final should = await _updateService.shouldCheck();
    // if (!should) return;
    await _updateService.markChecked();

    final info = await _updateService.checkLatest();
    if (info == null) return;

    // Пользователь уже откладывал эту версию?
    final skipped = await _updateService.isSkipped(info.version);
    if (skipped) return;

    // Сравниваем с текущей версией приложения
    final pkg = await PackageInfo.fromPlatform();
    final current = '${pkg.version}.${pkg.buildNumber}';

    if (!_updateService.isNewer(info.version, current)) return;

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
```

Подключение баннера в `build()` (верх `Column` над `PageView`):

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_pendingUpdate != null) _buildUpdateBanner(context),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _index = i),
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: /* NavigationBar — как в вашем экране */ null,
    );
  }
```

Сам баннер (`_buildUpdateBanner`) — полный код из референса:

```dart
  Widget _buildUpdateBanner(BuildContext context) {
    final info = _pendingUpdate!;

    return Material(
      color: const Color(0xFF10B981),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update_alt,
                      color: Colors.white, size: 22),
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
                      foregroundColor: const Color(0xFF10B981),
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
      ),
    );
  }
```

Если баннер не нужен на всех вкладках — можно показывать его только на «Настройках»/«Главной»
или заменить на `showDialog`, но тогда проверку нужно запускать после `WidgetsBinding.instance.addPostFrameCallback`,
чтобы не показать диалог до первой отрисовки.

### 5.3 Частые ошибки

| Симптом | Причина | Решение |
|---|---|---|
| Установщик: «Приложение не установлено» | APK подписан другим ключом / другой `applicationId` | собирать релиз тем же keystore и с тем же `applicationId` |
| Установщик: «Приложение не установлено», `versionCode` меньше | в `pubspec.yaml` не подняли `+N` | `version: 3.7.2+27` перед сборкой |
| Нажали «Обновить» — ничего не происходит | нет `REQUEST_INSTALL_PACKAGES` **или** пользователь запретил установку из неизвестных источников | добавить permission; разрешить установку в настройках; проверять `OpenResult.type` |
| `ResultType.permissionDenied` | нет разрешения на установку из этого источника | показать инструкцию/открыть `ACTION_MANAGE_UNKNOWN_APP_SOURCES` |
| `ResultType.fileNotFound` / `FileUriExposedException` | файл лежит вне путей `filepaths.xml` FileProvider | качать в `getExternalStorageDirectory()/updates` (см. п. 4.2) |
| Баннер не появляется | тег без номера сборки, релиз в draft, в релизе нет `.apk`, версия уже в `update_skip_version` | см. п. 2.2, 3.2 |
| Баннер появляется всегда | закомментирован `shouldCheck` (так в референсе) | включить антифлуд 24 ч |
| API вернул 403 | исчерпан лимит GitHub (60 запросов/час на IP) | включить `shouldCheck` / свой эндпоинт |
| В release-сборке не работает проверка/скачивание | нет `INTERNET` в основном манифесте | объявить явно (п. 4.4) |
| Ошибка компиляции `dart:io` / `getExternalStorageDirectory` на web | механизм использует `dart:io` и Android-плагины | вынести за `if (!kIsWeb && Platform.isAndroid)` или не поддерживать web |
| APK скачивается 0 % и сразу установщик | сервер не отдаёт `Content-Length` (редирект/CDN) | это не ошибка: прогресс просто не отображается |

### 5.4 Опциональные доработки (не входят в референс)

1. **Принудительное обновление**: добавить в JSON флаг `mandatory`; если `true` — не показывать крестик
   и блокировать работу (`onPressed: null` у «Позже», либо полноэкранный диалог).
2. **Проверка целостности APK**: GitHub отдаёт в ассетах поле `digest` (`sha256:...`), можно сверить
   SHA-256 скачанного файла через пакет `crypto` (уже есть в проекте) до вызова `OpenFilex.open`.
3. **Отмена загрузки**: хранить `http.Client` в поле, по кнопке «Отмена» — `client.close()` + удалить файл.
4. **Ручная проверка из «Настроек»**: вызвать `checkLatest()` + `isNewer()` по нажатию, игнорируя `isSkipped`,
   и показать результат снекбаром («У вас последняя версия»).
5. **Троттлинг прогресса**: обновлять `_progress` не чаще 1 раза на 1 % (меньше перестроений UI).
6. **Логи**: писать ошибки `checkLatest`/скачивания в общий логгер проекта (в референсе ошибки глотаются).

### 5.5 Короткий чеклист для приёмки

- [ ] в `pubspec.yaml` есть `package_info_plus`, `http`, `path_provider`, `open_filex`, `shared_preferences`
- [ ] создан `lib/data/repositories/update_service.dart` с актуальным `defaultRepo`
- [ ] в `AndroidManifest.xml` есть `INTERNET` и `REQUEST_INSTALL_PACKAGES`
- [ ] FileProvider присутствует в merged-манифесте (приходит из `open_filex`)
- [ ] версия в `pubspec.yaml` поднимается перед каждым релизом (`X.Y.Z+N`)
- [ ] тег релиза на GitHub = `vX.Y.Z.N`, к релизу приложен `.apk`, релиз опубликован
- [ ] баннер появляется, «Обновить» скачивает с прогрессом и открывает установщик
- [ ] «Позже» скрывает версию до следующего релиза
- [ ] офлайн/404 не ломают приложение и не показывают ошибок
- [ ] release-APK ставится поверх старой версии без «Приложение не установлено»
- [ ] (прод) включён `shouldCheck()` (24 ч) или свой эндпоинт вместо GitHub API

---

## 6. Итог: что именно переносить

1. **Источник данных** — публичный GitHub-репозиторий релизов; API `GET /repos/OWNER/REPO/releases/latest`;
   поля `tag_name` (версия, формат `X.Y.Z.N`), `body` (текст «что нового»), `assets[].name` (`.apk`),
   `assets[].browser_download_url` (ссылка).
2. **Логика** — проверка при старте главного экрана (+ антифлуд 24 ч через SharedPreferences),
   сравнение версий по числовым сегментам с текущей `'${version}.${buildNumber}'`,
   показ немодального баннера над контентом с кнопками «Обновить»/«Позже» и прогресс-баром.
3. **Установка** — `http` стримит APK в `getExternalStorageDirectory()/updates`, затем
   `OpenFilex.open()` открывает системный установщик; нужен `REQUEST_INSTALL_PACKAGES`, FileProvider
   приходит из `open_filex`, APK должен быть подписан тем же ключом и иметь больший `versionCode`.
