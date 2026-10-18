import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_transitions.dart';
import '../services/favorites_service.dart';
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
    return brewPageRoute<void>(
      reduced: reduced,
      child: CategoryMenuScreen(
        shop: shop,
        session: session,
        counter: counter,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  State<CategoryMenuScreen> createState() => _CategoryMenuScreenState();
}

class _CategoryMenuScreenState extends State<CategoryMenuScreen> {
  late String _currentCategory;
  bool _isGridView = false;
  final FavoritesService _favoritesService = FavoritesService.instance;
  StreamSubscription<List<BrewMenuItem>>? _menuSubscription;
  Timer? _menuLoadingTimeout;
  List<BrewMenuItem> _menuItems = const [];
  bool _menuLoading = true;
  final _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String? _selectedSubCategory;

  /// Drinks per page. The list is paged rather than endlessly scrolled: the
  /// reader picks a category first (on the shop's landing page), then steps
  /// through that category a page at a time with numbered controls at the
  /// bottom — so they always know where they are and how much is left.
  static const _pageSize = 6;

  /// Zero-based. Clamped against the current list in [_pageOf], so a menu
  /// update or a narrower search can never leave it pointing past the end.
  int _page = 0;

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

  static const _dripFallbackItems = [
    // --- Hello Vietnam ---
    BrewMenuItem(
      id: 'drip_ca_phe_sua_da',
      name: 'Cà Phê Sữa Đá',
      category: 'Hello Vietnam',
      subCategory: 'Vietnamese Coffee',
      description:
          'Traditional slow-drip dark roast with sweetened condensed milk',
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),
    BrewMenuItem(
      id: 'drip_egg_coffee',
      name: 'Cà Phê Trứng (Egg Coffee)',
      category: 'Hello Vietnam',
      subCategory: 'Vietnamese Coffee',
      description:
          'Rich Vietnamese espresso topped with luscious whipped egg foam',
      priceCents: 8800,
    ),

    // --- Tiramisu ---
    BrewMenuItem(
      id: 'drip_tiramisu_matcha',
      name: 'Tiramisu Matcha',
      category: 'Tiramisu',
      subCategory: 'Tiramisu Drinks',
      description:
          'Ceremonial Japanese matcha layered with velvety mascarpone cream',
      priceCents: 9800,
    ),
    BrewMenuItem(
      id: 'drip_tiramisu_latte',
      name: 'Tiramisu Latte',
      category: 'Tiramisu',
      subCategory: 'Tiramisu Drinks',
      description:
          'Handcrafted espresso with rich cocoa dust and tiramisu mascarpone',
      priceCents: 9800,
    ),

    // --- Cà Phê Series ---
    BrewMenuItem(
      id: 'drip_americano',
      name: 'Americano',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description:
          'Double shot rich dark roast espresso over cold filtered water',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_ca_phe_espanol',
      name: 'Cà Phê Español',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description: 'Spanish style espresso blend with smooth condensed milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_iced_latte',
      name: 'Iced Latte',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description: 'Fresh pulled espresso shots with cold whole milk over ice',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_caramel_macchiato',
      name: 'Caramel Macchiato',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description:
          'Layered espresso with vanilla milk and rich buttery caramel drizzle',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_salted_caramel',
      name: 'Salted Caramel Latte',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description:
          'Espresso infused with sea salt crystals and creamy caramel syrup',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_oreo_latte',
      name: 'Oreo Latte',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description:
          'Creamy iced coffee topped with crushed Oreo cookie crumbles',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_dark_mocha',
      name: 'Dark Mocha Latte',
      category: 'Cà Phê Series',
      subCategory: 'Classic Coffee',
      description:
          'Decadent dark Dutch cocoa blended with rich espresso and milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_matcha_fusion',
      name: 'Matcha Fusion',
      category: 'Cà Phê Series',
      subCategory: 'Premium Coffee',
      description:
          'Vibrant layered matcha green tea with bold espresso extraction',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_strawberry_latte',
      name: 'Strawberry Latte',
      category: 'Cà Phê Series',
      subCategory: 'Premium Coffee',
      description:
          'Sweet strawberry compote layered with espresso and cold milk',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_salty_cream_latte',
      name: 'Salty Cream Latte',
      category: 'Cà Phê Series',
      subCategory: 'Premium Coffee',
      description:
          'Signature iced latte crowned with whipped savory salted cream',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_salty_cream_americano',
      name: 'Salty Cream Americano',
      category: 'Cà Phê Series',
      subCategory: 'Premium Coffee',
      description: 'Crisp bold Americano topped with dense sea-salt cream cap',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_ube_latte',
      name: 'Ube Latte',
      category: 'Cà Phê Series',
      subCategory: 'Premium Coffee',
      description:
          'Authentic Philippine purple yam puree whisked with rich espresso',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_baristas_drink',
      name: "Barista's Drink",
      category: 'Cà Phê Series',
      subCategory: 'Specialty Coffee',
      description:
          "House barista secret recipe with double espresso and custom blend",
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),
    BrewMenuItem(
      id: 'drip_sea_salt_latte',
      name: 'Sea Salt Latte',
      category: 'Cà Phê Series',
      subCategory: 'Specialty Coffee',
      description:
          'Artisanal sea salt infused into velvety textured coffee milk',
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),
    BrewMenuItem(
      id: 'drip_cinnamon_latte',
      name: 'Cinnamon Latte',
      category: 'Cà Phê Series',
      subCategory: 'Specialty Coffee',
      description:
          'Warm aromatic Ceylon cinnamon spiced espresso and steamed milk',
      sizePrices: {BrewItemSize.medium: 5000, BrewItemSize.large: 6000},
    ),

    // --- Premium ---
    BrewMenuItem(
      id: 'drip_dolce_de_leche',
      name: 'Dolce de Leche',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description: 'Golden caramelized milk dulce syrup swirled with espresso',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_velvet_cream',
      name: 'Velvet Cream Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Silky smooth velvet cream cold foam over double shot espresso',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_mocha_latte',
      name: 'Mocha Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Rich Belgian chocolate paired with freshly ground coffee roast',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_white_mocha',
      name: 'White Mocha Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Sweet creamy white chocolate melted into hot espresso and milk',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_peanut_butter',
      name: 'Peanut Butter Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Creamy roasted peanut butter butterscotch swirl with iced coffee',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_vanilla_sweet_cream',
      name: 'Vanilla Sweet Cream',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'House-made vanilla sweet cream floated over bold iced coffee',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'drip_vienna_creamy',
      name: 'Vienna Creamy Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Traditional Viennese coffee topped with thick whipped cream',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'drip_toffee_nut',
      name: 'Toffee Nut Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Buttery toffee syrup and toasted nut notes with espresso and milk',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'drip_almond_latte',
      name: 'Almond Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Nutty toasted almond syrup harmonized with double shot espresso',
      sizePrices: {BrewItemSize.medium: 6000, BrewItemSize.large: 7000},
    ),
    BrewMenuItem(
      id: 'drip_nutella_latte',
      name: 'Nutella Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Authentic hazelnut cocoa Nutella spread stirred into warm espresso',
      sizePrices: {BrewItemSize.medium: 7000, BrewItemSize.large: 8000},
    ),
    BrewMenuItem(
      id: 'drip_biscoff_latte',
      name: 'Biscoff Latte',
      category: 'Premium',
      subCategory: 'Premium Coffee',
      description:
          'Caramelized speculoos Lotus Biscoff cookie butter iced latte',
      sizePrices: {BrewItemSize.medium: 7000, BrewItemSize.large: 8000},
    ),

    // --- Milky Series ---
    BrewMenuItem(
      id: 'drip_strawberry_milk',
      name: 'Strawberry Milk',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Real strawberry reduction combined with cold whole dairy milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_blueberry_milk',
      name: 'Blueberry Milk',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description: 'Wild blueberry puree swirled into fresh sweet cold milk',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_oreo_milk',
      name: 'Oreo Milk',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Rich cookies and cream milk with crushed Oreo biscuit pieces',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_swissmiss',
      name: 'Swissmiss',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Classic chocolate cocoa milk crafted with sweet milk chocolate',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
    ),
    BrewMenuItem(
      id: 'drip_strawberry_oreo',
      name: 'Strawberry Oreo',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Sweet strawberry and chocolate Oreo cookie duo with cold milk',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_ube_milk',
      name: 'Ube Milk',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Fragrant purple yam Halaya stirred with creamy condensed milk',
      sizePrices: {BrewItemSize.medium: 4500, BrewItemSize.large: 5500},
    ),
    BrewMenuItem(
      id: 'drip_cocoa',
      name: 'Cocoa',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Dark Dutch processed cocoa powder whisked with warm and cold milk',
      sizePrices: {BrewItemSize.medium: 5500, BrewItemSize.large: 6500},
    ),
    BrewMenuItem(
      id: 'drip_sea_salt_cocoa',
      name: 'Sea Salt Cocoa',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Rich chocolate cocoa topped with savory sea salt cream foam',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'drip_oreo_cocoa',
      name: 'Oreo Cocoa',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Double chocolate cocoa blended with crunchy chocolate cookies',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'drip_milky_biscoff',
      name: 'Milky Biscoff',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Cinnamon caramelized Lotus Biscoff spread blended with cold milk',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
    BrewMenuItem(
      id: 'drip_milky_nutella',
      name: 'Milky Nutella',
      category: 'Milky Series',
      subCategory: 'Classic Milky',
      description:
          'Thick hazelnut cocoa Nutella milk shake with chocolate drizzle',
      sizePrices: {BrewItemSize.medium: 6500, BrewItemSize.large: 7500},
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.initialCategory;
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.initForUser(widget.session?.uid);
    _favoritesService.addListener(_onFavoritesUpdated);
    _favoritesService.initForUser(widget.session?.uid);
    final menu = widget.counter?.menu(widget.shop.partner);
    if (menu == null) {
      _menuLoading = false;
      return;
    }
    _menuLoadingTimeout = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _menuLoading) {
        setState(() => _menuLoading = false);
      }
    });
    _menuSubscription = menu.listen(
      (items) {
        if (mounted) {
          _menuLoadingTimeout?.cancel();
          setState(() {
            _menuItems = items;
            _menuLoading = false;
          });
        }
      },
      onError: (Object _, StackTrace _) {
        _menuLoadingTimeout?.cancel();
        if (mounted) setState(() => _menuLoading = false);
      },
    );
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  void _onFavoritesUpdated() {
    if (mounted) setState(() {});
  }

  static int _pageCountFor(int total) =>
      total == 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;

  /// [_page], clamped to the pages [total] drinks actually fill.
  int _pageOf(int total) => _page.clamp(0, _pageCountFor(total) - 1);

  /// Moves to [page] and brings the reader back to the top of the list, where
  /// the new page starts — landing at the bottom of a fresh page would make
  /// them scroll up to see what they just paged to.
  void _goToPage(int page) {
    final total = _drinksForCurrentCategory.length;
    final target = page.clamp(0, _pageCountFor(total) - 1);
    if (target == _pageOf(total)) return;
    HapticFeedback.selectionClick();
    setState(() => _page = target);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
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
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _menuSubscription?.cancel();
    _menuLoadingTimeout?.cancel();
    _favoritesService.removeListener(_onFavoritesUpdated);
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
    if (b.contains('vietnam') && a.contains('vietnam')) return true;
    if (b.contains('tiramisu') && a.contains('tiramisu')) return true;
    if (b.contains('milky') && a.contains('milky')) return true;
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
    final fallback = widget.shop.partner == BrewPartner.a
        ? _dripFallbackItems
        : _fallbackItems;
    final source = _menuItems.isNotEmpty ? _menuItems : fallback;
    final matched = source
        .where((item) => _matchesCategory(item.category, _currentCategory))
        .toList(growable: false);
    if (matched.isNotEmpty) return matched;

    final fuzzy = source
        .where((item) {
          final c = (item.category ?? '').toLowerCase();
          final target = _currentCategory.toLowerCase();
          return c.contains(target) || target.contains(c);
        })
        .toList(growable: false);
    if (fuzzy.isNotEmpty) return fuzzy;

    return source;
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

  void _toggleFavorite(String itemId) {
    if (!_favoritesService.isFavorite(itemId) &&
        _favoritesService.hasReachedLimit) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF24382C),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: BrewColor.alert.withValues(alpha: 0.45)),
            ),
            content: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: BrewColor.alert),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You can save up to ${FavoritesService.maxFavorites} favorites. Remove one to add another.',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 12.5,
                      color: BrewColor.cream,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      return;
    }

    HapticFeedback.selectionClick();
    _favoritesService.toggleFavorite(itemId);
  }

  Widget _buildDrinkLoadingSliver() {
    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => const _DrinkLoadingCard(grid: true),
            childCount: 6,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _DrinkLoadingCard(),
          ),
          childCount: 4,
        ),
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
    final page = _pageOf(drinks.length);
    final pageCount = _pageCountFor(drinks.length);
    final displayedDrinks = drinks
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
              controller: _scrollController,
              slivers: [
                // Top App Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: topPadding + 8,
                      left: 16,
                      right: 16,
                      bottom: 12,
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
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0x66102418),
                              border: Border.all(
                                color: BrewColor.cream.withValues(alpha: 0.22),
                                width: 1.0,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 21,
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
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: BrewColor.cream,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.shop.displayName,
                                textAlign: TextAlign.center,
                                style: BrewType.rowBody.copyWith(
                                  fontSize: 14,
                                  color: BrewColor.cream.withValues(alpha: 0.6),
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
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isGridView
                                  ? const Color(0x66487A5E)
                                  : const Color(0x66102418),
                              border: Border.all(
                                color: _isGridView
                                    ? const Color(0x99487A5E)
                                    : BrewColor.cream.withValues(alpha: 0.22),
                                width: 1.0,
                              ),
                            ),
                            child: Icon(
                              _isGridView
                                  ? Icons.view_agenda_outlined
                                  : Icons.grid_view_rounded,
                              size: 21,
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {
                        _searchQuery = value;
                        _page = 0;
                      }),
                      textInputAction: TextInputAction.search,
                      style: BrewType.rowBody.copyWith(
                        fontSize: 16,
                        color: BrewColor.cream,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        hintText: 'Search this menu',
                        hintStyle: BrewType.rowBody.copyWith(
                          fontSize: 16,
                          color: BrewColor.cream.withValues(alpha: 0.5),
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
                        fillColor: const Color(0x99102418),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: Color(0xFF4DB38C),
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: Color(0xFF4DB38C),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: const BorderSide(
                            color: Color(0xFF6FD3AA),
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (subCategories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
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
                if (_menuLoading)
                  _buildDrinkLoadingSliver()
                else if (drinks.isEmpty)
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
                  // Screen 3: List View (Lazy Loaded)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final drink = displayedDrinks[index];
                        final isFav = _favoritesService.isFavorite(drink.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LazyReveal(
                            index: index,
                            child: _DrinkListCard(
                              drink: drink,
                              isFavorite: isFav,
                              onToggleFavorite: () {
                                _toggleFavorite(drink.id);
                              },
                              onAdd: () => _onAddToCart(drink),
                            ),
                          ),
                        );
                      }, childCount: displayedDrinks.length),
                    ),
                  )
                else
                  // Screen 4: 2-Column Grid View (Lazy Loaded)
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
                        final drink = displayedDrinks[index];
                        final isFav = _favoritesService.isFavorite(drink.id);
                        return _LazyReveal(
                          index: index,
                          child: _DrinkGridCard(
                            drink: drink,
                            isFavorite: isFav,
                            onToggleFavorite: () {
                              _toggleFavorite(drink.id);
                            },
                            onAdd: () => _onAddToCart(drink),
                          ),
                        );
                      }, childCount: displayedDrinks.length),
                    ),
                  ),

                // Page controls. Shown only when there is more than one page,
                // so a short category reads as a complete list rather than as
                // "page 1 of 1".
                if (!_menuLoading && pageCount > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _PaginationBar(
                        page: page,
                        pageCount: pageCount,
                        total: drinks.length,
                        pageSize: _pageSize,
                        onPage: _goToPage,
                      ),
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

/// Numbered page controls under a category's drinks: where the reader is
/// ("Showing 7–12 of 15 drinks"), Prev and Next, and the page numbers to jump
/// straight to one. Past seven pages the middle collapses to ellipses around
/// the current page, so the row never outgrows a phone.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  /// Zero-based.
  final int page;
  final int pageCount;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  /// Page numbers to draw (zero-based), with null standing for an ellipsis.
  List<int?> get _slots {
    if (pageCount <= 7) return [for (var i = 0; i < pageCount; i++) i];
    final start = math.max(1, math.min(page - 1, pageCount - 4));
    final end = math.min(pageCount - 2, math.max(page + 1, 3));
    return [
      0,
      if (start > 1) null,
      for (var i = start; i <= end; i++) i,
      if (end < pageCount - 2) null,
      pageCount - 1,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final first = page * pageSize + 1;
    final last = math.min(total, (page + 1) * pageSize);

    return Column(
      children: [
        Text(
          'Showing $first–$last of $total drinks',
          style: BrewType.mono.copyWith(
            fontSize: 11,
            letterSpacing: 0.5,
            color: BrewColor.cream.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PageButton(
              semanticsLabel: 'Previous page',
              onTap: page > 0 ? () => onPage(page - 1) : null,
              child: const Icon(Icons.chevron_left_rounded, size: 20),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final slot in _slots)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: slot == null
                            ? SizedBox(
                                width: 20,
                                child: Text(
                                  '…',
                                  textAlign: TextAlign.center,
                                  style: BrewType.mono.copyWith(
                                    color: BrewColor.cream.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              )
                            : _PageButton(
                                semanticsLabel: 'Page ${slot + 1}',
                                selected: slot == page,
                                onTap: slot == page ? null : () => onPage(slot),
                                child: Text('${slot + 1}'),
                              ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _PageButton(
              semanticsLabel: 'Next page',
              onTap: page < pageCount - 1 ? () => onPage(page + 1) : null,
              child: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.semanticsLabel,
    required this.child,
    this.onTap,
    this.selected = false,
  });

  final String semanticsLabel;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = selected
        ? BrewColor.field
        : BrewColor.cream.withValues(alpha: enabled ? 0.9 : 0.3);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled || selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6FD3AA) : const Color(0x33487A5E),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6FD3AA)
                  : const Color(0x66487A5E),
              width: 0.9,
            ),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: ink),
            child: DefaultTextStyle.merge(
              style: BrewType.mono.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
              child: child,
            ),
          ),
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
    padding: const EdgeInsets.only(right: 10, bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3A9E7C) : const Color(0x66102418),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF55C29C)
                : BrewColor.cream.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: BrewType.title.copyWith(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: BrewColor.cream,
          ),
        ),
      ),
    ),
  );
}

