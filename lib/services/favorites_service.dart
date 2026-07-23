import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteCity {
  final String name;
  final double lat;
  final double lon;

  // Constructor
  FavoriteCity({required this.name, required this.lat, required this.lon});

  // Convertire pentru stocare (JSON)
  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lon': lon,
  };

  // Creare din JSON
  factory FavoriteCity.fromJson(Map<String, dynamic> json) {
    return FavoriteCity(
      name: json['name'],
      lat: json['lat'],
      lon: json['lon'],
    );
  }
}

// Serviciu pentru gestionarea orașelor favorite
class FavoritesService {
  static const String _key = 'favorite_cities';
  static const String _migrationKey = 'favorites_migrated_to_firestore';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _favorites {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Trebuie să fii autentificat pentru a folosi favoritele.');
    }
    return _firestore.collection('users').doc(user.uid).collection('favorites');
  }

  Future<List<FavoriteCity>> getFavorites() async {
    await _migrateLocalFavorites();
    final snapshot = await _favorites.orderBy('name').get();
    return snapshot.docs.map((doc) => FavoriteCity.fromJson(doc.data())).toList();
  }

  Future<List<FavoriteCity>> _getLocalFavorites() async {
    final prefs = await SharedPreferences.getInstance(); 
    final String? data = prefs.getString(_key); 
    if (data == null) return [];
    
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => FavoriteCity.fromJson(e)).toList(); 
  }

  Future<void> addFavorite(FavoriteCity city) async {
    await _favorites.doc(_documentId(city)).set({
      ...city.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFavorite(FavoriteCity city) async {
    await _favorites.doc(_documentId(city)).delete();
  }

  String _documentId(FavoriteCity city) {
    return '${city.lat.toStringAsFixed(5)}_${city.lon.toStringAsFixed(5)}';
  }

  Future<void> _migrateLocalFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    final migrationKey = '${_migrationKey}_${user.uid}';
    if (prefs.getBool(migrationKey) ?? false) return;

    final localFavorites = await _getLocalFavorites();
    if (localFavorites.isNotEmpty) {
      final batch = _firestore.batch();
      for (final city in localFavorites) {
        batch.set(_favorites.doc(_documentId(city)), {
          ...city.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await prefs.setBool(migrationKey, true);
  }
}
