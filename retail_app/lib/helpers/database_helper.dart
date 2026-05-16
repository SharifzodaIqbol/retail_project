import 'dart:convert';
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
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Таблица для чеков, которые не смогли отправиться
    await db.execute('''
      CREATE TABLE offline_sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_data TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }

  // Сохранить чек, если нет интернета
  Future<void> insertOfflineSale(Map<String, dynamic> saleData) async {
    final db = await instance.database;
    await db.insert('offline_sales', {
      'sale_data': jsonEncode(saleData),
      'is_synced': 0,
    });
  }

  // Получить все неотправленные чеки
  Future<List<Map<String, dynamic>>> getUnsyncedSales() async {
    final db = await instance.database;
    return await db.query('offline_sales', where: 'is_synced = 0');
  }

  // Пометить чек как отправленный
  Future<void> markSaleAsSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'offline_sales',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
