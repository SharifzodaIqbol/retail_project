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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Офлайн-чеки (была в v1)
    await db.execute('''
      CREATE TABLE offline_sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_data TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        is_synced INTEGER DEFAULT 0
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
  }

  // ─── Офлайн-чеки ─────────────────────────────────────────────────────────

  Future<void> insertOfflineSale(Map<String, dynamic> saleData) async {
    final db = await instance.database;
    await db.insert('offline_sales', {
      'sale_data': jsonEncode(saleData),
      'is_synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSales() async {
    final db = await instance.database;
    return await db.query('offline_sales', where: 'is_synced = 0');
  }

  Future<void> markSaleAsSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'offline_sales',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаляет синхронизированные чеки старше [days] дней, чтобы БД не росла.
  Future<void> cleanupSyncedSales({int days = 30}) async {
    final db = await instance.database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
        1000;
    await db.delete(
      'offline_sales',
      where: 'is_synced = 1 AND created_at < ?',
      whereArgs: [cutoff],
    );
  }

  // ─── Кэш товаров ─────────────────────────────────────────────────────────

  /// Полностью заменяет кэш товаров (вызывать после успешного getAllProducts).
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    final db = await instance.database;
    final batch = db.batch();
    batch.delete('product_cache');
    for (final p in products) {
      batch.insert('product_cache', {
        'id': p['id'],
        'name': p['name'],
        'barcode': p['barcode'] ?? '',
        'buy_price': (p['buy_price'] as num?)?.toDouble() ?? 0.0,
        'sell_price': (p['sell_price'] as num?)?.toDouble() ?? 0.0,
        'stock': (p['stock'] as num?)?.toDouble() ?? 0.0,
        'unit': p['unit'] ?? 'шт',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Возвращает все товары из кэша.
  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final db = await instance.database;
    return await db.query('product_cache', orderBy: 'name ASC');
  }

  /// Ищет товар по штрихкоду в кэше.
  Future<Map<String, dynamic>?> getCachedProductByBarcode(
    String barcode,
  ) async {
    final db = await instance.database;
    final rows = await db.query(
      'product_cache',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Поиск товара по названию (LIKE) в кэше.
  Future<List<Map<String, dynamic>>> searchCachedProductsByName(
    String query,
  ) async {
    final db = await instance.database;
    return await db.query(
      'product_cache',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
      limit: 10,
    );
  }

  // ─── Кэш пользователей терминала ─────────────────────────────────────────

  /// Сохраняет список продавцов. PIN-хэш вычисляется здесь же, если передан.
  Future<void> cacheTerminalUsers(List<Map<String, dynamic>> users) async {
    final db = await instance.database;
    final batch = db.batch();
    batch.delete('terminal_users');
    for (final u in users) {
      batch.insert('terminal_users', {
        'id': u['id'],
        'username': u['username'] ?? '',
        'role': u['role'] ?? 'seller',
        'pin_hash': null, // PIN хранится только после успешного входа
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
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
