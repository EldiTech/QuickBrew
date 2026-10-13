import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/shop_mark.dart';
import 'category_menu_screen.dart';
import 'order_wizard_screen.dart';

/// Screen 2 of the visual design: The Store Landing Page.
///
/// Features:
/// - Hero banner with back button, seamlessly blended with the ambient background
/// - Shop information (name, subtitle, OPEN status, location, hours)
/// - Interactive tab pills (Menu, About, Photos, Reviews)
/// - 3-column "MENU CATEGORIES" grid (derived from live menu with fallback)
/// - "Try our Best Seller!" Dirty Avalanche promo card with direct ordering action
/// - Rich About, Photos, and Reviews sections for the tabs
/// - Floating bottom cart bar ("View Cart ₱96.00")
class StoreLandingScreen extends StatefulWidget {
  const StoreLandingScreen({
    super.key,
    required this.shop,
    this.session,
    this.counter,
  });

  final BrewShop shop;
  final BrewSession? session;
  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewShop shop,
    BrewSession? session,
    BrewCounter? counter,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          StoreLandingScreen(shop: shop, session: session, counter: counter),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
    );
  }

  @override
  State<StoreLandingScreen> createState() => _StoreLandingScreenState();
}

class _StoreLandingScreenState extends State<StoreLandingScreen> {
  int _selectedTab = 0;
  int _photosPage = 0;
  static const _photosPageSize = 6;
  StreamSubscription<List<BrewMenuItem>>? _menuSubscription;
  List<BrewMenuItem> _menuItems = const [];
  static const _tabs = ['Menu', 'About', 'Photos', 'Reviews'];

  int get _safeSelectedTab {
    final t = (_selectedTab as dynamic);
    return t is int ? t : 0;
  }

  int get _safePhotosPage {
    final p = (_photosPage as dynamic);
    return p is int ? p : 0;
  }

  static const _defaultCategories = [
    'Cà Phê Series',
    'Iced Blended',
    'Milk Tea',
    'Fresh Lemonade',
    'Refresher',
    'Add Ons',
  ];

