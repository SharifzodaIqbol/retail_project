import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../helpers/database_helper.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import 'data_refresh_service.dart';

/// Глобальный менеджер синхронизации офлайн-данных.
///
/// Раньше синхронизация неотправленных чеков запускалась только в
/// `initState()` экрана "Касса" — а этот экран создаётся один раз за
/// сессию (живёт внутри IndexedStack) и не пересоздаётся при
/// переключении вкладок. Поэтому если продавец уходил в офлайн,
/// пробивал чеки, а потом связь возвращалась, чеки "зависали" в
/// очереди до перезапуска приложения.
///
/// Этот сервис живёт на уровне всего приложения (запускается один раз
/// в main()) и реагирует на реальное восстановление связи, а не на
/// жизненный цикл конкретного экрана — так продавец вообще не должен
/// замечать, что был офлайн: как только сеть появилась, чеки и каталог
/// сами досинхронизируются в фоне.
class SyncService {
  SyncService._();
  static final instance = SyncService._();

  final _api = ApiService();
  final _db = DatabaseHelper.instance;

  StreamSubscription? _connectivitySub;
  Timer? _fallbackTimer;
  bool _isSyncing = false;
  bool _started = false;

  /// Запускать один раз при старте приложения (после ConnectivityService.init()).
  void start() {
    if (_started) return;
    _started = true;

    // Сразу пробуем синхронизировать то, что накопилось с прошлой сессии.
    syncNow();

    // Основной триггер: реальное восстановление сети — полная
    // синхронизация, включая обновление каталога.
    _connectivitySub = ConnectivityService.instance.onConnectionRestored.listen(
      (_) => syncNow(),
    );

    // Подстраховка на случай, если плагин connectivity_plus не заметит
    // смену сети (бывает на некоторых Android-прошивках). Здесь
    // синхронизируем только чеки — это дешёвая операция (сеть
    // тратится только если реально есть что отправить), а не гоняем
    // полный каталог по сети каждые 45 секунд без нужды.
    _fallbackTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _syncSalesOnly();
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _fallbackTimer?.cancel();
    _started = false;
  }

  /// Полная синхронизация: неотправленные чеки + офлайн-кэш каталога.
  /// Вызывается при старте приложения и при восстановлении связи.
  /// Безопасно вызывать многократно — параллельные вызовы игнорируются.
  Future<void> syncNow() async {
    if (_isSyncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    _isSyncing = true;
    try {
      await _syncOfflineSales();
      // Обновляем полный офлайн-каталог, чтобы кэш не отставал от склада
      // и порядок товаров совпадал с онлайн-режимом.
      await _api.refreshOfflineCache();
    } finally {
      _isSyncing = false;
    }
  }

  /// Лёгкая версия для периодической подстраховки — только чеки, без
  /// полного обхода каталога по сети (чтобы не тратить трафик и батарею
  /// впустую каждые 45 секунд).
  Future<void> _syncSalesOnly() async {
    if (_isSyncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    _isSyncing = true;
    try {
      await _syncOfflineSales();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncOfflineSales() async {
    final unsynced = await _db.getUnsyncedSales();
    if (unsynced.isEmpty) return;

    int successCount = 0;
    for (final row in unsynced) {
      // Если связь пропала посреди пачки — прекращаем, остальное
      // досинхронизируется при следующем восстановлении связи.
      if (!ConnectivityService.instance.isOnline) break;

      final saleData = jsonDecode(row['sale_data']);
      final success = await _api.createSaleFromRawData(saleData);
      if (success) {
        await _db.markSaleAsSynced(row['id']);
        successCount++;
      }
      // Если конкретный чек не прошёл (например, к моменту синхронизации
      // на складе физически не хватило остатка — другой продавец успел
      // продать последнее) — НЕ прерываем всю очередь. Иначе один
      // "плохой" чек будет вечно блокировать синхронизацию всех
      // остальных, честных чеков, идущих следом. Просто переходим к
      // следующему; несинхронизированный чек останется в очереди и
      // будет виден владельцу (см. предупреждение в ответе).
    }

    if (successCount > 0) {
      DataRefreshService.instance.notifySaleChanged();
      DataRefreshService.instance.notifyProductChanged();
      _notifyUser('☁️ Квитансияҳо ҳамоҳанг карда шудаанд: $successCount');
    }

    // Раз в сессию подчищаем старые синхронизированные чеки, чтобы
    // локальная БД не росла бесконечно.
    await _db.cleanupSyncedSales();
  }

  /// Ненавязчивое уведомление о фоновой синхронизации.
  /// Продавец не должен ничего делать руками — это просто индикатор,
  /// что чеки, пробитые офлайн, успешно долетели до сервера.
  void _notifyUser(String message) {
    final context = ApiService.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.blue),
    );
  }
}