String? _drinkFallbackAsset(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('avalanche') ||
      lower.contains('dirty') ||
      lower.contains('biscoff')) {
    return 'assets/images/dirty_avalanche.jpg';
  } else if (lower.contains('americano') ||
      lower.contains('barista') ||
      lower.contains('espresso')) {
    return 'assets/images/classic_coffees/americano.jpg';
  } else if (lower.contains('spanish') || lower.contains('español')) {
    return 'assets/images/classic_coffees/spanish_latte.jpg';
  } else if (lower.contains('salted caramel') ||
      lower.contains('salty cream') ||
      lower.contains('sea salt')) {
    return 'assets/images/classic_coffees/salted_caramel.jpg';
  } else if (lower.contains('caramel macchiato') ||
      lower.contains('toffee nut')) {
    return 'assets/images/classic_coffees/caramel_macchiato.jpg';
  } else if (lower.contains('hazelnut') ||
      lower.contains('almond') ||
      lower.contains('peanut')) {
    return 'assets/images/classic_coffees/hazelnut_macchiato.jpg';
  } else if (lower.contains('vanilla') ||
      lower.contains('vienna') ||
      lower.contains('velvet') ||
      lower.contains('dolce')) {
    return 'assets/images/classic_coffees/vanilla_macchiato.jpg';
  } else if (lower.contains('mocha almond')) {
    return 'assets/images/classic_coffees/mocha_almond.jpg';
  } else if (lower.contains('mocha') ||
      lower.contains('cocoa') ||
      lower.contains('swissmiss')) {
    return 'assets/images/classic_coffees/cafe_mocha.jpg';
  } else if (lower.contains('latte') || lower.contains('matcha')) {
    return 'assets/images/classic_coffees/cafe_latte.jpg';
  } else if (lower.contains('vietnam') ||
      lower.contains('sữa đá') ||
      lower.contains('egg')) {
    return 'assets/menu/drip_redesigned/drip_menu_1_specials.png';
  } else if (lower.contains('tiramisu')) {
    return 'assets/images/classic_coffees/caramel_macchiato.jpg';
  } else if (lower.contains('milky') ||
      lower.contains('milk') ||
      lower.contains('ube')) {
    return 'assets/menu/drip_redesigned/drip_menu_4_milky_series.png';
  } else if (lower.contains('lemon')) {
    return 'assets/menu/seven_redesigned/seven_menu_7_lemonade.png';
  } else if (lower.contains('tea') ||
      lower.contains('fruit') ||
      lower.contains('refresher') ||
      lower.contains('cooler') ||
      lower.contains('berry') ||
      lower.contains('mango') ||
      lower.contains('acai') ||
      lower.contains('peach')) {
    return 'assets/menu/seven_redesigned/seven_menu_6_refreshers.png';
  } else if (lower.contains('pastry') ||
      lower.contains('bakery') ||
      lower.contains('croissant') ||
      lower.contains('scone')) {
    return 'assets/images/classic_coffees/mocha_almond.jpg';
  }
  return 'assets/images/classic_coffees/americano.jpg';
}

