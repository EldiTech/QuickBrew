import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import 'order_wizard_screen.dart';

/// Screen 3 & 4 of the visual mockup: Category Drink Browser.
///
/// Features:
/// - Top Bar with back button and shop name
/// - Category pill selector ("Cà Phê", "Iced Blended", "Milk Tea", "Refresher", ...)
/// - Dynamic product listing filtered by the active category (live menu or fallback)
/// - Toggle between List View (Screen 3) and 2-Column Grid View (Screen 4)
/// - Drink cards with name, description, size prices (₱80 | ₱90), sizes (M, L),
///   favorite heart toggle, and quick '+' add button
class CategoryMenuScreen extends StatefulWidget {
  const CategoryMenuScreen({
    super.key,
    required this.shop,
    this.session,
    this.counter,
    this.initialCategory = 'Iced Blended',
  });

  final BrewShop shop;
  final BrewSession? session;
  final BrewCounter? counter;
  final String initialCategory;

  static Route<void> route({
    bool reduced = false,
    required BrewShop shop,
    BrewSession? session,
    BrewCounter? counter,
    String initialCategory = 'Iced Blended',
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          CategoryMenuScreen(
            shop: shop,
            session: session,
            counter: counter,
            initialCategory: initialCategory,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
    );
  }

  @override
  State<CategoryMenuScreen> createState() => _CategoryMenuScreenState();
}

class _CategoryMenuScreenState extends State<CategoryMenuScreen> {
  late String _currentCategory;
  bool _isGridView = false;
  final Set<String> _favorites = {};
  StreamSubscription<List<BrewMenuItem>>? _menuSubscription;
  List<BrewMenuItem> _menuItems = const [];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedSubCategory;
  int _page = 0;

  static const _pageSize = 5;

