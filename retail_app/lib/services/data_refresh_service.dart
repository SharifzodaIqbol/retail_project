import 'dart:async';
import 'package:flutter/material.dart';

/// Сервис для автоматического обновления данных (#4).
/// Виджеты подписываются на нужные события и получают уведомление.
///
/// Использование:
/// DataRefreshService.instance.onSaleAdded.listen((_) => _loadHistory());
class DataRefreshService {
  DataRefreshService._();
  static final instance = DataRefreshService._();

  final _saleController = StreamController<void>.broadcast();
  final _productController = StreamController<void>.broadcast();
  final _usersController = StreamController<void>.broadcast();
  final _analyticsController = StreamController<void>.broadcast();
  final _sessionController = StreamController<String>.broadcast();

  /// Слушать обновления продаж
  Stream<void> get onSaleChanged => _saleController.stream;

  /// Слушать обновления товаров
  Stream<void> get onProductChanged => _productController.stream;

  /// Слушать обновления сотрудников
  Stream<void> get onUsersChanged => _usersController.stream;

  Stream<void> get onAnalyticsChanged => _analyticsController.stream;

  /// Срабатывает, когда сервер сообщил, что JWT-токен невалиден/истёк
  /// (401 на любом запросе — см. ApiService._handleAuthErrors). Несёт
  /// человекочитаемое сообщение, которое экран входа покажет продавцу,
  /// чтобы было понятно, ПОЧЕМУ его вдруг вернуло на вход, а не оставлять
  /// гадать (токен живёт 24 часа, см. backend/internal/auth/jwt.go —
  /// раньше это выглядело как случайный "Неверный токен" посреди работы
  /// без какого-либо объяснения и без выхода из тупика).
  Stream<String> get onSessionExpired => _sessionController.stream;

  /// Вызвать после успешной продажи
  void notifySaleChanged() => _saleController.add(null);

  /// Вызвать после изменения товара
  void notifyProductChanged() => _productController.add(null);

  /// Вызвать после изменения пользователей
  void notifyUsersChanged() => _usersController.add(null);

  void notifyAnalyticsChanged() => _analyticsController.add(null);

  void notifySessionExpired(String message) => _sessionController.add(message);

  void dispose() {
    _saleController.close();
    _productController.close();
    _usersController.close();
    _analyticsController.close();
    _sessionController.close();
  }
}

mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _sub;

  /// Поток для подписки. Переопределите в своём State.
  Stream<void> get refreshStream;

  /// Метод загрузки данных. Переопределите в своём State.
  Future<void> loadData();

  @override
  void initState() {
    super.initState();
    loadData();
    _sub = refreshStream.listen((_) {
      if (mounted) loadData();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