  static const _defaultMenuItems = [
    BrewMenuItem(
      id: 'pour_over',
      name: 'Barista Pour-Over Station',
      category: 'Cà Phê Series',
      description: 'Crafted with precision Ethiopian and single-origin beans',
      sizePrices: {BrewItemSize.medium: 8500, BrewItemSize.large: 9500},
    ),
    BrewMenuItem(
      id: 'dirty_avalanche',
      name: 'Signature Dirty Avalanche',
      category: 'Iced Blended',
      description: 'Rich espresso layered over chilled artisan cream and cocoa',
      sizePrices: {BrewItemSize.medium: 8000, BrewItemSize.large: 9000},
    ),
    BrewMenuItem(
      id: 'java_frappe',
      name: 'Java Frappe',
      category: 'Iced Blended',
      description: 'Smooth coffee frappe with rich mocha drizzle',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'fruit_refreshers',
      name: 'Fresh Fruit Refreshers',
      category: 'Refresher',
      description: 'Handcrafted with real passion fruit, strawberries and mint',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'matcha_series',
      name: 'Artisan Matcha Series',
      category: 'Milk Tea',
      description:
          'Ceremonial grade Uji matcha whisked fresh to order with cream',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'bakery_display',
      name: 'Pastry & Bakery Display',
      category: 'Add Ons',
      description: 'Freshly baked flaky croissants and butter scones daily',
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),
    BrewMenuItem(
      id: 'spanish_latte',
      name: 'Spanish Latte',
      category: 'Cà Phê Series',
      description: 'Creamy espresso blend with sweet condensed milk',
      sizePrices: {BrewItemSize.medium: 7500, BrewItemSize.large: 8500},
    ),
    BrewMenuItem(
      id: 'caramel_frappe',
      name: 'Caramel Frappe',
      category: 'Iced Blended',
      description:
          'Sweet and creamy caramel coffee frappe with caramel drizzle',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'brown_sugar',
      name: 'Brown Sugar Milk Tea',
      category: 'Milk Tea',
      description: 'Fresh milk with slow-simmered caramelized tiger pearls',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'lemonade_sparkling',
      name: 'Fresh Sparkling Lemonade',
      category: 'Fresh Lemonade',
      description: 'Crisp citrus refresher with sparkling soda water and mint',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'avalanche_biscoff',
      name: 'Avalanche Biscoff',
      category: 'Iced Blended',
      description: 'Decadent coffee frappe with crushed Lotus Biscoff biscuit',
      sizePrices: {BrewItemSize.medium: 7000, BrewItemSize.large: 8000},
    ),
    BrewMenuItem(
      id: 'midnight_frappe',
      name: 'Midnight Dark Frappe',
      category: 'Iced Blended',
      description: 'Intense dark roast coffee blended with cocoa nibs',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
  ];

  @override
  void initState() {
    super.initState();
    final menu = widget.counter?.menu(widget.shop.partner);
    _menuSubscription = menu?.listen((items) {
      if (mounted) setState(() => _menuItems = items);
    });
  }

  @override
  void dispose() {
    _menuSubscription?.cancel();
    super.dispose();
  }

  static String _cleanCategoryName(String raw) {
    final stripped = raw.replaceAll(RegExp(r'\s*\d+/\d+'), '').trim();
    if (stripped.isEmpty) return raw;
    if (stripped.toLowerCase() == 'premium') return 'Premium Series';
    return stripped;
  }

  List<_CategoryItem> _categoriesFor(List<BrewMenuItem> items) {
    final live = BrewMenuItem.categoriesOf(items);
    final names = live.isNotEmpty
        ? live.map(_cleanCategoryName).toSet().toList()
        : _defaultCategories;
    return names
        .map((name) {
          final lower = (name as dynamic)?.toString().toLowerCase() ?? '';
          final (icon, color) = lower.contains('coffee') || lower.contains('cà')
              ? (Icons.coffee_rounded, const Color(0xFFD4A373))
              : lower.contains('blend') || lower.contains('frappe')
              ? (Icons.icecream_rounded, const Color(0xFFC68B59))
              : lower.contains('tea')
              ? (Icons.bubble_chart_rounded, const Color(0xFFE0A96D))
              : lower.contains('lemon')
              ? (Icons.local_drink_rounded, const Color(0xFFE9C46A))
              : lower.contains('fresh') || lower.contains('refresh')
              ? (Icons.eco_rounded, const Color(0xFF81B29A))
              : (Icons.local_cafe_rounded, const Color(0xFFB5838D));
          return _CategoryItem(
            id: name,
            name: name,
            icon: icon,
            accentColor: color,
            imageBytes: items
                .where(
                  (item) =>
                      _cleanCategoryName(item.category ?? '') == name &&
                      item.imageBytes != null,
                )
                .map((item) => item.imageBytes)
                .firstOrNull,
          );
        })
        .toList(growable: false);
  }

  void _openCategory(String categoryName) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      CategoryMenuScreen.route(
        shop: widget.shop,
        session: widget.session,
        counter: widget.counter,
        initialCategory: categoryName,
      ),
    );
  }

  static String? _itemFallbackAsset(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('avalanche') || lower.contains('dirty')) {
      return 'assets/images/dirty_avalanche.jpg';
    } else if (lower.contains('americano')) {
      return 'assets/images/classic_coffees/americano.jpg';
    } else if (lower.contains('spanish')) {
      return 'assets/images/classic_coffees/spanish_latte.jpg';
    } else if (lower.contains('salted caramel')) {
      return 'assets/images/classic_coffees/salted_caramel.jpg';
    } else if (lower.contains('caramel macchiato')) {
      return 'assets/images/classic_coffees/caramel_macchiato.jpg';
    } else if (lower.contains('hazelnut')) {
      return 'assets/images/classic_coffees/hazelnut_macchiato.jpg';
    } else if (lower.contains('vanilla')) {
      return 'assets/images/classic_coffees/vanilla_macchiato.jpg';
    } else if (lower.contains('mocha almond')) {
      return 'assets/images/classic_coffees/mocha_almond.jpg';
    } else if (lower.contains('mocha')) {
      return 'assets/images/classic_coffees/cafe_mocha.jpg';
    } else if (lower.contains('latte')) {
      return 'assets/images/classic_coffees/cafe_latte.jpg';
    }
    return null;
  }

  BrewMenuItem get _bestSellerItem {
    return _menuItems.where((i) {
      final name = (i.name as dynamic)?.toString().toLowerCase() ?? '';
      return name.contains('avalanche') || name.contains('dirty');
    }).firstOrNull ??
    _defaultMenuItems.where((i) {
      final name = (i.name as dynamic)?.toString().toLowerCase() ?? '';
      return name.contains('avalanche') || name.contains('dirty');
    }).firstOrNull ??
    const BrewMenuItem(
      id: 'dirty_avalanche',
      name: 'Dirty Avalanche',
      category: 'Iced Blended',
      subCategory: 'Frappe Series',
      description: 'Bold coffee frappe with rich chocolate and cream',
      sizePrices: {BrewItemSize.medium: 8000, BrewItemSize.large: 9000},
    );
  }

  void _openBestSeller() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      OrderWizardScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: widget.shop,
        session: widget.session,
        counter: widget.counter,
        item: _bestSellerItem,
      ),
    );
  }

  void _showWriteReviewDialog() {
    int rating = 5;
    final textController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF20F241A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Write a Review',
                        style: BrewType.displayAt(20).copyWith(
                          color: BrewColor.cream,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: BrewColor.sageLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'How was your experience at ${widget.shop.displayName}?',
                    style: BrewType.rowBody.copyWith(
                      color: BrewColor.sageLight,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      return IconButton(
                        iconSize: 34,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setModalState(() => rating = star);
                        },
                        icon: Icon(
                          star <= rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFF4C430),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    style: BrewType.rowBody.copyWith(color: BrewColor.cream),
                    decoration: InputDecoration(
                      hintText:
                          'Share details about your drink, service, or atmosphere...',
                      hintStyle: BrewType.rowBody.copyWith(
                        color: BrewColor.cream.withValues(alpha: 0.35),
                      ),
                      filled: true,
                      fillColor: const Color(0x3308170F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: BrewColor.cream.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF5BA37E)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3E6953),
                        foregroundColor: BrewColor.cream,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF143825),
                            content: Text(
                              'Thank you! Your review has been submitted.',
                              style: BrewType.rowBody.copyWith(
                                color: BrewColor.cream,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Submit Review',
                        style: BrewType.title.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: BrewColor.cream,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final isOpen = shop.status == BrewShopStatus.open;
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top;
    final bottomPadding = math.max(media.padding.bottom, 16.0);
    final categories = _categoriesFor(_menuItems);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF081710),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: BrewColor.field,
        body: Stack(
          children: [
            // Background ambient pattern covering the entire screen
            const Positioned.fill(child: BrewBackground(child: SizedBox())),

            // Scrollable store body
            CustomScrollView(
              slivers: [
                // Top Hero Section with Back Button
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      // Hero Banner surface (seamlessly fading out to transparent at the bottom)
                      Container(
                        height: 380 + topPadding,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xF0183B28),
                              Color(0xCC112D1E),
                              Color(0x550D2217),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.45, 0.8, 1.0],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Coffee cup photo with soft vertical gradient shader mask
                            Positioned(
                              top: topPadding,
                              right: -10,
                              width: 310,
                              height: 350,
                              child: ShaderMask(
                                shaderCallback: (bounds) {
                                  return const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white,
                                      Colors.white,
                                      Color(0x55FFFFFF),
                                      Colors.transparent,
                                    ],
                                    stops: [0.0, 0.4, 0.75, 1.0],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.dstIn,
                                child: Image.asset(
                                  'assets/images/hero_cup.jpg',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            // Left scrim gradient to ensure shop text is highly legible
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Color(0xF2091F14),
                                      Color(0xD9091F14),
                                      Color(0x20091F14),
                                    ],
                                    stops: [0.0, 0.52, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            // Soft ambient light aura
                            Positioned(
                              top: 20,
                              right: 20,
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0x33487A5E),
                                      Color(0x00000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Stylized squircle cup emblem graphic (clean border & anti-aliased clip)
                            Positioned(
                              left: 24,
                              top: topPadding + 60,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: const Color(0x380F2B1D),
                                  border: Border.all(
                                    color: BrewColor.cream.withValues(
                                      alpha: 0.18,
                                    ),
                                    width: 1.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x59000000),
                                      blurRadius: 24,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: BrewShopMark(
                                    shop: shop,
                                    dimension: 120,
                                    fit: BoxFit.cover,
                                    showFrame: false,
                                  ),
                                ),
                              ),
                            ),
                            // Shop Name
                            Positioned(
                              left: 24,
                              right: 24,
                              top: topPadding + 196,
                              child: Text(
                                shop.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BrewType.displayAt(30).copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: BrewColor.cream,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            // Shop Description
                            Positioned(
                              left: 24,
                              right: 90,
                              top: topPadding + 242,
                              child: Text(
                                shop.displayDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: BrewType.rowBody.copyWith(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: BrewColor.sageLight,
                                ),
                              ),
                            ),
                            // Location and Operating Hours
                            Positioned(
                              left: 24,
                              right: 24,
                              top: topPadding + 304,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    size: 17,
                                    color: BrewColor.sageLight,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Aurora, QC',
                                    style: BrewType.title.copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: BrewColor.sageLight,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 16,
                                    color: BrewColor.sageLight,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '7:00 AM - 10:00 PM',
                                      overflow: TextOverflow.ellipsis,
                                      style: BrewType.title.copyWith(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: BrewColor.sageLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status Badge (OPEN / CLOSED)
                      Positioned(
                        top: topPadding + 18,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xC70B2B1A),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isOpen
                                  ? const Color(0xFF5BA37E)
                                  : BrewColor.alert,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOpen
                                      ? const Color(0xFF48D588)
                                      : BrewColor.alert,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isOpen ? 'OPEN' : 'CLOSED',
                                style: BrewType.title.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: BrewColor.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Floating Top Back Button
                      Positioned(
                        top: topPadding + 8,
                        left: 16,
                        child: Semantics(
                          button: true,
                          label: 'Back to home',
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).maybePop();
                            },
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0x66000000),
                                border: Border.all(
                                  color: BrewColor.cream.withValues(alpha: 0.2),
                                  width: 1.0,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x40000000),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                size: 20,
                                color: BrewColor.cream,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main store content: Tabs & Active Tab Body
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Tab Navigation Pills
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _tabs.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final label = _tabs[index];
                            final isSelected = index == _safeSelectedTab;
                            return InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedTab = index);
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF3E6953)
                                      : const Color(0x33102318),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF5BA37E)
                                        : BrewColor.cream.withValues(
                                            alpha: 0.12,
                                          ),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: BrewType.title.copyWith(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? const Color(0xFFE8F5EE)
                                        : BrewColor.cream.withValues(
                                            alpha: 0.7,
                                          ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Dynamic Tab Body
                      switch (_safeSelectedTab) {
                        0 => _buildMenuTab(context, categories),
                        1 => _buildAboutTab(context, shop),
                        2 => _buildPhotosTab(context),
                        3 => _buildReviewsTab(context),
                        _ => _buildMenuTab(context, categories),
                      },

                      // Bottom clearance
                      SizedBox(height: bottomPadding + 64),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= TAB 0: MENU TAB =================
  Widget _buildMenuTab(BuildContext context, List<_CategoryItem> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MENU CATEGORIES Header
        Text(
          'MENU CATEGORIES',
          style: BrewType.title.copyWith(
            fontSize: 12,
            letterSpacing: 1.8,
            color: BrewColor.sageLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),

        // 3-Column Category Grid Cards
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.80,
          ),
          itemBuilder: (context, index) {
            final cat = categories[index];
            return _CategoryGridCard(
              item: cat,
              onTap: () => _openCategory(cat.name),
            );
          },
        ),
        const SizedBox(height: 22),

        // "Try our Best Seller!" Promo Card
        _BestSellerPromoCard(
          item: _bestSellerItem,
          onView: _openBestSeller,
        ),
      ],
    );
  }

  // ================= TAB 1: ABOUT TAB =================
  Widget _buildAboutTab(BuildContext context, BrewShop shop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Story Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xEB132218),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x33487A5E),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 20,
                      color: Color(0xFF5BA37E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Our Story',
                    style: BrewType.displayAt(18).copyWith(
                      fontWeight: FontWeight.w700,
                      color: BrewColor.cream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Proudly serving the Aurora community since 2023. At ${shop.displayName}, every bean is thoughtfully sourced and roasted to perfection. From our signature handcrafted espresso blends to our freshly shaken fruit refreshers, our baristas pour passion into every cup.',
                style: BrewType.rowBody.copyWith(
                  fontSize: 13,
                  height: 1.5,
                  color: BrewColor.cream.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Hours & Location Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xEB132218),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hours & Location',
                style: BrewType.displayAt(
                  17,
                ).copyWith(fontWeight: FontWeight.w700, color: BrewColor.cream),
              ),
              const SizedBox(height: 14),
              _buildInfoRow(
                Icons.calendar_today_rounded,
                'Monday – Friday',
                '7:00 AM – 10:00 PM',
              ),
              const Divider(color: Color(0x22FFFFFF), height: 18),
              _buildInfoRow(
                Icons.weekend_rounded,
                'Saturday – Sunday',
                '8:00 AM – 11:00 PM',
              ),
              const Divider(color: Color(0x22FFFFFF), height: 18),
              _buildInfoRow(
                Icons.location_on_rounded,
                'Address',
                'Aurora Blvd, Quezon City, Metro Manila',
              ),
              const Divider(color: Color(0x22FFFFFF), height: 18),
              _buildInfoRow(
                Icons.phone_rounded,
                'Contact',
                '(02) 8123-4567 • hello@quickbrew.ph',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Amenities Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xEB132218),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amenities',
                style: BrewType.displayAt(
                  17,
                ).copyWith(fontWeight: FontWeight.w700, color: BrewColor.cream),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildAmenityChip(Icons.wifi_rounded, 'Free Wi-Fi'),
                  _buildAmenityChip(Icons.ac_unit_rounded, 'Air Conditioned'),
                  _buildAmenityChip(Icons.power_rounded, 'Power Outlets'),
                  _buildAmenityChip(Icons.chair_rounded, 'Cozy Seating'),
                  _buildAmenityChip(
                    Icons.delivery_dining_rounded,
                    'Takeout & Delivery',
                  ),
                  _buildAmenityChip(
                    Icons.pets_rounded,
                    'Pet Friendly (Outdoor)',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF5BA37E)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: BrewType.title.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: BrewColor.cream.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: BrewType.rowBody.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: BrewColor.cream,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAmenityChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x330B2317),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.1),
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5BA37E)),
          const SizedBox(width: 6),
          Text(
            text,
            style: BrewType.title.copyWith(
              fontSize: 12,
              color: BrewColor.cream.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  String _formatItemPrice(BrewMenuItem item) {
    if (item.sizePrices.isNotEmpty) {
      final prices = item.sizePrices.values.toList()..sort();
      if (prices.length >= 2) {
        return '₱${(prices.first / 100).toStringAsFixed(0)} | ₱${(prices.last / 100).toStringAsFixed(0)}';
      } else if (prices.isNotEmpty) {
        return '₱${(prices.first / 100).toStringAsFixed(0)}';
      }
    }
    if (item.priceCents != null) {
      return '₱${(item.priceCents! / 100).toStringAsFixed(0)}';
    }
    return '₱75';
  }

  void _openDrinkWizard(BrewMenuItem item) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      OrderWizardScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: widget.shop,
        session: widget.session,
        counter: widget.counter,
        item: item,
      ),
    );
  }

  (IconData, Color) _itemIconAndColor(BrewMenuItem item) {
    final name = (item.name as dynamic)?.toString() ?? '';
    final category = (item.category as dynamic)?.toString() ?? '';
    final lower = '$name $category'.toLowerCase();
    if (lower.contains('coffee') ||
        lower.contains('cà') ||
        lower.contains('latte')) {
      return (Icons.coffee_rounded, const Color(0xFFD4A373));
    } else if (lower.contains('blend') ||
        lower.contains('frappe') ||
        lower.contains('avalanche')) {
      return (Icons.icecream_rounded, const Color(0xFFC68B59));
    } else if (lower.contains('matcha') || lower.contains('tea')) {
      return (Icons.bubble_chart_rounded, const Color(0xFF709775));
    } else if (lower.contains('lemon')) {
      return (Icons.local_drink_rounded, const Color(0xFFE9C46A));
    } else if (lower.contains('refresh') || lower.contains('fruit')) {
      return (Icons.eco_rounded, const Color(0xFF81B29A));
    } else if (lower.contains('pastry') ||
        lower.contains('bakery') ||
        lower.contains('croissant')) {
      return (Icons.bakery_dining_rounded, const Color(0xFFE0A96D));
    }
    return (Icons.local_cafe_rounded, const Color(0xFFB5838D));
  }

  // ================= TAB 2: PHOTOS / MENU PICTURES TAB =================
  Widget _buildPhotosTab(BuildContext context) {
    final allItems = _menuItems.isNotEmpty ? _menuItems : _defaultMenuItems;
    final totalPages = math.max(1, (allItems.length / _photosPageSize).ceil());
    final currentPage = _safePhotosPage.clamp(0, totalPages - 1);
    final pageStart = currentPage * _photosPageSize;
    final pageItems = allItems.skip(pageStart).take(_photosPageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row with item count
        Row(
          children: [
            Text(
              'STORE GALLERY',
              style: BrewType.title.copyWith(
                fontSize: 12,
                letterSpacing: 1.8,
                color: BrewColor.sageLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x33487A5E),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${allItems.length} items',
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  color: const Color(0xFF67B08B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Prominent Responsive Pagination Controls Bar (Prev, Page pill, Next)
        if (totalPages > 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous Button
                InkWell(
                  key: const ValueKey('prev_page_btn'),
                  onTap: currentPage > 0
                      ? () {
                          HapticFeedback.lightImpact();
                          setState(() => _photosPage = currentPage - 1);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: currentPage > 0
                          ? const Color(0x33487A5E)
                          : const Color(0x1A102318),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: currentPage > 0
                            ? const Color(0xFF5BA37E)
                            : BrewColor.cream.withValues(alpha: 0.1),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back_ios_rounded,
                          size: 11,
                          color: currentPage > 0
                              ? BrewColor.cream
                              : BrewColor.cream.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Prev',
                          style: BrewType.title.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: currentPage > 0
                                ? BrewColor.cream
                                : BrewColor.cream.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Center Page Indicator Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x2E102318),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: BrewColor.cream.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    'Page ${currentPage + 1} of $totalPages',
                    style: BrewType.mono.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BrewColor.cream,
                    ),
                  ),
                ),

                // Next Button
                InkWell(
                  key: const ValueKey('next_page_btn'),
                  onTap: currentPage < totalPages - 1
                      ? () {
                          HapticFeedback.lightImpact();
                          setState(() => _photosPage = currentPage + 1);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: currentPage < totalPages - 1
                          ? const Color(0x33487A5E)
                          : const Color(0x1A102318),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: currentPage < totalPages - 1
                            ? const Color(0xFF5BA37E)
                            : BrewColor.cream.withValues(alpha: 0.1),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next',
                          style: BrewType.title.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: currentPage < totalPages - 1
                                ? BrewColor.cream
                                : BrewColor.cream.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: currentPage < totalPages - 1
                              ? BrewColor.cream
                              : BrewColor.cream.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        // 2-Column Grid of Menu Picture Cards
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: pageItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final item = pageItems[index];
            final (icon, accentColor) = _itemIconAndColor(item);
            final priceStr = _formatItemPrice(item);

            return InkWell(
              onTap: () => _openDrinkWizard(item),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xEB132218),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Picture / Illustration area
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0x2E102B1D),
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accentColor.withValues(alpha: 0.22),
                              const Color(0x1A091A11),
                            ],
                          ),
                        ),
                        child: Builder(
                          builder: (context) {
                            final imageBytes = item.imageBytes;

                            if (imageBytes != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  imageBytes,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              );
                            }

                            final fallback = _itemFallbackAsset(item.name);
                            if (fallback != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  fallback,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              );
                            }

                            return Center(
                              child: Icon(icon, size: 38, color: accentColor),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Item Name
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrewType.title.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BrewColor.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Description or Subtitle
                    Text(
                      item.description ?? item.category ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrewType.rowBody.copyWith(
                        fontSize: 11,
                        color: BrewColor.sageLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Price & Order Pill
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceStr,
                            style: BrewType.mono.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFD4A373),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x33487A5E),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0x66487A5E),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'Order',
                            style: BrewType.mono.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: BrewColor.cream,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ================= TAB 3: REVIEWS TAB =================
  Widget _buildReviewsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall Rating Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xEB132218),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '4.9',
                        style: BrewType.displayAt(38).copyWith(
                          fontWeight: FontWeight.w700,
                          color: BrewColor.cream,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ 5.0',
                        style: BrewType.title.copyWith(
                          fontSize: 14,
                          color: BrewColor.sageLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(
                      5,
                      (_) => const Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: Color(0xFFF4C430),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '128 verified customer reviews',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 11.5,
                      color: BrewColor.cream.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0x33487A5E),
                  foregroundColor: BrewColor.cream,
                  elevation: 0,
                  side: const BorderSide(color: Color(0x66487A5E)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: _showWriteReviewDialog,
                icon: const Icon(Icons.rate_review_rounded, size: 16),
                label: Text(
                  'Review',
                  style: BrewType.title.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Customer Review Cards
        _buildReviewCard(
          author: 'Maria Santos',
          rating: 5,
          date: '2 days ago',
          drinkOrdered: 'Dirty Avalanche (L)',
          comment:
              'Hands down the best Dirty Avalanche in QC! Perfectly balanced espresso and creamy chocolate frappe. The atmosphere is quiet and lovely.',
        ),
        const SizedBox(height: 12),
        _buildReviewCard(
          author: 'Alex Tan',
          rating: 5,
          date: '1 week ago',
          drinkOrdered: 'Iced Sea Salt Latte',
          comment:
              'Staff is super friendly and the quick ordering flow made my morning rush so easy. Wi-Fi was fast and steady too.',
        ),
        const SizedBox(height: 12),
        _buildReviewCard(
          author: 'Joshua Reyes',
          rating: 5,
          date: '2 weeks ago',
          drinkOrdered: 'Matcha Green Tea',
          comment:
              'Genuine Japanese matcha taste, not overly sweet. Will definitely be a regular here!',
        ),
      ],
    );
  }

  Widget _buildReviewCard({
    required String author,
    required int rating,
    required String date,
    required String drinkOrdered,
    required String comment,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.1),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0x33487A5E),
                child: Text(
                  author[0],
                  style: BrewType.title.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BrewColor.cream,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: BrewType.title.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: BrewColor.cream,
                      ),
                    ),
                    Text(
                      date,
                      style: BrewType.rowBody.copyWith(
                        fontSize: 11,
                        color: BrewColor.sageLight,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 15,
                    color: const Color(0xFFF4C430),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: const Color(0x2E102B1D),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Ordered: $drinkOrdered',
              style: BrewType.mono.copyWith(
                fontSize: 10.5,
                color: const Color(0xFFD4A373),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comment,
            style: BrewType.rowBody.copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: BrewColor.cream.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem {
  const _CategoryItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.accentColor,
    this.imageBytes,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color accentColor;
  final Uint8List? imageBytes;
}

class _CategoryGridCard extends StatefulWidget {
  const _CategoryGridCard({required this.item, required this.onTap});

  final _CategoryItem item;
  final VoidCallback onTap;

  @override
  State<_CategoryGridCard> createState() => _CategoryGridCardState();
}

class _CategoryGridCardState extends State<_CategoryGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 130),
        scale: _pressed ? 0.95 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xEB132218),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Stylized visual header
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0x2E102B1D),
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.item.accentColor.withValues(alpha: 0.18),
                        const Color(0x1A091A11),
                      ],
                    ),
                  ),
                  child: widget.item.imageBytes == null
                      ? Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0x330C2317),
                              border: Border.all(
                                color: widget.item.accentColor.withValues(
                                  alpha: 0.3,
                                ),
                                width: 1.0,
                              ),
                            ),
                            child: Icon(
                              widget.item.icon,
                              size: 24,
                              color: widget.item.accentColor,
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            widget.item.imageBytes!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                ),
              ),
              // Category Name Label (using elegant proportional typography with 2-line capacity)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6, bottom: 9),
                child: Text(
                  widget.item.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BrewType.title.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: BrewColor.cream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BestSellerPromoCard extends StatelessWidget {
  const _BestSellerPromoCard({
    this.item,
    required this.onView,
  });

  final BrewMenuItem? item;
  final VoidCallback? onView;

  Widget _buildProductImage() {
    final imageBytes = item?.imageBytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return Image.memory(
        imageBytes,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackBadge(),
      );
    }

    final name = (item?.name ?? '').toLowerCase();
    String? assetPath;
    if (name.contains('avalanche') || name.contains('dirty') || name.isEmpty) {
      assetPath = 'assets/images/dirty_avalanche.jpg';
    } else if (name.contains('americano')) {
      assetPath = 'assets/images/classic_coffees/americano.jpg';
    } else if (name.contains('spanish')) {
      assetPath = 'assets/images/classic_coffees/spanish_latte.jpg';
    } else if (name.contains('salted caramel')) {
      assetPath = 'assets/images/classic_coffees/salted_caramel.jpg';
    } else if (name.contains('caramel macchiato')) {
      assetPath = 'assets/images/classic_coffees/caramel_macchiato.jpg';
    } else if (name.contains('hazelnut')) {
      assetPath = 'assets/images/classic_coffees/hazelnut_macchiato.jpg';
    } else if (name.contains('vanilla')) {
      assetPath = 'assets/images/classic_coffees/vanilla_macchiato.jpg';
    } else if (name.contains('mocha almond')) {
      assetPath = 'assets/images/classic_coffees/mocha_almond.jpg';
    } else if (name.contains('mocha')) {
      assetPath = 'assets/images/classic_coffees/cafe_mocha.jpg';
    } else if (name.contains('latte')) {
      assetPath = 'assets/images/classic_coffees/cafe_latte.jpg';
    }

    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackBadge(),
      );
    }

    return _buildFallbackBadge();
  }

  Widget _buildFallbackBadge() {
    return const Center(
      child: Icon(
        Icons.local_cafe_rounded,
        size: 38,
        color: Color(0xFFD4A373),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Try our Best Seller! Dirty Avalanche. Bold coffee. Creamy bliss. View',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0x33487A5E),
          highlightColor: const Color(0x1F487A5E),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xEB132218),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33487A5E), width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Try our Best Seller!',
                        style: BrewType.title.copyWith(
                          fontSize: 11.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD4A373),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dirty Avalanche',
                        style: BrewType.displayAt(19).copyWith(
                          fontWeight: FontWeight.w600,
                          color: BrewColor.cream,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Bold coffee. Creamy bliss.',
                        style: BrewType.rowBody.copyWith(
                          fontSize: 12,
                          color: BrewColor.cream.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // View button
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
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
                              'View',
                              style: BrewType.mono.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: BrewColor.cream,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: BrewColor.cream,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Stylized drink preview badge with photo
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x33C68B59), Color(0x1F0B1E13)],
                    ),
                    border: Border.all(
                      color: BrewColor.cream.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: _buildProductImage(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
