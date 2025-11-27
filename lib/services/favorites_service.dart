import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteCity {
  final String name;
  final double lat;
  final double lon;

  FavoriteCity({required this.name, required this.lat, required this.lon});

  // Convertire pentru stocare (JSON)
  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lon': lon,
  };

  factory FavoriteCity.fromJson(Map<String, dynamic> json) {
    return FavoriteCity(
      name: json['name'],
      lat: json['lat'],
      lon: json['lon'],
    );
  }
}

class FavoritesService {
  static const String _key = 'favorite_cities';

  Future<List<FavoriteCity>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_key);
    if (data == null) return [];
    
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => FavoriteCity.fromJson(e)).toList();
  }

  Future<void> addFavorite(FavoriteCity city) async {
    final list = await getFavorites();
    // Evităm duplicatele
    if (!list.any((e) => e.name == city.name && e.lat == city.lat)) {
      list.add(city);
      await _saveList(list);
    }
  }

  Future<void> removeFavorite(FavoriteCity city) async {
    final list = await getFavorites();
    list.removeWhere((e) => e.name == city.name && e.lat == city.lat);
    await _saveList(list);
  }

  Future<void> _saveList(List<FavoriteCity> list) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}