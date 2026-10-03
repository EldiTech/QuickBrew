import 'package:flutter/widgets.dart';

/// Full-screen ambient background displaying the branded coffee background
/// image with the warm dark gradient scrim that guarantees legibility and
/// high contrast across all screens.
class BrewBackground extends StatelessWidget {
  const BrewBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/login_bg.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x5508170F),
                  Color(0x88050F0A),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
