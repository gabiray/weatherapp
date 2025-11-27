import 'package:flutter/material.dart';
import '../../services/favorites_service.dart';

class FavoritesScreen extends StatefulWidget {
  // Funcție callback: Când dăm click pe un oraș, trimitem datele înapoi la Home
  final Function(double lat, double lon, String name) onCitySelected;

  const FavoritesScreen({super.key, required this.onCitySelected});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesService _favService = FavoritesService();
  List<FavoriteCity> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  // Reîncărcăm lista de fiecare dată când pagina devine vizibilă
  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    final list = await _favService.getFavorites();
    setState(() {
      _favorites = list;
      _isLoading = false;
    });
  }

  Future<void> _deleteCity(FavoriteCity city) async {
    await _favService.removeFavorite(city);
    _loadFavorites(); // Reîncărcăm lista după ștergere
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        title: const Text("Orașe Favorite"),
        backgroundColor: Colors.blue[50],
        elevation: 0,
        actions: [
            IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                onPressed: _loadFavorites,
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 60, color: Colors.blueAccent.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text("Nu ai nicio locație salvată.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final city = _favorites[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.location_city, color: Colors.white),
                        ),
                        title: Text(city.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${city.lat.toStringAsFixed(2)}, ${city.lon.toStringAsFixed(2)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteCity(city),
                        ),
                        onTap: () {
                          // Aici e magia: trimitem datele înapoi la Home Screen
                          widget.onCitySelected(city.lat, city.lon, city.name);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}