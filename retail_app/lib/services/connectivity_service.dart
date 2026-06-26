import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Следит за состоянием сети и уведомляет подписчиков.
/// При восстановлении соединения вызываются все зарегистрированные
/// обратные вызовы (например, синхронизация офлайн-чеков).
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _onlineController = StreamController<void>.broadcast();
  StreamSubscription? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Поток восстановления сети (срабатывает один раз при каждом переходе офлайн→онлайн).
  Stream<void> get onConnectionRestored => _onlineController.stream;

  /// Запустить мониторинг. Вызывать один раз в main() или в _Bootstrapper.initState().
  Future<void> init() async {
    // Проверяем текущее состояние
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(result);

    // Подписываемся на изменения
    _sub = _connectivity.onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = _hasConnection(result);

      if (wasOffline && _isOnline) {
        // Переход офлайн → онлайн
        _onlineController.add(null);
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );
  }

  void dispose() {
    _sub?.cancel();
    _onlineController.close();
  }
}
