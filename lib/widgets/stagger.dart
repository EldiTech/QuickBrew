import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Drives the landing screen's entrance: items 60ms apart, each rising 12px
/// while fading in over 260ms, in DOM order.
///
/// Under reduced motion every item shares one 260ms opacity ramp — no offset,
/// no translation.
class StaggerGroup extends StatefulWidget {
  const StaggerGroup({
    super.key,
    required this.itemCount,
    required this.reveal,
    required this.reduced,
    required this.child,
  });

  final int itemCount;

  /// Flip to true to play the entrance.
  final bool reveal;

  final bool reduced;
  final Widget child;

  @override
  State<StaggerGroup> createState() => _StaggerGroupState();
}

class _StaggerGroupState extends State<StaggerGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration get _total => widget.reduced
      ? BrewMotion.staggerItem
      : BrewMotion.staggerStep * (widget.itemCount - 1) + BrewMotion.staggerItem;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);
    if (widget.reveal) _controller.forward();
  }

  @override
  void didUpdateWidget(StaggerGroup old) {
    super.didUpdateWidget(old);
    _controller.duration = _total;
    if (widget.reveal && !old.reveal) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StaggerScope(
      progress: _controller,
      reduced: widget.reduced,
      totalMs: _total.inMilliseconds,
      child: widget.child,
    );
  }
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({
    required this.progress,
    required this.reduced,
    required this.totalMs,
    required super.child,
  });

  final Animation<double> progress;
  final bool reduced;
  final int totalMs;

  static _StaggerScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StaggerScope>();
    assert(scope != null, 'StaggerItem must sit under a StaggerGroup');
    return scope!;
  }

  @override
  bool updateShouldNotify(_StaggerScope old) =>
      progress != old.progress ||
      reduced != old.reduced ||
      totalMs != old.totalMs;
}

/// One staggered element. [index] is its position in DOM order.
///
/// Rides the group's timeline when it is mounted in time to, and plays the same
/// 260ms ramp on its own when it is not — see [_StaggerItemState._late]. Either
/// way an element that appears on one of these screens fades and rises; nothing
/// arrives by simply being there on a frame it was not there on the frame before.
class StaggerItem extends StatefulWidget {
  const StaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem>
    with SingleTickerProviderStateMixin {
  /// This item's own entrance, for when the group's has already been spent.
  ///
  /// Null in the ordinary case, which is an item mounted with the rest of its
  /// screen: it rides [_StaggerScope.progress] and this stays unused.
  ///
  /// It exists because half the content on the signed-in screens does not exist
  /// when the screen does. A menu board, an orders history, the active-order
  /// card, a roster — each arrives from Firestore a round trip after the group
  /// started, and the group's controller has very often already reached 1 by
  /// then: the shortest of these timelines is the menu's 440ms, against a cold
  /// read that routinely takes longer. Riding a finished timeline means
  /// `window.transform(1)`, which is 1 — full opacity, no rise, on the first
  /// frame. The rows *popped*, and they popped on the screens where the reader
  /// is watching for exactly the content that popped.
  ///
  /// So an item that finds the group already past its own cue plays the identical
  /// ramp itself instead. The group is deliberately not restarted: rewinding it
  /// would re-run the entrance for the masthead and the headline the reader has
  /// been looking at for a second, every single time a snapshot lands.
  AnimationController? _late;

  /// Whether the ride-or-play question has been asked. Asked once, on the first
  /// build: [didChangeDependencies] runs again whenever the group's item count
  /// changes, and an item already riding the timeline must not switch horses
  /// halfway.
  bool _settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    _settled = true;

    final scope = _StaggerScope.of(context);
    // Under reduced motion the group holds every item on one opacity ramp with
    // no offset, and a late arrival is simply already at the end of it.
    if (scope.reduced) return;

    // Strictly past, not at: on the first frame of a fresh group both sides are
    // 0 for index 0, and that item is riding the timeline it is the start of.
    if (scope.progress.value <= _startFraction(scope)) return;

    _late = AnimationController(vsync: this, duration: BrewMotion.staggerItem)
      ..forward();
  }

  @override
  void dispose() {
    _late?.dispose();
    super.dispose();
  }

  /// Where this item's ramp begins inside the group's timeline, 0..1.
  double _startFraction(_StaggerScope scope) =>
      (widget.index * BrewMotion.staggerStep.inMilliseconds) / scope.totalMs;

  @override
  Widget build(BuildContext context) {
    final scope = _StaggerScope.of(context);
    final late = _late;

    if (late != null) {
      return AnimatedBuilder(
        animation: late,
        child: widget.child,
        builder: (context, child) => _rise(
          Curves.easeOutCubic.transform(late.value),
          child,
        ),
      );
    }

    final startMs =
        scope.reduced ? 0 : widget.index * BrewMotion.staggerStep.inMilliseconds;
    final endMs = startMs + BrewMotion.staggerItem.inMilliseconds;
    final window = Interval(
      startMs / scope.totalMs,
      endMs / scope.totalMs,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: scope.progress,
      child: widget.child,
      builder: (context, child) {
        final t = window.transform(scope.progress.value.clamp(0.0, 1.0));
        if (scope.reduced) return Opacity(opacity: t, child: child);
        return _rise(t, child);
      },
    );
  }

  /// The entrance itself, stated once so a late arrival and a group member are
  /// the same 12px rise under the same fade rather than two things that merely
  /// look alike.
  Widget _rise(double t, Widget? child) => Opacity(
    opacity: t.clamp(0.0, 1.0),
    child: Transform.translate(
      offset: Offset(0, (1 - t) * BrewMotion.staggerRise),
      child: child,
    ),
  );
}
