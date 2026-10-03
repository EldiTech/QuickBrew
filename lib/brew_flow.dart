import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'screens/landing_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/tokens.dart';
import 'widgets/cup_mark.dart';

enum _Phase { extracting, transit, landed }

/// Owns the handover from splash to landing.
///
/// The cup is a genuine shared element: it is drawn exactly once, and during
/// the flight it is lifted into an overlay above both screens and interpolated
/// between the two measured slots. There is no cross-fade of two cups, because
/// there is only ever one cup.
class BrewFlow extends StatefulWidget {
  const BrewFlow({
    super.key,
    this.onGetStarted,
    this.onCreateAccount,
    this.onLanded,
    this.startLanded = false,
  });

  final VoidCallback? onGetStarted;
  final VoidCallback? onCreateAccount;

  /// Fired once the cup is down and the landing screen begins its entrance.
  ///
  /// This is what lets the app hand a returning reader straight to their home
  /// screen without cutting the splash short. At the instant it fires, every
  /// landing element is still at opacity zero and the cup is sitting in exactly
  /// the slot the home screen's own cup occupies — so a home screen faded in on
  /// this callback replaces nothing the reader can see, and the mark does not
  /// move. Firing it any earlier would mean interrupting the extraction; any
  /// later, and the landing copy the reader has no business seeing would have
  /// faded up first.
  final VoidCallback? onLanded;

  /// Skips the splash and opens on the landing screen, already revealed.
  ///
  /// For coming *back*: logging out should not replay a two-and-a-half second
  /// brand animation. The splash earns its time once per launch.
  final bool startLanded;

  @override
  State<BrewFlow> createState() => _BrewFlowState();
}

class _BrewFlowState extends State<BrewFlow> with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _splashSlotKey = GlobalKey();
  final _landingSlotKey = GlobalKey();

  /// One controller for all three splash beats; the windows below carve it up.
  late final AnimationController _extract = AnimationController(
    vsync: this,
    duration: BrewMotion.splashRun,
  )..addStatusListener(_onExtractStatus);

  static const _fadeWindow = Interval(0, BrewMotion.fadeEnd, curve: Curves.easeOut);
  static const _drawWindow = Interval(
    BrewMotion.fadeEnd,
    BrewMotion.drawEnd,
    curve: Curves.easeInOut,
  );
  static const _fillWindow = Interval(
    BrewMotion.drawEnd,
    1,
    curve: BrewMotion.extractionCurve,
  );

  late final AnimationController _handover = AnimationController(
    vsync: this,
    duration: BrewMotion.transit,
  )..addStatusListener(_onHandoverStatus);

  _Phase _phase = _Phase.extracting;
  bool _reveal = false;
  bool _reduced = false;
  bool _sequenced = false;
  Rect? _from;
  Rect? _to;
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sequenced) return;
    _sequenced = true;
    _reduced = MediaQuery.disableAnimationsOf(context);

    if (widget.startLanded) {
      // Straight to the landed state: cup full, splash gone, entrance playing.
      // The callback goes out after this frame rather than during it, because
      // whoever is listening will call setState and we are inside a build.
      _extract.value = 1;
      _handover.value = 1;
      _phase = _Phase.landed;
      _reveal = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLanded?.call();
      });
      return;
    }

    if (_reduced) {
      // Cup renders pre-filled, splash holds, then hands over on opacity alone.
      _extract.value = 1;
      _handover.duration = BrewMotion.staggerItem;
      _hold = Timer(BrewMotion.reducedHold, _land);
    } else {
      _extract.forward();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _extract.dispose();
    _handover.dispose();
    super.dispose();
  }

  void _onExtractStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _reduced || !mounted) return;
    _beginTransit();
  }

  void _onHandoverStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _reduced || !mounted) return;
    _land();
  }

  void _beginTransit() {
    _from = _slotRect(_splashSlotKey);
    _to = _slotRect(_landingSlotKey);
    if (_from == null || _to == null) {
      // Nothing measurable to fly between; hand over without the travel.
      _land();
      return;
    }
    setState(() => _phase = _Phase.transit);
    _handover.forward();
  }

  /// The cup has arrived. Everything else staggers in behind it.
  void _land() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.landed;
      _reveal = true;
    });
    if (!_handover.isAnimating && _handover.value < 1) _handover.forward();
    widget.onLanded?.call();
  }

  /// A slot's rect in the coordinate space of the overlay stack.
  Rect? _slotRect(GlobalKey key) {
    final slot = key.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (slot is! RenderBox || stack is! RenderBox) return null;
    if (!slot.hasSize || !stack.hasSize) return null;
    return slot.localToGlobal(Offset.zero, ancestor: stack) & slot.size;
  }

  /// The brief fixes both screens at viewport height with no scrolling. That
  /// holds up to 1.3x system text; beyond it the bottom group is pushed off the
  /// screen and Sign in becomes unreachable. Capping the scale is the lesser
  /// harm compared with an unreachable primary action, but it does mean readers
  /// who set text above 130% do not get it — see the note in the summary.
  static const _maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScale),
      ),
      child: _buildChrome(),
    );
  }

  Widget _buildChrome() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BrewColor.field,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_extract, _handover]),
        builder: (context, _) => _buildStack(),
      ),
    );
  }

  Widget _buildStack() {
    final beat = _extract.value;
    final fill = _fillWindow.transform(beat);
    final splashOpacity = _fadeWindow.transform(beat) *
        (1 - Curves.easeOut.transform(_handover.value));
    final flying = _phase == _Phase.transit && !_reduced;

    return Stack(
      key: _stackKey,
      fit: StackFit.expand,
      children: [
        // The landing screen is mounted from the first frame so its cup slot can
        // be measured, which means it is invisible but present. Keep it out of
        // the semantics tree until it lands, or a screen reader reads out "Sign
        // in" while the splash is still covering the screen.
        // AbsorbPointer on the splash stops touches, but not focus traversal: a
        // keyboard user could otherwise tab to Sign in and activate it while
        // the splash still covers the screen.
        ExcludeFocus(
          excluding: !_reveal,
          child: ExcludeSemantics(
            excluding: !_reveal,
            child: LandingScreen(
              cupSlotKey: _landingSlotKey,
              // Under reduced motion the cup never travels, so it simply sits
              // in its landed slot from the start.
              showCupInSlot: _reduced || _phase == _Phase.landed,
              reveal: _reveal,
              reduced: _reduced,
              onGetStarted: widget.onGetStarted,
              onCreateAccount: widget.onCreateAccount,
            ),
          ),
        ),
        // Non-interactive and non-dismissible: this absorbs rather than ignores,
        // so nothing reaches the landing controls sitting underneath it.
        if (_phase != _Phase.landed || splashOpacity > 0)
          AbsorbPointer(
            child: Opacity(
              opacity: splashOpacity,
              child: SplashScreen(
                progress: fill,
                strokeProgress: _drawWindow.transform(beat),
                cupSlotKey: _splashSlotKey,
                showCupInSlot: _reduced || _phase == _Phase.extracting,
              ),
            ),
          ),
        if (flying) _flyingCup(),
      ],
    );
  }

  Widget _flyingCup() {
    final t = BrewMotion.transitCurve.transform(_handover.value);
    final rect = Rect.lerp(_from!, _to!, t)!;

    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: CupMark(
          dimension: rect.width,
          progress: 1,
          strokeWidth: BrewMotion.cupSplashStroke +
              (BrewMotion.cupLandingStroke - BrewMotion.cupSplashStroke) * t,
        ),
      ),
    );
  }
}
