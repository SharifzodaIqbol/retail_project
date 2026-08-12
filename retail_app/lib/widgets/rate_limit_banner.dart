import 'dart:async';
import 'package:flutter/material.dart';

/// Показывает баннер с обратным отсчётом "Подождите MM:SS" после
/// срабатывания rate limit (см. backend internal/ratelimit). Сам считает
/// секунды локально и вызывает [onExpired], когда время вышло — экран,
/// который использует виджет, в этот момент должен снова разрешить попытки.
class RateLimitBanner extends StatefulWidget {
  final int initialSeconds;
  final String message;
  final VoidCallback? onExpired;

  const RateLimitBanner({
    Key? key,
    required this.initialSeconds,
    required this.message,
    this.onExpired,
  }) : super(key: key);

  @override
  State<RateLimitBanner> createState() => _RateLimitBannerState();
}

class _RateLimitBannerState extends State<RateLimitBanner> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.initialSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft <= 1) {
          _secondsLeft = 0;
          timer.cancel();
          widget.onExpired?.call();
        } else {
          _secondsLeft -= 1;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5C6C2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_clock_rounded,
            color: Color(0xFFC0392B),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message,
                  style: const TextStyle(
                    color: Color(0xFFC0392B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Такрор кунед баъд аз $_formatted',
                  style: const TextStyle(
                    color: Color(0xFFC0392B),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Возвращает true, пока пользователь заблокирован (есть оставшееся время) —
/// удобно для условия disabled у кнопки/клавиатуры.
bool isRateLimited(int? secondsLeft) => secondsLeft != null && secondsLeft > 0;
