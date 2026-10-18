import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized manager for customer favorite products.
///
/// Persists favorited product IDs per user in [SharedPreferences], and
/// broadcasts updates through a stream and [ValueListenable] so any screen
/// or card reacts immediately when a user hearts or unhearts an item.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();

  static final FavoritesService instance = FavoritesService._();

  static const String _prefPrefix = 'quickbrew_favorites_';
  static const int maxFavorites = 5;
  String _currentUid = 'guest';
  final Set<String> _favoriteIds = <String>{};
  bool _initialized = false;

  /// All currently favorited item IDs.
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// Number of favorited items.
  int get count => _favoriteIds.length;

  /// Whether the service has loaded the user's stored favorites.
  bool get isInitialized => _initialized;

  /// Binds the favorites store to the signed-in user's UID (or 'guest').
  Future<void> initForUser(String? uid) async {
    final effectiveUid = (uid != null && uid.trim().isNotEmpty)
        ? uid.trim()
        : 'guest';
    if (_initialized && _currentUid == effectiveUid) return;

    _currentUid = effectiveUid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored =
          prefs.getStringList('$_prefPrefix$_currentUid') ?? const [];
      _favoriteIds
        ..clear()
        ..addAll(stored);
    } catch (e) {
      debugPrint('FavoritesService: unable to read storage: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  /// Whether a specific item is in the user's favorites.
  bool isFavorite(String itemId) => _favoriteIds.contains(itemId);

  /// Whether another item can be added without removing one first.
  bool get hasReachedLimit => _favoriteIds.length >= maxFavorites;

  /// Toggles an item's favorite state and saves to disk.
  Future<bool> toggleFavorite(String itemId) async {
    final willBeFavorite = !_favoriteIds.contains(itemId);
    if (willBeFavorite && hasReachedLimit) return false;

    if (willBeFavorite) {
      _favoriteIds.add(itemId);
    } else {
      _favoriteIds.remove(itemId);
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        '$_prefPrefix$_currentUid',
        _favoriteIds.toList(),
      );
    } catch (e) {
      debugPrint('FavoritesService: unable to persist favorites: $e');
    }
    return willBeFavorite;
  }

  /// Explicitly adds an item to favorites.
  Future<void> addFavorite(String itemId) async {
    if (!_favoriteIds.contains(itemId) && hasReachedLimit) return;
    if (_favoriteIds.add(itemId)) {
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          '$_prefPrefix$_currentUid',
          _favoriteIds.toList(),
        );
      } catch (e) {
        debugPrint('FavoritesService: error writing add: $e');
      }
    }
  }

  /// Explicitly removes an item from favorites.
  Future<void> removeFavorite(String itemId) async {
    if (_favoriteIds.remove(itemId)) {
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          '$_prefPrefix$_currentUid',
          _favoriteIds.toList(),
        );
      } catch (e) {
        debugPrint('FavoritesService: error writing remove: $e');
      }
    }
  }

  /// Clears all favorites for the active user.
  Future<void> clearAll() async {
    if (_favoriteIds.isEmpty) return;
    _favoriteIds.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefPrefix$_currentUid');
    } catch (e) {
      debugPrint('FavoritesService: error clearing favorites: $e');
    }
  }
}