class _LazyReveal extends StatefulWidget {
  const _LazyReveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_LazyReveal> createState() => _LazyRevealState();
}

class _LazyRevealState extends State<_LazyReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BrewMotion.staggerItem,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;

    if (_reducedMotion) {
      _controller.value = 1;
      return;
    }

    Future<void>.delayed(
      Duration(milliseconds: math.min(widget.index, 5) * 45),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(_controller.value);
        if (_reducedMotion) return Opacity(opacity: progress, child: child);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * BrewMotion.staggerRise),
            child: child,
          ),
        );
      },
    );
  }
}

class _DrinkImage extends StatelessWidget {
  const _DrinkImage({
    required this.bytes,
    required this.icon,
    required this.accentColor,
    required this.width,
    required this.height,
  });

  final Uint8List? bytes;
  final IconData icon;
  final Color accentColor;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
    if (imageBytes == null) {
      return _DrinkImageLoadingPlaceholder(
        icon: icon,
        accentColor: accentColor,
        width: width,
        height: height,
        animate: false,
      );
    }

    return Image.memory(
      imageBytes,
      width: width,
      height: height,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        if (frame != null) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: BrewMotion.imageReveal,
            curve: BrewMotion.crossFadeCurve,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: child,
          );
        }
        return _DrinkImageLoadingPlaceholder(
          icon: icon,
          accentColor: accentColor,
          width: width,
          height: height,
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _DrinkImageLoadingPlaceholder(
            icon: icon,
            accentColor: accentColor,
            width: width,
            height: height,
            animate: false,
          ),
    );
  }
}

