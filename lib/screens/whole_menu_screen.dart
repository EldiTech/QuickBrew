import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_transitions.dart';
import 'store_landing_screen.dart';

/// Full-screen high-resolution viewer for whole menu boards (posters).
///
/// Backed dynamically by Firestore via `shops/{shopId}/whole_menu`, with offline
/// asset fallbacks when Firestore has not yet been populated. Features smooth
/// multi-board switching, pinch-to-zoom, pan, and double-tap zoom.
class WholeMenuViewerScreen extends StatefulWidget {
  const WholeMenuViewerScreen({
    super.key,
    required this.shop,
    this.counter,
    this.session,
    this.initialBoardIndex = 0,
  });

  final BrewShop shop;
  final BrewCounter? counter;
  final BrewSession? session;
  final int initialBoardIndex;

  static Route<void> route({
    required BrewShop shop,
    BrewCounter? counter,
    BrewSession? session,
    int initialBoardIndex = 0,
  }) {
    return brewPageRoute<void>(
      child: WholeMenuViewerScreen(
        shop: shop,
        counter: counter,
        session: session,
        initialBoardIndex: initialBoardIndex,
      ),
    );
  }

  @override
  State<WholeMenuViewerScreen> createState() => _WholeMenuViewerScreenState();
}

class _WholeMenuViewerScreenState extends State<WholeMenuViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  final TransformationController _transformController =
      TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialBoardIndex;
    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
        )..addListener(() {
          if (_zoomAnimation != null) {
            _transformController.value = _zoomAnimation!.value;
          }
        });
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _zoomToMatrix(Matrix4.identity());
  }

  void _zoomToMatrix(Matrix4 target) {
    _zoomAnimation =
        Matrix4Tween(begin: _transformController.value, end: target).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward(from: 0);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    if (currentScale > 1.2) {
      _zoomToMatrix(Matrix4.identity());
    } else {
      final position = details.localPosition;
      final target = Matrix4.identity()
        ..storage[0] = 2.5
        ..storage[5] = 2.5
        ..storage[10] = 1.0
        ..storage[12] = -position.dx * 1.5
        ..storage[13] = -position.dy * 1.5;
      _zoomToMatrix(target);
    }
  }

  void _goToStore(BuildContext context) {
    Navigator.of(context).push(
      StoreLandingScreen.route(
        shop: widget.shop,
        session: widget.session,
        counter: widget.counter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top;
    final bottomPadding = math.max(media.padding.bottom, 16.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BrewColor.field,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF07140D),
        body: BrewBackground(
          child: StreamBuilder<List<BrewWholeMenuBoard>>(
            stream: widget.counter?.wholeMenu(widget.shop.partner),
            initialData: BrewWholeMenuBoard.defaultsFor(widget.shop.partner),
            builder: (context, snapshot) {
              final boards = snapshot.data ?? const [];

              if (boards.isEmpty) {
                return _buildEmptyState(context, topPadding, bottomPadding);
              }

              final safeIndex = _currentIndex.clamp(0, boards.length - 1);
              final activeBoard = boards[safeIndex];

              return Stack(
                children: [
                  // Full interactive viewer area
                  Positioned.fill(
                    child: GestureDetector(
                      onDoubleTapDown: _onDoubleTapDown,
                      onDoubleTap: () {},
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 1.0,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(40),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: topPadding + 64,
                              bottom: bottomPadding + 80,
                              left: 12,
                              right: 12,
                            ),
                            child: _buildBoardImage(activeBoard),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top bar header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildHeader(context, topPadding, boards, safeIndex),
                  ),

                  // Bottom toolbar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(
                      context,
                      bottomPadding,
                      activeBoard,
                      boards.length,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBoardImage(BrewWholeMenuBoard board) {
    if (board.imageBytes != null && board.imageBytes!.isNotEmpty) {
      return _fitBoardImage(
        board,
        Image.memory(
          board.imageBytes!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) =>
              _buildImageErrorPlaceholder(),
        ),
      );
    }

    if (board.assetPath != null && board.assetPath!.isNotEmpty) {
      return _fitBoardImage(
        board,
        Image.asset(
          board.assetPath!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) =>
              _buildImageErrorPlaceholder(),
        ),
      );
    }

    return _buildImageErrorPlaceholder();
  }

  Widget _fitBoardImage(BrewWholeMenuBoard board, Widget image) {
    return AspectRatio(
      aspectRatio: board.aspectRatio ?? (1024 / 511),
      child: SizedBox(width: double.infinity, child: image),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0x33102419),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrewColor.hairline),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              size: 48,
              color: BrewColor.cream,
            ),
            const SizedBox(height: 12),
            Text(
              'Board image unavailable',
              style: BrewType.mono.copyWith(color: BrewColor.cream),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    double topPadding,
    List<BrewWholeMenuBoard> boards,
    int activeIndex,
  ) {
    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 8,
        bottom: 12,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xF207140D),
            const Color(0xD907140D),
            Colors.transparent,
          ],
          stops: const [0.0, 0.75, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Close button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x33132B1E),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.15),
                        width: 1.0,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: BrewColor.cream,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Shop info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.shop.displayName,
                      style: BrewType.title.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BrewColor.cream,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Whole Menu Board',
                      style: BrewType.mono.copyWith(
                        fontSize: 11,
                        color: const Color(0xFFD4A373),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              // Reset zoom button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _resetZoom,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x33132B1E),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.15),
                        width: 1.0,
                      ),
                    ),
                    child: const Icon(
                      Icons.zoom_out_map_rounded,
                      size: 18,
                      color: BrewColor.cream,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Board tabs switcher if multiple boards exist
          if (boards.length > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (final (idx, board) in boards.indexed) ...[
                    if (idx > 0) const SizedBox(width: 8),
                    _BoardTabChip(
                      label: board.title,
                      selected: idx == activeIndex,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _resetZoom();
                        setState(() => _currentIndex = idx);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    double bottomPadding,
    BrewWholeMenuBoard activeBoard,
    int totalBoards,
  ) {
    return Container(
      padding: EdgeInsets.only(
        top: 14,
        bottom: bottomPadding + 6,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xF207140D),
            const Color(0xD907140D),
            Colors.transparent,
          ],
          stops: const [0.0, 0.75, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeBoard.title,
                      style: BrewType.rowTitle.copyWith(
                        fontSize: 13.5,
                        color: BrewColor.cream,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeBoard.description ??
                          'Pinch or double-tap to zoom in',
                      style: BrewType.rowBody.copyWith(
                        fontSize: 11,
                        color: BrewColor.cream.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // "Order now" button to jump into store catalog
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _goToStore(context),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x33487A5E),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0x66487A5E),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Order Drink',
                          style: BrewType.mono.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: BrewColor.cream,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: BrewColor.cream,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    double topPadding,
    double bottomPadding,
  ) {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding,
          bottom: bottomPadding,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33102419),
                border: Border.all(color: BrewColor.hairline),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 32,
                color: Color(0xFFD4A373),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No Menu Boards Available',
              style: BrewType.displayAt(20).copyWith(color: BrewColor.cream),
            ),
            const SizedBox(height: 8),
            Text(
              'This shop has not uploaded whole menu poster boards yet.',
              textAlign: TextAlign.center,
              style: BrewType.rowBody.copyWith(
                color: BrewColor.cream.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0x33487A5E),
                foregroundColor: BrewColor.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Back to Shops'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardTabChip extends StatelessWidget {
  const _BoardTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
          decoration: BoxDecoration(
            color: selected ? const Color(0x40D4A373) : const Color(0x1F132B1E),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4A373)
                  : BrewColor.cream.withValues(alpha: 0.15),
              width: selected ? 1.2 : 0.9,
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x33D4A373), blurRadius: 8)]
                : null,
          ),
          child: Text(
            label,
            style: BrewType.mono.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? const Color(0xFFE2C4A2) : BrewColor.cream,
            ),
          ),
        ),
      ),
    );
  }
}
