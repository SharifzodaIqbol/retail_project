import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    final dbPath = kIsWeb ? filePath : join(await getDatabasesPath(), filePath);
    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Офлайн-чеки (была в v1).
    // status: 'pending' (ждёт отправки/повтора) | 'synced' (успешно ушёл на
    // сервер) | 'failed' (сервер отклонил чек бизнес-ошибкой — например,
    // недостаточно товара на складе — и повторная отправка без вмешательства
    // человека не имеет смысла, поэтому такие чеки НЕ ретраятся автоматически).
    // is_synced оставлен для обратной совместимости со старым кодом/данными,
    // но новый код должен ориентироваться на status.
    await db.execute('''
      CREATE TABLE offline_sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_data TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        is_synced INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        last_error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Кэш товаров
    await db.execute('''
      CREATE TABLE product_cache(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL,
        buy_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        stock REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'шт',
        cached_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_product_barcode ON product_cache(barcode)',
    );

    // Кэш пользователей терминала (продавцы)
    await db.execute('''
      CREATE TABLE terminal_users(
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        role TEXT NOT NULL,
        pin_hash TEXT,
        cached_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Миграция с v1: добавляем недостающие таблицы и колонки
      await db
          .execute(
            "ALTER TABLE offline_sales ADD COLUMN created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))",
          )
          .catchError((_) {}); // игнорируем если колонка уже есть

      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_cache(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          barcode TEXT NOT NULL,
          buy_price REAL NOT NULL,
          sell_price REAL NOT NULL,
          stock REAL NOT NULL,
          unit TEXT NOT NULL DEFAULT 'шт',
          cached_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_barcode ON product_cache(barcode)',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS terminal_users(
          id INTEGER PRIMARY KEY,
          username TEXT NOT NULL,
          role TEXT NOT NULL,
          pin_hash TEXT,
          cached_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
      ''');
    }

    if (oldVersion < 3) {
      // Раньше offline_sales знала только "синхронизирован / нет"
      // (is_synced 0/1). Из-за этого чек, отклонённый сервером бизнес-
      // ошибкой (например, "недостаточно товара ID: 12"), было невозможно
      // отличить от чека, не отправленного из-за реального обрыва сети —
      // оба выглядели как is_synced = 0 и оба вечно попадали в повторную
      // отправку (см. getUnsyncedSales/_syncOfflineSales), заново падая с
      // той же ошибкой при каждом запуске приложения, без единого
      // сообщения об этом пользователю.
      //
      // status разводит эти два случая: 'pending' по-прежнему ретраится
      // автоматически, а 'failed' — нет, и ждёт решения человека (обновить
      // остатки, отредактировать чек или удалить его).
      await db
          .execute(
            "ALTER TABLE offline_sales ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
          )
          .catchError((_) {});
      await db
          .execute('ALTER TABLE offline_sales ADD COLUMN last_error TEXT')
          .catchError((_) {});
      await db
          .execute(
            'ALTER TABLE offline_sales ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
          )
          .catchError((_) {});

      // Существующие уже синхронизированные чеки (is_synced = 1) помечаем
      // как synced, чтобы они не попали под getUnsyncedSales/pending-выборки.
      await db.execute(
        "UPDATE offline_sales SET status = 'synced' WHERE is_synced = 1",
      );
    }
  }

  // ─── Офлайн-чеки ─────────────────────────────────────────────────────────

  Future<void> insertOfflineSale(Map<String, dynamic> saleData) async {
    final db = await instance.database;
    await db.insert('offline_sales', {
      'sale_data': jsonEncode(saleData),
      'is_synced': 0,
      'status': 'pending',
    });
  }

  /// Чеки, которые ещё стоит пытаться отправить автоматически. НЕ включает
  /// 'failed' — те отклонены сервером бизнес-ошибкой и не уйдут сами по
  /// себе от повторной идентичной попытки.
  Future<List<Map<String, dynamic>>> getUnsyncedSales() async {
    final db = await instance.database;
    return await db.query('offline_sales', where: "status = 'pending'");
  }

  /// Чеки, которые сервер отклонил окончательно (нужно решение человека:
  /// обновить остатки, отредактировать или удалить чек).
  Future<List<Map<String, dynamic>>> getFailedSales() async {
    final db = await instance.database;
    return await db.query(
      'offline_sales',
      where: "status = 'failed'",
      orderBy: 'created_at DESC',
    );
  }

  Future<void> markSaleAsSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'offline_sales',
      {'is_synced': 1, 'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Помечает чек как отклонённый сервером бизнес-ошибкой (не сетевой
  /// сбой) — такой чек больше не участвует в автоматических повторах.
  Future<void> markSaleAsFailed(int id, String error) async {
    final db = await instance.database;
    await db.update(
      'offline_sales',
      {'status': 'failed', 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Увеличивает счётчик неудачных сетевых попыток, не меняя статус —
  /// чек остаётся 'pending' и будет повторён снова.
  Future<void> incrementRetryCount(int id) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE offline_sales SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  /// Удаляет один чек из очереди (например, по решению пользователя — если
  /// он признан ошибочным/дублем и отправлять его больше не нужно).
  Future<void> deleteOfflineSale(int id) async {
    final db = await instance.database;
    await db.delete('offline_sales', where: 'id = ?', whereArgs: [id]);
  }

  /// Возвращает чек обратно в очередь на отправку (например, после того как
  /// пользователь пополнил остатки товара и хочет повторить попытку вручную).
  Future<void> retryFailedSale(int id) async {
    final db = await instance.database;
    await db.update(
      'offline_sales',
      {'status': 'pending', 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаляет синхронизированные чеки старше [days] дней, чтобы БД не росла.
  /// 'failed' сюда не попадают — они ждут явного решения пользователя.
  Future<void> cleanupSyncedSales({int days = 30}) async {
    final db = await instance.database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
        1000;
    await db.delete(
      'offline_sales',
      where: "status = 'synced' AND created_at < ?",
      whereArgs: [cutoff],
    );
  }

  // ─── Кэш товаров ─────────────────────────────────────────────────────────
  //
  // Раньше поиск товара (`searchCachedProductsByName`) и поиск по
  // штрихкоду (`getCachedProductByBarcode`) при каждом вызове шли в
  // sqflite: platform channel в нативный поток + `LIKE '%...%'` без
  // индекса (полное построчное сканирование таблицы). При наборе текста
  // в кассе это дёргалось на каждую букву. На слабых Android-аппаратах
  // (а именно такие массово используются в рознице в Таджикистане) это
  // давало заметные подтормаживания офлайн-поиска — независимо от того,
  // как быстро определяется сам факт "нет сети".
  //
  // Каталог небольшого/среднего магазина обычно — от пары сотен до
  // нескольких тысяч позиций, что комфортно помещается в память
  // процесса. Поэтому держим read-through копию каталога в памяти и
  // ищем по ней в чистом Dart (без похода в БД и без сканирования) —
  // это на порядки быстрее, чем SQL LIKE через platform channel.
  // SQLite остаётся источником истины: данные переживают перезапуск
  // приложения, а в память подгружаются один раз лениво при первом
  // обращении.
  List<Map<String, dynamic>>? _memProducts; // null = ещё не загружен из БД
  final Map<String, Map<String, dynamic>> _memByBarcode = {};

  Future<void> _ensureMemLoaded() async {
    if (_memProducts != null) return;
    final db = await instance.database;
    _memProducts = await db.query('product_cache');
    _rebuildBarcodeIndex();
  }

  void _rebuildBarcodeIndex() {
    _memByBarcode.clear();
    for (final p in _memProducts ?? const <Map<String, dynamic>>[]) {
      final barcode = p['barcode'] as String? ?? '';
      if (barcode.isNotEmpty) _memByBarcode[barcode] = p;
    }
  }

  Map<String, dynamic> _normalizeProduct(Map<String, dynamic> p) => {
    'id': p['id'],
    'name': p['name'],
    'barcode': p['barcode'] ?? '',
    'buy_price': (p['buy_price'] as num?)?.toDouble() ?? 0.0,
    'sell_price': (p['sell_price'] as num?)?.toDouble() ?? 0.0,
    'stock': (p['stock'] as num?)?.toDouble() ?? 0.0,
    'unit': p['unit'] ?? 'шт',
  };

  /// Полностью заменяет кэш товаров (вызывать после успешного getAllProducts).
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    final db = await instance.database;
    final batch = db.batch();
    batch.delete('product_cache');
    final normalized = <Map<String, dynamic>>[];
    for (final p in products) {
      final row = _normalizeProduct(p);
      normalized.add(row);
      batch.insert(
        'product_cache',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    // Полная пересборка каталога — обновляем и in-memory копию целиком,
    // чтобы следующий поиск сразу видел актуальные данные.
    _memProducts = normalized;
    _rebuildBarcodeIndex();
  }

  /// Обновляет в кэше только переданные товары, не трогая остальной
  /// каталог. Используется при обычном онлайн-просмотре одной страницы
  /// склада — раньше такой просмотр по ошибке ПОЛНОСТЬЮ перезаписывал
  /// кэш этой единственной страницей (см. [cacheProducts]), из-за чего
  /// офлайн-каталог "худел" до последней открытой страницы и порядок
  /// товаров переставал совпадать с онлайном. Полную пересборку кэша
  /// (со сверкой состава и порядка) делает [cacheProducts].
  Future<void> upsertCachedProducts(List<Map<String, dynamic>> products) async {
    if (products.isEmpty) return;
    await _ensureMemLoaded();

    final db = await instance.database;
    final batch = db.batch();
    for (final p in products) {
      final row = _normalizeProduct(p);
      batch.insert(
        'product_cache',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final idx = _memProducts!.indexWhere((e) => e['id'] == row['id']);
      if (idx >= 0) {
        _memProducts![idx] = row;
      } else {
        _memProducts!.add(row);
      }
    }
    await batch.commit(noResult: true);
    _rebuildBarcodeIndex();
  }

  /// Возвращает все товары из кэша.
  ///
  /// Важно: порядок должен совпадать с тем, что отдаёт сервер в онлайне
  /// (ORDER BY stock ASC на бэкенде), иначе список на складе выглядит
  /// "перемешанным" при переходе в офлайн. `id ASC` вторым ключом даёт
  /// стабильный порядок при одинаковом остатке (как обычно и получается
  /// в Postgres при равенстве значений сортировки).
  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    await _ensureMemLoaded();
    final list = List<Map<String, dynamic>>.from(_memProducts!);
    list.sort((a, b) {
      final stockCmp = (a['stock'] as num).compareTo(b['stock'] as num);
      if (stockCmp != 0) return stockCmp;
      return (a['id'] as num).compareTo(b['id'] as num);
    });
    return list;
  }

  /// Ищет товар по штрихкоду в кэше. O(1) по in-memory индексу вместо
  /// похода в sqflite на каждый скан.
  Future<Map<String, dynamic>?> getCachedProductByBarcode(
    String barcode,
  ) async {
    await _ensureMemLoaded();
    return _memByBarcode[barcode];
  }

  /// Поиск товара по названию в кэше — линейный проход по in-memory
  /// списку в чистом Dart. Для каталога в несколько тысяч позиций это
  /// занимает доли миллисекунды и не требует индекса, в отличие от
  /// SQL `LIKE '%...%'`, который в принципе не может использовать
  /// индекс (значение ищется в середине строки).
  Future<List<Map<String, dynamic>>> searchCachedProductsByName(
    String query,
  ) async {
    await _ensureMemLoaded();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final matches =
        _memProducts!
            .where((p) => (p['name'] as String).toLowerCase().contains(q))
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    return matches.take(10).toList();
  }

  // ─── Кэш пользователей терминала ─────────────────────────────────────────

  /// Сохраняет список продавцов, не трогая уже сохранённые PIN-хэши.
  ///
  /// Раньше метод полностью пересоздавал таблицу (delete + insert), что
  /// обнуляло pin_hash для ВСЕХ продавцов при каждом обновлении списка —
  /// включая тех, кто уже успешно логинился и должен иметь возможность
  /// зайти по PIN офлайн. Из-за этого офлайн-вход мог "неожиданно"
  /// переставать работать, стоило списку продавцов обновиться ещё раз
  /// (например, при фоновой синхронизации). Теперь существующие
  /// продавцы обновляются точечно (без изменения pin_hash), новые —
  /// добавляются с пустым pin_hash, а уволенные/удалённые на сервере —
  /// убираются из кэша.
  Future<void> cacheTerminalUsers(List<Map<String, dynamic>> users) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final u in users) {
        final id = u['id'];
        final existing = await txn.query(
          'terminal_users',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('terminal_users', {
            'id': id,
            'username': u['username'] ?? '',
            'role': u['role'] ?? 'seller',
            'pin_hash': null, // PIN появится после первого успешного входа
          });
        } else {
          await txn.update(
            'terminal_users',
            {'username': u['username'] ?? '', 'role': u['role'] ?? 'seller'},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // Убираем из кэша тех, кого больше нет в свежем списке с сервера.
      final ids = users.map((u) => u['id']).toList();
      if (ids.isEmpty) {
        await txn.delete('terminal_users');
      } else {
        final placeholders = List.filled(ids.length, '?').join(',');
        await txn.delete(
          'terminal_users',
          where: 'id NOT IN ($placeholders)',
          whereArgs: ids,
        );
      }
    });
  }

  /// Сохраняет хэш PIN после успешного входа — для офлайн-проверки.
  Future<void> savePinHash(int userId, String pin) async {
    final db = await instance.database;
    final hash = _hashPin(pin);
    await db.update(
      'terminal_users',
      {'pin_hash': hash},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Возвращает всех пользователей терминала из кэша.
  Future<List<Map<String, dynamic>>> getCachedTerminalUsers() async {
    final db = await instance.database;
    return await db.query('terminal_users', orderBy: 'username ASC');
  }

  /// Проверяет PIN офлайн. Возвращает данные пользователя или null.
  Future<Map<String, dynamic>?> verifyPinOffline(int userId, String pin) async {
    final db = await instance.database;
    final rows = await db.query(
      'terminal_users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final user = rows.first;
    final storedHash = user['pin_hash'] as String?;
    if (storedHash == null) return null; // PIN никогда не кэшировался
    if (storedHash == _hashPin(pin)) return user;
    return null;
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin + '_pos_salt_2026');
    return sha256.convert(bytes).toString();
  }
}