class _DrinkImageLoadingPlaceholder extends StatefulWidget {
  const _DrinkImageLoadingPlaceholder({
    required this.icon,
    required this.accentColor,
    required this.width,
    required this.height,
    this.animate = true,
  });

  final IconData icon;
  final Color accentColor;
  final double width;
  final double height;
  final bool animate;

  @override
  State<_DrinkImageLoadingPlaceholder> createState() =>
      _DrinkImageLoadingPlaceholderState();
}

class _DrinkImageLoadingPlaceholderState
    extends State<_DrinkImageLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion || !widget.animate) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _reducedMotion || !widget.animate
            ? 0.35
            : (math.sin(_controller.value * math.pi * 2) + 1) / 2;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0x1A091A11),
              widget.accentColor.withValues(alpha: 0.24),
              pulse * 0.55,
            ),
            gradient: LinearGradient(
              begin: Alignment(-1 + pulse * 2, -1),
              end: Alignment(pulse * 2, 1),
              colors: [
                widget.accentColor.withValues(alpha: 0.12),
                const Color(0x331C3A29),
                widget.accentColor.withValues(alpha: 0.22),
              ],
            ),
          ),
          child: Center(
            child: Opacity(
              opacity: 0.35 + pulse * 0.4,
              child: Icon(
                widget.icon,
                size: widget.width.isFinite && widget.height.isFinite
                    ? math.min(widget.width, widget.height) * 0.42
                    : 36,
                color: widget.accentColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DrinkLoadingCard extends StatelessWidget {
  const _DrinkLoadingCard({this.grid = false});

  final bool grid;

  @override
  Widget build(BuildContext context) {
    const accentColor = BrewColor.sageLight;
    final image = _DrinkImageLoadingPlaceholder(
      icon: Icons.local_cafe_outlined,
      accentColor: accentColor,
      width: grid ? double.infinity : 76,
      height: grid ? double.infinity : 76,
    );

    return Container(
      height: grid ? null : 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xD90F2418),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BrewColor.cream.withValues(alpha: 0.12)),
      ),
      child: grid
          ? Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: image,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 82,
                    height: 12,
                    decoration: BoxDecoration(
                      color: BrewColor.cream.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 54,
                    height: 10,
                    decoration: BoxDecoration(
                      color: BrewColor.cream.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: image,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 130,
                        height: 14,
                        decoration: BoxDecoration(
                          color: BrewColor.cream.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 92,
                        height: 22,
                        decoration: BoxDecoration(
                          color: BrewColor.cream.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
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
  const _DrinkListCard({
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
          color: const Color(0xD90F2418),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: BrewColor.cream.withValues(alpha: 0.14),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drink Emblem / Image
            Builder(
              builder: (context) {
                final imageBytes = drink.menuItem.imageBytes;

                return Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        drink.accentColor.withValues(alpha: 0.2),
                        const Color(0x1A091A11),
                      ],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Builder(
                      builder: (context) {
                        return _DrinkImage(
                          bytes: imageBytes,
                          icon: drink.icon,
                          accentColor: drink.accentColor,
                          width: 76,
                          height: 76,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 14),

            // Drink Details: name over the M / L price tiles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    drink.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: BrewType.title.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: BrewColor.cream,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DrinkPriceStrip(
                    mediumPrice: drink.mediumPrice,
                    largePrice: drink.largePrice,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Favorite heart toggle button
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleFavorite,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 22,
                  color: isFavorite
                      ? const Color(0xFFE56B6F)
                      : BrewColor.cream.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Quick '+' add button
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF3A9E7C),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x553A9E7C), blurRadius: 10),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 24,
                  color: Colors.white,
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
                    if (imageBytes != null) {
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
                          child: _DrinkImage(
                            bytes: imageBytes,
                            icon: drink.icon,
                            accentColor: drink.accentColor,
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
              maxLines: 2,
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _DrinkPriceStrip(
                    mediumPrice: drink.mediumPrice,
                    largePrice: drink.largePrice,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
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

/// A price is a small two-column table, not a run-on sentence. Each size sits
/// directly above its amount, so prices stay aligned in both list and grid
/// cards at narrow phone widths.
class _DrinkPriceStrip extends StatelessWidget {
  const _DrinkPriceStrip({
    required this.mediumPrice,
    required this.largePrice,
    this.compact = false,
  });

  final String mediumPrice;
  final String largePrice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final oneSize = mediumPrice == largePrice;
    final gap = compact ? 4.0 : 8.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _DrinkPriceTile(
              label: oneSize ? 'ONE SIZE' : 'M',
              price: mediumPrice,
              compact: compact,
            ),
          ),
          if (!oneSize) ...[
            SizedBox(width: gap),
            Expanded(
              child: _DrinkPriceTile(
                label: 'L',
                price: largePrice,
                compact: compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrinkPriceTile extends StatelessWidget {
  const _DrinkPriceTile({
    required this.label,
    required this.price,
    required this.compact,
  });

  final String label;
  final String price;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 34 : 46),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0x66184030),
        borderRadius: BorderRadius.circular(compact ? 7 : 11),
        border: Border.all(color: BrewColor.cream.withValues(alpha: 0.12)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: BrewType.rowBody.copyWith(
                fontSize: compact ? 8.5 : 12,
                fontWeight: FontWeight.w600,
                color: BrewColor.cream.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: compact ? 1 : 0),
            Text(
              price,
              style: BrewType.title.copyWith(
                fontSize: compact ? 11 : 17,
                fontWeight: FontWeight.w800,
                color: BrewColor.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
