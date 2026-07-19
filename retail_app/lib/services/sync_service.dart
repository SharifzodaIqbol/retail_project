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
    // Важно: getUnsyncedSales отдаёт только 'pending' — чеки, уже
    // помеченные 'failed' в прошлый раз (сервер отклонил их бизнес-
    // ошибкой, например "недостаточно товара"), сюда не попадают и не
    // будут молча повторяться на каждом тике этого сервиса.
    final unsynced = await _db.getUnsyncedSales();
    if (unsynced.isEmpty) return;

    int successCount = 0;
    int rejectedCount = 0;

    for (final row in unsynced) {
      // Если связь пропала посреди пачки — прекращаем, остальное
      // досинхронизируется при следующем восстановлении связи.
      if (!ConnectivityService.instance.isOnline) break;

      final saleData = jsonDecode(row['sale_data']);
      final result = await _api.createSaleFromRawData(saleData);

      if (result.isSuccess) {
        await _db.markSaleAsSynced(row['id']);
        successCount++;
      } else if (result.isRejected) {
        // Сервер ответил и отклонил чек по существу (например, к моменту
        // синхронизации на складе физически не хватило остатка — другой
        // продавец успел продать последнее). Повторная идентичная отправка
        // даст ту же ошибку, поэтому помечаем чек 'failed' и НЕ ретраим
        // его молча на каждом тике — иначе именно он и будет вечно
        // "стучаться" в сервер с одной и той же ошибкой в логах.
        await _db.markSaleAsFailed(
          row['id'],
          result.errorMessage ?? 'Сервер чекро рад кард',
        );
        rejectedCount++;
      }
      // networkError — оставляем чек 'pending' как есть и просто идём
      // дальше по очереди; он естественно попадёт в следующий цикл
      // синхронизации. Не прерываем всю очередь целиком: иначе один
      // "плохой" или временно недоступный чек будет вечно блокировать
      // синхронизацию всех остальных, честных чеков, идущих следом.
    }

    if (successCount > 0) {
      DataRefreshService.instance.notifySaleChanged();
      DataRefreshService.instance.notifyProductChanged();
      _notifyUser('☁️ Квитансияҳо ҳамоҳанг карда шудаанд: $successCount');
    }

    if (rejectedCount > 0) {
      // Раньше об этом не сообщалось вообще. Теперь владелец/продавец
      // сразу видит, что часть чеков требует его внимания (например,
      // нужно пополнить остатки), а не бесконечно тихо копится в логах
      // сервера как повторяющаяся ошибка "недостаточно товара".
      _notifyUser(
        '⚠️ $rejectedCount чек(ҳо) рад карда шуд — санҷед тафсилот',
        color: Colors.red,
      );
    }

    // Раз в сессию подчищаем старые синхронизированные чеки, чтобы
    // локальная БД не росла бесконечно. 'failed' сюда не попадают — они
    // ждут явного решения человека (обновить остатки/удалить/повторить).
    await _db.cleanupSyncedSales();
  }

  /// Ненавязчивое уведомление о фоновой синхронизации.
  /// Продавец не должен ничего делать руками — это просто индикатор,
  /// что чеки, пробитые офлайн, успешно долетели до сервера (или, при
  /// [color] красном — что часть чеков требует его внимания).
  void _notifyUser(String message, {Color color = Colors.blue}) {
    final context = ApiService.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }
}
