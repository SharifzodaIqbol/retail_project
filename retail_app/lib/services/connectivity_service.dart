import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  static const String _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const _fastProbe = Duration(seconds: 4);
  static const _slowProbe = Duration(seconds: 20);

  final _connectivity = Connectivity();
  final _onlineController = StreamController<void>.broadcast();
  StreamSubscription? _sub;
  Timer? _probeTimer;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Поток восстановления сети (срабатывает один раз при каждом переходе офлайн→онлайн).
  Stream<void> get onConnectionRestored => _onlineController.stream;

  /// Запустить мониторинг. Вызывать один раз в main() или в _Bootstrapper.initState().
  Future<void> init() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(result) && await _canReachServer();

    _sub = _connectivity.onConnectivityChanged.listen((result) async {
      if (!_hasConnection(result)) {
        _isOnline = false;
        _rescheduleProbe();
        return;
      }
      final wasOffline = !_isOnline;
      final reachable = await _canReachServer();
      _isOnline = reachable;
      if (wasOffline && reachable) {
        _onlineController.add(null);
      }
      _rescheduleProbe();
    });

    _rescheduleProbe();
  }

  /// Немедленно помечает соединение как отсутствующее. Вызывается из
  /// api_service сразу при неудаче реального сетевого запроса, чтобы
  /// следующий же запрос (следующий символ в поиске, следующий скан
  /// штрихкода) сразу шёл в локальный кэш, а не снова ждал таймаут.
  /// Периодический пробник сам подтвердит фактическое восстановление,
  /// когда оно произойдёт — здесь мы только ускоряем реакцию на обрыв.
  void markOffline() {
    if (!_isOnline) return;
    _isOnline = false;
    _rescheduleProbe();
  }

  /// Планирует следующую проверку связи. Интервал зависит от текущего
  /// состояния: пока офлайн — проверяем чаще, чтобы быстрее заметить
  /// восстановление сети (частые обрывы в мобильных сетях).
  void _rescheduleProbe() {
    _probeTimer?.cancel();
    _probeTimer = Timer(_isOnline ? _slowProbe : _fastProbe, () async {
      final result = await _connectivity.checkConnectivity();
      if (!_hasConnection(result)) {
        _isOnline = false;
        _rescheduleProbe();
        return;
      }
      final wasOffline = !_isOnline;
      final reachable = await _canReachServer();
      _isOnline = reachable;
      if (wasOffline && reachable) {
        _onlineController.add(null);
      }
      _rescheduleProbe();
    });
  }

  /// Лёгкая проверка реальной достижимости бэкенда. Короткий таймаут —
  /// это внутренняя проверка состояния сети, а не пользовательский
  /// запрос, поэтому она не должна ощутимо задерживать интерфейс, даже
  /// если сервер недоступен.
  Future<bool> _canReachServer() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
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
    _probeTimer?.cancel();
    _onlineController.close();
  }
}
