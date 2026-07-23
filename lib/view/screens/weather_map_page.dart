import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/favorites_service.dart';

// --- CLASA DE REZULTAT PENTRU PAGINA HARTĂ ---
class MapLocationResult {
  final LatLng coords;
  final String? name;
  MapLocationResult({required this.coords, this.name});
}

// --- WIDGET PENTRU PAGINA HARTĂ ---
class WeatherMapPage extends StatefulWidget {
  final void Function(LatLng coords, String? name)? onSelection;
  const WeatherMapPage({super.key, this.onSelection});

  @override
  State<WeatherMapPage> createState() => _WeatherMapPageState();
}

// --- PAGINA HARTĂ PENTRU SELECȚIA ORAȘULUI ---
class _WeatherMapPageState extends State<WeatherMapPage> {
  LatLng _center = const LatLng(44.43, 26.10); // Default: București
  LatLng? _selected;
  String? _selectedName;
  bool _isResolvingName = false;
  
  // STARE FAVORIT (NOU)
  bool _isLocationFavorite = false;
  
  final MapController _mapController = MapController();
  final FavoritesService _favService = FavoritesService();
  final TextEditingController _searchController = TextEditingController();

  // SETĂM POZIȚIA INIȚIALĂ A HARTII
  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
  }

  // --- LOGICĂ GPS ---
  Future<void> _moveToCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('GPS-ul este oprit.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnack('Permisiunea de locație a fost refuzată.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnack('Permisiunea de locație este blocată permanent.');
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      final newCenter = LatLng(position.latitude, position.longitude);
      
      setState(() => _center = newCenter);
      _mapController.move(newCenter, 15.0);
      
      // Selectăm automat locația curentă și verificăm dacă e favorită
      _onTap(TapPosition(Offset.zero, Offset.zero), newCenter);

    } catch (e) {
      debugPrint('Eroare locație: $e');
    }
  }

  // --- LOGICĂ CĂUTARE ---
  Future<void> _searchCity(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus(); // Ascundem tastatura
    
    setState(() => _isResolvingName = true);

    try {
      final url = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(trimmed)}&count=1&language=en&format=json',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) throw Exception('Eroare API');

      final data = jsonDecode(res.body);
      if (data['results'] == null || data['results'].isEmpty) {
        _showSnack('Orașul nu a fost găsit.');
        setState(() => _isResolvingName = false);
        return;
      }

      final result = data['results'][0];
      final double lat = (result['latitude'] as num).toDouble();
      final double lon = (result['longitude'] as num).toDouble();
      final String name = result['name'];
      final String? country = result['country'];
      
      final fullName = country != null ? '$name, $country' : name;
      final newLatLng = LatLng(lat, lon);

      // Mutăm harta la noua locație
      _mapController.move(newLatLng, 12.0);

      setState(() {
        _selected = newLatLng;
        _selectedName = fullName;
        _isResolvingName = false;
        _center = newLatLng;
      });
      
      // Verificăm imediat dacă acest oraș căutat e deja favorit
      _checkFavoriteStatus();

    } catch (e) {
      _showSnack('Eroare la căutare.');
      setState(() => _isResolvingName = false);
    }
  }

  // --- METODĂ SNACKBAR ---
  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
    }
  }

  // --- LOGICĂ TAP PE HARTĂ ---
  Future<void> _onTap(TapPosition tapPos, LatLng latLng) async {
    setState(() {
      _selected = latLng;
      _selectedName = null;
      _isResolvingName = true;
      _isLocationFavorite = false; // Resetăm starea vizuală temporar
    });

    // Începem verificarea dacă e favorit (chiar înainte să avem numele)
    _checkFavoriteStatus();

    final name = await _reverseGeocode(latLng.latitude, latLng.longitude);

    setState(() {
      _selectedName = name;
      _isResolvingName = false;
    });
    
    // Verificăm din nou după ce avem numele (pentru siguranță)
    _checkFavoriteStatus();
  }

  // --- LOGICĂ VERIFICARE FAVORIT (NOU) ---
  Future<void> _checkFavoriteStatus() async {
    if (_selected == null) return;
    
    final favorites = await _favService.getFavorites();
    // Verificăm dacă există un oraș cu coordonate foarte apropiate (ca să evităm erori mici de float)
    final isFav = favorites.any((city) {
      final double diffLat = (city.lat - _selected!.latitude).abs();
      final double diffLon = (city.lon - _selected!.longitude).abs();
      return diffLat < 0.001 && diffLon < 0.001; 
    });

    if (mounted) {
      setState(() {
        _isLocationFavorite = isFav;
      });
    }
  }

  // --- LOGICĂ COMUTARE FAVORIT (ADD/REMOVE) ---
  Future<void> _toggleFavorite() async {
    if (_selected == null) return;
    
    final String nameToSave = _selectedName ?? 'Locație necunoscută';
    final cityObj = FavoriteCity(
      name: nameToSave,
      lat: _selected!.latitude,
      lon: _selected!.longitude,
    );

    if (_isLocationFavorite) {
      // Dacă E deja favorit -> ÎL ȘTERGEM
      await _favService.removeFavorite(cityObj);
      setState(() => _isLocationFavorite = false);
      _showSnack('Eliminat din favorite.');
    } else {
      // Dacă NU E favorit -> ÎL ADĂUGĂM
      await _favService.addFavorite(cityObj);
      setState(() => _isLocationFavorite = true);
      _showSnack('Adăugat la favorite! ❤️');
    }
  }

  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2');
      final res = await http.get(url, headers: {'User-Agent': 'WeatherApp/1.0'});
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final address = data['address'] ?? {};
      final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'];
      final country = address['country'];
      if (city != null && country != null) return '$city, $country';
      return city ?? country;
    } catch (_) {
      return null;
    }
  }

  // --- CONFIRMĂ SELECȚIA ȘI ÎNCHIDE PAGINA ---
  void _confirmSelection() {
    if (_selected == null) return;
    if (widget.onSelection != null) {
      widget.onSelection!(_selected!, _selectedName);
    } else {
      Navigator.of(context).pop(MapLocationResult(coords: _selected!, name: _selectedName));
    }
  }

  // --- BUILD WIDGET ---
  @override
  Widget build(BuildContext context) {
    final subtitle = _selected == null
        ? 'Atinge harta pentru a alege o locație'
        : _isResolvingName
            ? 'Se caută adresa...'
            : _selectedName ?? 'Selectat';

    return Scaffold(
      backgroundColor: Colors.blue[50],
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. HARTA
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 10.0,
                onTap: _onTap,
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.app'),
                if (_selected != null)
                  MarkerLayer(markers: [Marker(point: _selected!, width: 40, height: 40, child: const Icon(Icons.location_pin, size: 40, color: Colors.redAccent))]),
              ],
            ),
          ),

          // 2. BARA DE CĂUTARE
          Positioned(
            top: 50, 
            left: 20, 
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchCity,
                      decoration: InputDecoration(
                        hintText: 'Caută oraș pe hartă...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Colors.blueAccent),
                          onPressed: () => _searchCity(_searchController.text),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.blueAccent),
                    onPressed: _moveToCurrentLocation,
                    tooltip: "Locația Mea",
                  ),
                ),
              ],
            ),
          ),

          // 3. PANOU DE JOS
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: const Offset(0, -4))],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, color: Colors.grey[300], margin: const EdgeInsets.only(bottom: 10)),
                    Text('Locație Selectată', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        // BUTON FAVORITE (Inimă plină sau goală)
                        if (_selected != null) 
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: IconButton.filled(
                              onPressed: _toggleFavorite, // Apelăm funcția de toggle
                              style: IconButton.styleFrom(
                                backgroundColor: _isLocationFavorite 
                                    ? Colors.pinkAccent.withValues(alpha: 0.1) // Fundal roz dacă e favorit
                                    : Colors.grey[100], // Fundal gri dacă nu e
                              ),
                              icon: Icon(
                                // AICI E MODIFICAREA VIZUALĂ:
                                _isLocationFavorite ? Icons.favorite : Icons.favorite_border,
                                color: _isLocationFavorite ? Colors.pinkAccent : Colors.grey,
                              ),
                            ),
                          ),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _selected == null ? null : _confirmSelection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check),
                            label: const Text('Vezi Vremea Aici'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
