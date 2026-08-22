import 'dart:async';

class SaleRejectionService {
  SaleRejectionService._();
  static final instance = SaleRejectionService._();

  final _controller = StreamController<String>.broadcast();

  /// Текст ошибки от сервера для каждого отклонённого в фоне чека.
  Stream<String> get onSaleRejected => _controller.stream;

  void notifyRejected(String errorMessage) => _controller.add(errorMessage);

  void dispose() => _controller.close();
}