  static const _fallbackItems = [
    // --- Classic Coffees (Seven Coffee & Tea) ---
    BrewMenuItem(
      id: 'classic_americano',
      name: 'Americano',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Double shot rich espresso over cold filtered water and ice',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_cafe_latte',
      name: 'Cafe Latte',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Rich espresso with steamed velvety fresh milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_cafe_mocha',
      name: 'Cafe Mocha',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Espresso with rich chocolate and steamed milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_caramel_macchiato',
      name: 'Caramel Macchiato',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Espresso with vanilla syrup, milk and caramel drizzle',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_hazelnut_macchiato',
      name: 'Hazelnut Macchiato',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Smooth hazelnut espresso infusion with velvety foam',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_mocha_almond',
      name: 'Mocha Almond',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Rich cocoa and espresso with nutty almond notes',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_salted_caramel',
      name: 'Salted Caramel',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Buttery caramel with a hint of sea salt and espresso',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_spanish_latte',
      name: 'Spanish Latte',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Creamy espresso blend with sweet condensed milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'classic_vanilla_macchiato',
      name: 'Vanilla Macchiato',
      category: 'Classic',
      subCategory: 'Classic',
      description: 'Sweet vanilla bean infused espresso layered with milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),

    // --- Cà Phê Series ---
    BrewMenuItem(
      id: 'spanish_latte',
      name: 'Spanish Latte',
      category: 'Cà Phê',
      description: 'Creamy espresso blend with sweet condensed milk',
      sizePrices: {BrewItemSize.medium: 7500, BrewItemSize.large: 8500},
    ),
    BrewMenuItem(
      id: 'pour_over',
      name: 'Barista Pour-Over Station',
      category: 'Cà Phê',
      description: 'Crafted with precision Ethiopian and single-origin beans',
      sizePrices: {BrewItemSize.medium: 8500, BrewItemSize.large: 9500},
    ),
    BrewMenuItem(
      id: 'viet_iced_coffee',
      name: 'Vietnamese Iced Coffee',
      category: 'Cà Phê',
      description: 'Traditional slow-drip roast with sweet condensed milk',
      sizePrices: {BrewItemSize.medium: 7000, BrewItemSize.large: 8000},
    ),
    BrewMenuItem(
      id: 'iced_americano',
      name: 'Iced Americano',
      category: 'Cà Phê',
      description: 'Double shot rich espresso over cold filtered water and ice',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),

    // --- Iced Blended ---
    BrewMenuItem(
      id: 'dirty_avalanche',
      name: 'Dirty Avalanche',
      category: 'Iced Blended',
      description: 'Coffee based frappe with rich chocolate and cream',
      sizePrices: {BrewItemSize.medium: 8000, BrewItemSize.large: 9000},
    ),
    BrewMenuItem(
      id: 'java_frappe',
      name: 'Java Frappe',
      category: 'Iced Blended',
      description: 'Smooth coffee frappe with mocha drizzle',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'midnight_frappe',
      name: 'Midnight Frappe',
      category: 'Iced Blended',
      description: 'Dark and rich coffee chocolate blend',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'caramel_frappe',
      name: 'Caramel Frappe',
      category: 'Iced Blended',
      description: 'Sweet and creamy caramel coffee frappe',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'avalanche_biscoff',
      name: 'Avalanche Biscoff',
      category: 'Iced Blended',
      description: 'Coffee frappe with Biscoff biscuit flavor',
      sizePrices: {BrewItemSize.medium: 7000, BrewItemSize.large: 8000},
    ),

    // --- Milk Tea ---
    BrewMenuItem(
      id: 'matcha_green_tea',
      name: 'Matcha Green Tea',
      category: 'Milk Tea',
      description: 'Japanese pure matcha blended with cream',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'brown_sugar',
      name: 'Brown Sugar Milk Tea',
      category: 'Milk Tea',
      description: 'Fresh milk with slow-simmered caramelized tiger pearls',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'classic_pearl_tea',
      name: 'Classic Pearl Milk Tea',
      category: 'Milk Tea',
      description: 'Black tea with creamy milk and chewy tapioca pearls',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'taro_milk_tea',
      name: 'Taro Milk Tea',
      category: 'Milk Tea',
      description: 'Creamy sweet taro root infusion with velvety fresh milk',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),

    // --- Fresh Lemonade ---
    BrewMenuItem(
      id: 'lemonade_sparkling',
      name: 'Fresh Sparkling Lemonade',
      category: 'Fresh Lemonade',
      description: 'Crisp citrus refresher with sparkling soda water and mint',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'honey_citrus',
      name: 'Honey Citrus Lemonade',
      category: 'Fresh Lemonade',
      description: 'Pure wild honey infused with fresh hand-squeezed lemon',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'strawberry_lemonade',
      name: 'Strawberry Lemonade',
      category: 'Fresh Lemonade',
      description: 'Muddled ripe strawberries with chilled tart lemonade',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),

    // --- Refresher ---
    BrewMenuItem(
      id: 'fruit_refreshers',
      name: 'Fresh Fruit Refreshers',
      category: 'Refresher',
      description: 'Handcrafted with real passion fruit, strawberries and mint',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'mango_dragonfruit',
      name: 'Mango Dragonfruit Refresher',
      category: 'Refresher',
      description: 'Tropical sweet mango nectar with diced red dragonfruit',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'peach_berry_cooler',
      name: 'Peach Berry Cooler',
      category: 'Refresher',
      description: 'Juicy white peach nectar with mixed garden berries and ice',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'strawberry_acai',
      name: 'Strawberry Acai Cooler',
      category: 'Refresher',
      description: 'Sweet strawberry puree accented by crisp acai juice notes',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),

    // --- Add Ons ---
    BrewMenuItem(
      id: 'bakery_display',
      name: 'Pastry & Bakery Display',
      category: 'Add Ons',
      description: 'Freshly baked flaky croissants and butter scones daily',
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),
    BrewMenuItem(
      id: 'extra_shot',
      name: 'Extra Espresso Shot',
      category: 'Add Ons',
      description: 'Rich single-origin espresso boost pulled fresh',
      priceCents: 2000,
    ),
    BrewMenuItem(
      id: 'bobba_pearl',
      name: 'Bobba Pearl',
      category: 'Add Ons',
      description: 'Chewy brown sugar caramelized tapioca sinkers',
      priceCents: 1000,
    ),
    BrewMenuItem(
      id: 'cream_cheese_foam',
      name: 'Cream Cheese Foam',
      category: 'Add Ons',
      description: 'Decadent salted cream cheese crown for any drink',
      priceCents: 1500,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.initialCategory;
    final menu = widget.counter?.menu(widget.shop.partner);
    _menuSubscription = menu?.listen((items) {
      if (mounted) setState(() => _menuItems = items);
    });
  }

  @override
  void didUpdateWidget(CategoryMenuScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      setState(() {
        _currentCategory = widget.initialCategory;
        _selectedSubCategory = null;
        _page = 0;
      });
    }
  }

  @override
  void dispose() {
    _menuSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesCategory(String? itemCat, String target) {
    if (itemCat == null || itemCat.isEmpty) return false;
    final a = itemCat.trim().toLowerCase();
    final b = target.trim().toLowerCase();
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    if ((b.contains('cà') || b.contains('coffee')) &&
        (a.contains('cà') || a.contains('coffee'))) {
      return true;
    }
    if ((b.contains('blend') || b.contains('frappe')) &&
        (a.contains('blend') || a.contains('frappe'))) {
      return true;
    }
    if (b.contains('premium') && a.contains('premium')) return true;
    if (b.contains('classic') && a.contains('classic')) return true;
    if (b.contains('tea') && a.contains('tea')) return true;
    if (b.contains('lemon') && a.contains('lemon')) return true;
    if (b.contains('refresh') && a.contains('refresh')) return true;
    if (b.contains('add') && a.contains('add')) return true;
    return false;
  }

  (String, String) _pricesFor(BrewMenuItem item) {
    if (item.sizePrices.isNotEmpty) {
      final m = item.sizePrices[BrewItemSize.medium];
      final l = item.sizePrices[BrewItemSize.large];
      if (m != null && l != null) {
        return (
          '₱${(m / 100).toStringAsFixed(0)}',
          '₱${(l / 100).toStringAsFixed(0)}',
        );
      }
      final sorted = item.sizePrices.values.toList()..sort();
      if (sorted.length >= 2) {
        return (
          '₱${(sorted.first / 100).toStringAsFixed(0)}',
          '₱${(sorted.last / 100).toStringAsFixed(0)}',
        );
      } else if (sorted.isNotEmpty) {
        final p = '₱${(sorted.first / 100).toStringAsFixed(0)}';
        return (p, p);
      }
    }
    if (item.priceCents != null) {
      final p = '₱${(item.priceCents! / 100).toStringAsFixed(0)}';
      return (p, p);
    }
    return ('₱75', '₱85');
  }

  (IconData, Color) _iconAndColorFor(BrewMenuItem item) {
    final lower = ('${item.name} ${item.category ?? ''}').toLowerCase();
    if (lower.contains('coffee') ||
        lower.contains('cà') ||
        lower.contains('latte') ||
        lower.contains('espresso')) {
      return (Icons.coffee_rounded, const Color(0xFFD4A373));
    } else if (lower.contains('blend') ||
        lower.contains('frappe') ||
        lower.contains('avalanche')) {
      return (Icons.icecream_rounded, const Color(0xFFC68B59));
    } else if (lower.contains('matcha') || lower.contains('tea')) {
      return (Icons.bubble_chart_rounded, const Color(0xFF709775));
    } else if (lower.contains('lemon')) {
      return (Icons.local_drink_rounded, const Color(0xFFE9C46A));
    } else if (lower.contains('refresh') ||
        lower.contains('fruit') ||
        lower.contains('cooler')) {
      return (Icons.eco_rounded, const Color(0xFF81B29A));
    } else if (lower.contains('pastry') ||
        lower.contains('bakery') ||
        lower.contains('croissant')) {
      return (Icons.bakery_dining_rounded, const Color(0xFFE0A96D));
    }
    return (Icons.local_cafe_rounded, const Color(0xFFB5838D));
  }

  List<BrewMenuItem> get _itemsInCurrentCategory {
    final source = _menuItems.isNotEmpty ? _menuItems : _fallbackItems;
    return source
        .where(
          (item) =>
              _matchesCategory(item.category, _currentCategory) ||
              _matchesCategory(item.subCategory, _currentCategory),
        )
        .toList(growable: false);
  }

  List<String> get _subCategoriesInCurrentCategory {
    final result = <String>[];
    for (final item in _itemsInCurrentCategory) {
      final subCategory = item.subCategory?.trim();
      if (subCategory != null &&
          subCategory.isNotEmpty &&
          !result.contains(subCategory)) {
        result.add(subCategory);
      }
    }
    return result;
  }

  List<_DrinkItem> get _drinksForCurrentCategory {
    final query = _searchQuery.trim().toLowerCase();
    final itemsToUse = _itemsInCurrentCategory.where((item) {
      if (_selectedSubCategory != null &&
          item.subCategory != _selectedSubCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          (item.description?.toLowerCase().contains(query) ?? false) ||
          (item.category?.toLowerCase().contains(query) ?? false) ||
          (item.subCategory?.toLowerCase().contains(query) ?? false);
    });

    return itemsToUse
        .map((item) {
          final (mPrice, lPrice) = _pricesFor(item);
          final (icon, color) = _iconAndColorFor(item);
          return _DrinkItem(
            id: item.id,
            name: item.name,
            description: item.description ?? '',
            mediumPrice: mPrice,
            largePrice: lPrice,
            accentColor: color,
            icon: icon,
            menuItem: item,
          );
        })
        .toList(growable: false);
  }

  void _onAddToCart(_DrinkItem drink) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      OrderWizardScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: widget.shop,
        session: widget.session,
        counter: widget.counter,
        item: drink.menuItem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top;
    final bottomPadding = math.max(media.padding.bottom, 16.0);
    final drinks = _drinksForCurrentCategory;
    final subCategories = _subCategoriesInCurrentCategory;
    final totalPages = math.max(1, (drinks.length / _pageSize).ceil()).toInt();
    final page = _page.clamp(0, totalPages - 1).toInt();
    final pageDrinks = drinks
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList(growable: false);

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
            // Ambient texture background
            const Positioned.fill(child: BrewBackground(child: SizedBox())),

            // Scrollable Content
            CustomScrollView(
              slivers: [
                // Top App Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: topPadding + 8,
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        // Back Button
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).maybePop();
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0x33102418),
                              border: Border.all(
                                color: BrewColor.cream.withValues(alpha: 0.15),
                                width: 1.0,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 19,
                              color: BrewColor.cream,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentCategory,
                                textAlign: TextAlign.center,
                                style: BrewType.title.copyWith(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrewColor.cream,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.shop.displayName,
                                textAlign: TextAlign.center,
                                style: BrewType.rowBody.copyWith(
                                  fontSize: 11,
                                  color: BrewColor.cream.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Layout Toggle Button (Screen 3 List vs Screen 4 Grid)
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isGridView = !_isGridView);
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isGridView
                                  ? const Color(0x33487A5E)
                                  : const Color(0x33102418),
                              border: Border.all(
                                color: _isGridView
                                    ? const Color(0x66487A5E)
                                    : BrewColor.cream.withValues(alpha: 0.15),
                                width: 1.0,
                              ),
                            ),
                            child: Icon(
                              _isGridView
                                  ? Icons.view_agenda_outlined
                                  : Icons.grid_view_rounded,
                              size: 18,
                              color: BrewColor.cream,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {
                        _searchQuery = value;
                        _page = 0;
                      }),
                      textInputAction: TextInputAction.search,
                      style: BrewType.rowBody.copyWith(color: BrewColor.cream),
                      decoration: InputDecoration(
                        hintText: 'Search this menu',
                        hintStyle: BrewType.rowBody.copyWith(
                          color: BrewColor.cream.withValues(alpha: 0.45),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: BrewColor.cream.withValues(alpha: 0.72),
                        ),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _page = 0;
                                  });
                                },
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: BrewColor.cream.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                              ),
                        filled: true,
                        fillColor: const Color(0x66102418),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: BrewColor.cream.withValues(alpha: 0.16),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: BrewColor.cream.withValues(alpha: 0.16),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF5BA37E),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (subCategories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _SubCategoryFilterChip(
                            label: 'All',
                            selected: _selectedSubCategory == null,
                            onTap: () => setState(() {
                              _selectedSubCategory = null;
                              _page = 0;
                            }),
                          ),
                          for (final subCategory in subCategories)
                            _SubCategoryFilterChip(
                              label: subCategory,
                              selected: _selectedSubCategory == subCategory,
                              onTap: () => setState(() {
                                _selectedSubCategory = subCategory;
                                _page = 0;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Drink Cards: Screen 3 (List View) or Screen 4 (Grid View)
                if (drinks.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 60,
                        horizontal: 24,
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.local_cafe_outlined,
                              size: 44,
                              color: BrewColor.cream.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No drinks found in $_currentCategory',
                              style: BrewType.rowBody.copyWith(
                                color: BrewColor.cream.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (!_isGridView)
                  // Screen 3: List View
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final drink = pageDrinks[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DrinkListCard(
                            drink: drink,
                            onAdd: () => _onAddToCart(drink),
                          ),
                        );
                      }, childCount: pageDrinks.length),
                    ),
                  )
                else
                  // Screen 4: 2-Column Grid View
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final drink = pageDrinks[index];
                        final isFav = _favorites.contains(drink.id);
                        return _DrinkGridCard(
                          drink: drink,
                          isFavorite: isFav,
                          onToggleFavorite: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (isFav) {
                                _favorites.remove(drink.id);
                              } else {
                                _favorites.add(drink.id);
                              }
                            });
                          },
                          onAdd: () => _onAddToCart(drink),
                        );
                      }, childCount: pageDrinks.length),
                    ),
                  ),

                if (drinks.isNotEmpty && totalPages > 1)
                  SliverToBoxAdapter(
                    child: _MenuPagination(
                      page: page,
                      totalPages: totalPages,
                      onPrevious: page == 0
                          ? null
                          : () => setState(() => _page = page - 1),
                      onNext: page == totalPages - 1
                          ? null
                          : () => setState(() => _page = page + 1),
                    ),
                  ),

                // Clean bottom clearance
                SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubCategoryFilterChip extends StatelessWidget {
  const _SubCategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3E6953) : const Color(0x33102418),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF5BA37E)
                : BrewColor.cream.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: BrewType.title.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BrewColor.cream,
          ),
        ),
      ),
    ),
  );
}

