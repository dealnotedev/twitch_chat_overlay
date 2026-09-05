import 'package:flutter/widgets.dart';

/// Reveals a newly received row without changing its layout height.
class ChatMessageEntrance extends StatefulWidget {
  const ChatMessageEntrance({
    required this.elapsed,
    required this.child,
    super.key,
  });

  static const duration = Duration(milliseconds: 240);

  /// Time since this item entered the UI; null means pre-existing history.
  final Duration? elapsed;
  final Widget child;

  @override
  State<ChatMessageEntrance> createState() => _ChatMessageEntranceState();
}

class _ChatMessageEntranceState extends State<ChatMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final elapsed = widget.elapsed;
    _controller = AnimationController(
      vsync: this,
      duration: ChatMessageEntrance.duration,
      value: elapsed == null
          ? 1
          : (elapsed.inMicroseconds /
                    ChatMessageEntrance.duration.inMicroseconds)
                .clamp(0.0, 1.0),
    );
    _progress = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
    } else if (!_started && _controller.value < 1) {
      _controller.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 10 * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
