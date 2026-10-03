import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/cup_mark.dart';

/// Full-screen lockout shown when the mobile application is put under
/// maintenance from the QuickBrew Website Admin Portal.
///
/// Prevents user interactions, custom orders, or cart updates until the admin
/// unlocks the system.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({
    super.key,
    required this.message,
    this.onRefresh,
    this.onAdminBypass,
  });

  final String message;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onAdminBypass;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _glowCtrl;

  // Stagger offsets for entrance animation
  late final Animation<double> _badgeFade;
  late final Animation<Offset> _badgeSlide;
  late final Animation<double> _cupFade;
  late final Animation<double> _cupScale;
  late final Animation<double> _headlineFade;
  late final Animation<Offset> _headlineSlide;
  late final Animation<double> _messageFade;
  late final Animation<Offset> _messageSlide;
  late final Animation<double> _buttonFade;
  late final Animation<Offset> _buttonSlide;
  late final Animation<double> _bypassFade;

  bool _refreshPressed = false;
  bool _bypassPressed = false;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // Badge: 0.0 → 0.25
    _badgeFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
    );
    _badgeSlide = Tween<Offset>(
      begin: const Offset(0, -12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOutCubic),
    ));

    // Cup: 0.1 → 0.45
    _cupFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.1, 0.45, curve: Curves.easeOut),
    );
    _cupScale = Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.1, 0.5, curve: Curves.elasticOut),
    ));

    // Headline: 0.25 → 0.55
    _headlineFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.25, 0.55, curve: Curves.easeOut),
    );
    _headlineSlide = Tween<Offset>(
      begin: const Offset(0, 16),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.25, 0.6, curve: Curves.easeOutCubic),
    ));

    // Message: 0.35 → 0.65
    _messageFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    );
    _messageSlide = Tween<Offset>(
      begin: const Offset(0, 16),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.35, 0.7, curve: Curves.easeOutCubic),
    ));

    // Button: 0.55 → 0.85
    _buttonFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
    );
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 20),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.55, 0.9, curve: Curves.easeOutCubic),
    ));

    // Bypass: 0.7 → 1.0
    _bypassFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    if (reduced) {
      _entranceCtrl.value = 1.0;
      _pulseCtrl.stop();
      _glowCtrl.stop();
    }

    return PopScope(
      canPop: false,
      child: BrewBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // ── Frosted Status Badge ──
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: _badgeSlide.value,
                    child: Opacity(
                      opacity: _badgeFade.value,
                      child: child,
                    ),
                  ),
                  child: _buildStatusBadge(reduced),
                ),

                const SizedBox(height: 36),

                // ── Illuminated Cup Medallion ──
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) => Transform.scale(
                    scale: _cupScale.value,
                    child: Opacity(
                      opacity: _cupFade.value,
                      child: child,
                    ),
                  ),
                  child: _buildCupMedallion(reduced),
                ),

                const SizedBox(height: 36),

                // ── Headline ──
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: _headlineSlide.value,
                    child: Opacity(
                      opacity: _headlineFade.value,
                      child: child,
                    ),
                  ),
                  child: Text(
                    'Service Paused',
                    textAlign: TextAlign.center,
                    style: BrewType.display.copyWith(
                      fontSize: 34,
                      height: 1.1,
                      color: BrewColor.mark,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Shimmer divider ──
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) => Opacity(
                    opacity: _headlineFade.value,
                    child: child,
                  ),
                  child: Container(
                    width: 48,
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          BrewColor.cream.withValues(alpha: 0.0),
                          BrewColor.cream.withValues(alpha: 0.4),
                          BrewColor.cream.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Message ──
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: _messageSlide.value,
                    child: Opacity(
                      opacity: _messageFade.value,
                      child: child,
                    ),
                  ),
                  child: _buildMessageCard(),
                ),

                const Spacer(flex: 3),

                // ── Refresh button ──
                if (widget.onRefresh != null)
                  AnimatedBuilder(
                    animation: _entranceCtrl,
                    builder: (context, child) => Transform.translate(
                      offset: _buttonSlide.value,
                      child: Opacity(
                        opacity: _buttonFade.value,
                        child: child,
                      ),
                    ),
                    child: _buildRefreshButton(reduced),
                  ),

                // ── Admin bypass ──
                if (widget.onAdminBypass != null) ...[
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _entranceCtrl,
                    builder: (context, child) => Opacity(
                      opacity: _bypassFade.value,
                      child: child,
                    ),
                    child: _buildBypassLink(reduced),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Status Badge ─────────────────────────────────────────────────────

  Widget _buildStatusBadge(bool reduced) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: BrewColor.alert.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: BrewColor.alert.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing dot
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final pulse = reduced ? 1.0 : _pulseCtrl.value;
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BrewColor.alert.withValues(
                        alpha: 0.6 + 0.4 * pulse,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: BrewColor.alert.withValues(
                            alpha: 0.3 + 0.4 * pulse,
                          ),
                          blurRadius: 6 + 6 * pulse,
                          spreadRadius: 1 + 2 * pulse,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(
                'MAINTENANCE IN PROGRESS',
                style: BrewType.mono.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: BrewColor.alert,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Cup Medallion ────────────────────────────────────────────────────

  Widget _buildCupMedallion(bool reduced) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        final glow = reduced ? 0.5 : _glowCtrl.value;
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: BrewColor.alert.withValues(alpha: 0.15 + 0.15 * glow),
              width: 1.5,
            ),
            boxShadow: [
              // Inner warm glow
              BoxShadow(
                color: BrewColor.alert.withValues(alpha: 0.08 + 0.12 * glow),
                blurRadius: 30 + 20 * glow,
                spreadRadius: 2 + 4 * glow,
              ),
              // Outer ambient glow
              BoxShadow(
                color: BrewColor.sage.withValues(alpha: 0.06 + 0.06 * glow),
                blurRadius: 50,
                spreadRadius: 8,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrewColor.field.withValues(alpha: 0.55),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  BrewColor.cream.withValues(alpha: 0.06),
                  BrewColor.field.withValues(alpha: 0.4),
                ],
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: const CupMark(dimension: 56, progress: 0.5),
          ),
        ),
      ),
    );
  }

  // ─── Message Card ─────────────────────────────────────────────────────

  Widget _buildMessageCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: BrewColor.cream.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: BrewType.body.copyWith(
              fontSize: 15,
              height: 1.6,
              color: BrewColor.rowInk,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Refresh Button ───────────────────────────────────────────────────

  Widget _buildRefreshButton(bool reduced) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _refreshPressed = true),
      onTapUp: (_) {
        setState(() => _refreshPressed = false);
        HapticFeedback.lightImpact();
        widget.onRefresh?.call();
      },
      onTapCancel: () => setState(() => _refreshPressed = false),
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        transform: Matrix4.translationValues(
          0.0, _refreshPressed ? 1.0 : 0.0, 0.0,
        ),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _refreshPressed
              ? BrewColor.darken(BrewColor.cream, 0.08)
              : BrewColor.cream,
          boxShadow: [
            BoxShadow(
              color: BrewColor.cream.withValues(
                alpha: _refreshPressed ? 0.08 : 0.18,
              ),
              blurRadius: _refreshPressed ? 8 : 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'Check If Back Online',
          style: BrewType.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: BrewColor.darkField,
          ),
        ),
      ),
    );
  }

  // ─── Admin Bypass Link ────────────────────────────────────────────────

  Widget _buildBypassLink(bool reduced) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _bypassPressed = true),
      onTapUp: (_) {
        setState(() => _bypassPressed = false);
        HapticFeedback.selectionClick();
        widget.onAdminBypass?.call();
      },
      onTapCancel: () => setState(() => _bypassPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _bypassPressed
              ? BrewColor.cream.withValues(alpha: 0.06)
              : BrewColor.cream.withValues(alpha: 0.0),
          border: Border.all(
            color: _bypassPressed
                ? BrewColor.cream.withValues(alpha: 0.2)
                : BrewColor.cream.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Text(
          'Staff & Admin Sign In',
          style: BrewType.mono.copyWith(
            fontSize: 11.5,
            letterSpacing: 0.8,
            color: BrewColor.cream.withValues(
              alpha: _bypassPressed ? 0.85 : 0.55,
            ),
          ),
        ),
      ),
    );
  }
}