class _MenuPagination extends StatelessWidget {
  const _MenuPagination({
    required this.page,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Previous'),
        ),
        Text(
          'Page ${page + 1} of $totalPages',
          style: BrewType.rowBody.copyWith(color: BrewColor.cream),
        ),
        TextButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Next'),
        ),
      ],
    ),
  );
}

String? _drinkFallbackAsset(String name) {
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

class _DrinkItem {
  const _DrinkItem({
    required this.id,
    required this.name,
    required this.description,
    required this.mediumPrice,
    required this.largePrice,
    required this.accentColor,
    required this.icon,
    required this.menuItem,
  });

  final String id;
  final String name;
  final String description;
  final String mediumPrice;
  final String largePrice;
  final Color accentColor;
  final IconData icon;
  final BrewMenuItem menuItem;
}

/// Screen 3 Drink List Item Card
class _DrinkListCard extends StatelessWidget {
  const _DrinkListCard({required this.drink, required this.onAdd});

  final _DrinkItem drink;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
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
        child: Row(
          children: [
            // Drink Emblem / Image
            Builder(
              builder: (context) {
                final imageBytes = drink.menuItem.imageBytes;

                return Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        drink.accentColor.withValues(alpha: 0.2),
                        const Color(0x1A091A11),
                      ],
                    ),
                    border: Border.all(
                      color: drink.accentColor.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Builder(
                      builder: (context) {
                        if (imageBytes != null) {
                          return Image.memory(
                            imageBytes,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          );
                        }
                        final fallback = _drinkFallbackAsset(drink.name);
                        if (fallback != null) {
                          return Image.asset(
                            fallback,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          );
                        }
                        return Center(
                          child: Icon(
                            drink.icon,
                            size: 32,
                            color: drink.accentColor,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),

            // Drink Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drink.name,
                    style: BrewType.title.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: BrewColor.cream,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    drink.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BrewType.rowBody.copyWith(
                      fontSize: 11.5,
                      color: BrewColor.cream.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Price & Sizes: ₱80 | ₱90   M  L
                  Row(
                    children: [
                      Text(
                        drink.mediumPrice == drink.largePrice
                            ? drink.mediumPrice
                            : '${drink.mediumPrice} | ${drink.largePrice}',
                        style: BrewType.mono.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: BrewColor.cream,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        drink.mediumPrice == drink.largePrice
                            ? 'Regular'
                            : 'M  L',
                        style: BrewType.mono.copyWith(
                          fontSize: 10,
                          color: BrewColor.cream.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Quick '+' add button
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF3E7554),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x403E7554), blurRadius: 8),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: Color(0xFFE8F5EE),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen 4 Drink 2-Column Grid Card
class _DrinkGridCard extends StatelessWidget {
  const _DrinkGridCard({
    required this.drink,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onAdd,
  });

  final _DrinkItem drink;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
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
            // Favorite heart toggle button
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: onToggleFavorite,
                child: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                  color: isFavorite
                      ? const Color(0xFFE56B6F)
                      : BrewColor.cream.withValues(alpha: 0.6),
                ),
              ),
            ),

            // Stylized drink graphic container with photo
            Expanded(
              child: Center(
                child: Builder(
                  builder: (context) {
                    final imageBytes = drink.menuItem.imageBytes;

                    final fallback = _drinkFallbackAsset(drink.name);
                    if (imageBytes != null || fallback != null) {
                      return Container(
                        width: double.infinity,
                        height: double.infinity,
                        margin: const EdgeInsets.only(top: 4, bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: drink.accentColor.withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: imageBytes != null
                              ? Image.memory(
                                  imageBytes,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Image.asset(
                                  fallback!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                        ),
                      );
                    }

                    return Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            drink.accentColor.withValues(alpha: 0.22),
                            const Color(0x1F0A1F13),
                          ],
                        ),
                        border: Border.all(
                          color: drink.accentColor.withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Icon(
                        drink.icon,
                        size: 32,
                        color: drink.accentColor,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Drink Name
            Text(
              drink.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrewType.title.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: BrewColor.cream,
              ),
            ),
            const SizedBox(height: 3),

            // Price & Size row + Add '+' button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drink.mediumPrice == drink.largePrice
                            ? drink.mediumPrice
                            : '${drink.mediumPrice} | ${drink.largePrice}',
                        style: BrewType.mono.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: BrewColor.cream,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        drink.mediumPrice == drink.largePrice
                            ? 'Regular'
                            : 'M  L',
                        style: BrewType.mono.copyWith(
                          fontSize: 9.5,
                          color: BrewColor.cream.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Circular '+' button
                InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3E7554),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 17,
                      color: Color(0xFFE8F5EE),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
