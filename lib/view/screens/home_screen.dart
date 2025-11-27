import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'weather_map_page.dart';
import 'profile_screen.dart';
import 'favorites_screen.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  int _currentIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  String _locationLabel = 'Se încarcă...';
  double? _currentTemp;
  String _todayDescription = '';
  String _todayEmoji = '☀️';
  double? _windSpeed;
  int? _humidity;
  double? _pressure;
  double? _todayHigh;
  double? _todayLow;
  String _timeLabel = '--:--';
  
  List<_DailyForecast> _dailyForecast = [];
  List<_HourlyForecast> _hourlyForecast = [];

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  // --- LOGICĂ GPS ---
  Future<void> _determinePosition() async {
    setState(() => _isLoading = true);
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _searchAndLoadWeather('Bucuresti');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _searchAndLoadWeather('Bucuresti');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _searchAndLoadWeather('Bucuresti');
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      await _loadWeatherByCoords(
        lat: position.latitude,
        lon: position.longitude,
        labelFromGeo: 'Locația Ta',
      );
      _updateCityNameFromCoords(position.latitude, position.longitude);
    } catch (e) {
      _searchAndLoadWeather('Bucuresti');
    }
  }

  Future<void> _updateCityNameFromCoords(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2');
      final res = await http.get(url, headers: {'User-Agent': 'WeatherApp/1.0'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final address = data['address'];
        String city = address['city'] ?? address['town'] ?? address['village'] ?? 'Locația Ta';
        setState(() => _locationLabel = city);
      }
    } catch (_) {}
  }

  // --- API CALLS ---
  Future<void> _searchAndLoadWeather(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final geoUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(trimmed)}&count=1&language=en&format=json',
      );
      final geoRes = await http.get(geoUrl);
      if (geoRes.statusCode != 200) throw Exception('Geocoding failed');
      final geoJson = jsonDecode(geoRes.body);
      if (geoJson['results'] == null || geoJson['results'].isEmpty) throw Exception('Orașul nu a fost găsit');

      final result = geoJson['results'][0];
      final double lat = (result['latitude'] as num).toDouble();
      final double lon = (result['longitude'] as num).toDouble();
      final String name = result['name'] ?? 'Unknown';
      final String? country = result['country'];

      await _loadWeatherByCoords(
        lat: lat,
        lon: lon,
        labelFromGeo: country == null ? name : '$name, $country',
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWeatherByCoords({
    required double lat,
    required double lon,
    String? labelFromGeo,
  }) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // URL MODIFICAT: Am adăugat "is_day" la hourly
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current_weather=true'
        '&hourly=temperature_2m,weathercode,relativehumidity_2m,surface_pressure,is_day' // <--- AICI E CHEIA (is_day)
        '&daily=temperature_2m_max,temperature_2m_min,weathercode,windspeed_10m_max,precipitation_probability_max'
        '&forecast_days=7'
        '&timezone=auto',
      );
      final weatherRes = await http.get(weatherUrl);
      if (weatherRes.statusCode != 200) throw Exception('Weather API failed');

      final weatherJson = jsonDecode(weatherRes.body);
      
      // 1. Current Weather
      final current = weatherJson['current_weather'];
      final double temp = (current['temperature'] as num).toDouble();
      final int code = (current['weathercode'] as num).toInt();
      final double wind = (current['windspeed'] as num).toDouble();
      // Aflăm dacă e zi sau noapte chiar acum (1 = zi, 0 = noapte)
      final int isDayNow = (current['is_day'] as num).toInt(); 
      
      String niceTime = '--:--';
      if (current['time'] != null) {
        final d = DateTime.parse(current['time']);
        niceTime = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }

      // 2. Hourly Data Logic
      final hourlyData = weatherJson['hourly'];
      final List hTimes = hourlyData['time'];
      final List hTemps = hourlyData['temperature_2m'];
      final List hCodes = hourlyData['weathercode'];
      final List hIsDay = hourlyData['is_day'] ?? []; // Lista cu 0/1 pentru fiecare oră
      
      final now = DateTime.now();
      int startIndex = 0;
      for(int i=0; i<hTimes.length; i++) {
        if (DateTime.parse(hTimes[i]).hour == now.hour && DateTime.parse(hTimes[i]).day == now.day) {
          startIndex = i;
          break;
        }
      }

      final List<_HourlyForecast> tempHourlyList = [];
      for (int i = startIndex; i < startIndex + 24 && i < hTimes.length; i++) {
         final dt = DateTime.parse(hTimes[i]);
         final tTemp = (hTemps[i] as num).toDouble();
         final tCode = (hCodes[i] as num).toInt();
         
         // Luăm flag-ul de zi/noapte specific orei respective
         final bool isHourDay = (hIsDay.isNotEmpty && i < hIsDay.length) 
            ? (hIsDay[i] == 1) 
            : true; // Fallback
         
         final String hourLabel = '${dt.hour.toString().padLeft(2,'0')}:00';
         
         tempHourlyList.add(_HourlyForecast(
           time: i == startIndex ? 'Acum' : hourLabel,
           temp: '${tTemp.round()}°',
           icon: _emojiForCode(tCode, isDay: isHourDay), // <--- Trimitem isDay aici
         ));
      }

      // 3. Extra details
      int? humidity;
      double? pressure;
      if (hourlyData['relativehumidity_2m'] != null && hourlyData['relativehumidity_2m'].isNotEmpty) {
        humidity = (hourlyData['relativehumidity_2m'][startIndex] as num).toInt();
      }
      if (hourlyData['surface_pressure'] != null && hourlyData['surface_pressure'].isNotEmpty) {
        pressure = (hourlyData['surface_pressure'][startIndex] as num).toDouble();
      }

      // 4. Daily Data
      final daily = weatherJson['daily'];
      final List dTimes = daily['time'];
      final List dMaxTemps = daily['temperature_2m_max'];
      final List dMinTemps = daily['temperature_2m_min'];
      final List dCodes = daily['weathercode'];
      final List dWinds = daily['windspeed_10m_max'];
      final List dRains = daily['precipitation_probability_max'];

      final List<_DailyForecast> tempDailyList = [];
      const weekdayNames = ['Lun', 'Mar', 'Mie', 'Joi', 'Vin', 'Sâm', 'Dum'];

      for (int i = 0; i < dTimes.length; i++) {
        final DateTime date = DateTime.parse(dTimes[i]);
        final int wCode = (dCodes[i] as num).toInt();
        final double tMax = (dMaxTemps[i] as num).toDouble();
        final double tMin = (dMinTemps[i] as num).toDouble();
        final double wSpeed = (dWinds[i] as num).toDouble();
        final int rainProb = (dRains[i] as num).toInt();
        
        final String dayLabel = i == 0 ? 'Azi' : weekdayNames[date.weekday - 1];

        tempDailyList.add(_DailyForecast(
          day: dayLabel,
          fullDate: '${date.day}/${date.month}',
          icon: _emojiForCode(wCode, isDay: true), // Pentru daily, arătăm mereu iconița de zi
          high: '${tMax.round()}°',
          low: '${tMin.round()}°',
          description: _descriptionForCode(wCode),
          windSpeed: '${wSpeed.round()} km/h',
          rainChance: '$rainProb%',
        ));
      }

      setState(() {
        _locationLabel = labelFromGeo ?? 'Locație Custom';
        _currentTemp = temp;
        _todayDescription = _descriptionForCode(code);
        // Folosim isDayNow pentru iconița mare principală
        _todayEmoji = _emojiForCode(code, isDay: isDayNow == 1); 
        _windSpeed = wind;
        _humidity = humidity;
        _pressure = pressure;
        _todayHigh = (dMaxTemps[0] as num).toDouble();
        _todayLow = (dMinTemps[0] as num).toDouble();
        _timeLabel = niceTime;
        _dailyForecast = tempDailyList;
        _hourlyForecast = tempHourlyList;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- CALLBACKS ---
  void _onMapLocationSelected(LatLng coords, String? name) {
    setState(() => _currentIndex = 0);
    _loadWeatherByCoords(lat: coords.latitude, lon: coords.longitude, labelFromGeo: name);
  }

  void _onFavoriteSelected(double lat, double lon, String name) {
    setState(() => _currentIndex = 0);
    _loadWeatherByCoords(lat: lat, lon: lon, labelFromGeo: name);
  }

  // --- HELPERE ICONIȚE ---
  
  // Acum acceptă parametrul `isDay` (default true)
  String _emojiForCode(int code, {bool isDay = true}) {
    if (code == 0) {
      return isDay ? '☀️' : '🌙'; // Senin: Soare sau Lună
    }
    if (code == 1 || code == 2 || code == 3) {
      return isDay ? '⛅' : '☁️'; // Nori: Soare cu nori sau Nori simpli (noaptea)
    }
    if (code <= 48) return '🌫'; // Ceață
    if (code <= 67) return '🌦'; // Ploaie
    if (code <= 77) return '❄️'; // Ninsoare
    if (code <= 82) return '🌧'; // Averse
    if (code >= 95) return '⛈'; // Furtună
    return '☁️';
  }

  String _descriptionForCode(int code) {
    if (code == 0) return 'Senin';
    if (code == 1) return 'Preponderent senin';
    if (code == 2) return 'Parțial noros';
    if (code == 3) return 'Înnorat';
    if (code <= 48) return 'Ceață';
    if (code <= 67) return 'Ploaie';
    if (code <= 77) return 'Ninsoare';
    if (code <= 82) return 'Averse';
    if (code >= 95) return 'Furtună';
    return 'Necunoscut';
  }

  // --- UI COMPONENTS ---

  void _showForecastSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 20),
                  const Text("Prognoza pe 7 Zile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: _dailyForecast.length,
                      itemBuilder: (context, index) {
                        final item = _dailyForecast[index];
                        return ExpansionTile(
                          leading: Text(item.icon, style: const TextStyle(fontSize: 24)),
                          title: Text('${item.day} • ${item.description}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Max: ${item.high}  Min: ${item.low}'),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              color: Colors.blue[50],
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(children: [const Icon(Icons.water_drop, color: Colors.blue), Text("Ploaie: ${item.rainChance}")]),
                                  Column(children: [const Icon(Icons.air, color: Colors.grey), Text("Vânt: ${item.windSpeed}")]),
                                  Column(children: [const Icon(Icons.calendar_today, color: Colors.orange), Text(item.fullDate)]),
                                ],
                              ),
                            )
                          ],
                        );
                      },
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

  Widget _buildHourlyList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            "Următoarele 24h",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _hourlyForecast.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final item = _hourlyForecast[index];
              return Container(
                width: 70,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: index == 0 ? Colors.blueAccent : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.time,
                      style: TextStyle(
                        fontSize: 13,
                        color: index == 0 ? Colors.white70 : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(item.icon, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 8),
                    Text(
                      item.temp,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: index == 0 ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Acasă'),
            BottomNavigationBarItem(icon: Icon(Icons.favorite_rounded), label: 'Favorite'),
            BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Hartă'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profil'),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(),
          FavoritesScreen(onCitySelected: _onFavoriteSelected),
          WeatherMapPage(onSelection: _onMapLocationSelected),
          const ProfileScreen(),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    final bool hasToday = _currentTemp != null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Salut,', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
                    Text('WeatherApp', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ],
                ),
                const Icon(Icons.cloud, color: Colors.blueAccent, size: 40),
              ],
            ),
            const SizedBox(height: 24),

            // Search + GPS
            Row(
  children: [
    Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
             BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: TextField(
          controller: _searchController,
          // 1. Asta schimbă tasta "Enter" de pe tastatură în "Lupă/Search"
          textInputAction: TextInputAction.search, 
          
          decoration: InputDecoration(
            hintText: 'Caută oraș...',
            hintStyle: const TextStyle(color: Colors.black38),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            
            // 2. Folosim suffixIcon (dreapta) ca Buton
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, color: Colors.blueAccent),
              onPressed: () {
                // Ascundem tastatura când apăsăm pe lupă
                FocusScope.of(context).unfocus(); 
                _searchAndLoadWeather(_searchController.text);
              },
            ),
          ),
          
          // Funcționează și când dai "Search" de pe tastatură
          onSubmitted: (value) {
            FocusScope.of(context).unfocus();
            _searchAndLoadWeather(value);
          },
        ),
      ),
    ),
    
    const SizedBox(width: 10),
    
    // Butonul GPS (Rămâne la fel)
    Container(
      decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
             BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))
          ]
      ),
      child: IconButton(
        icon: const Icon(Icons.my_location, color: Colors.blueAccent),
        onPressed: _determinePosition,
        tooltip: "Locația Mea",
      ),
    )
  ],
),

            if (_isLoading) const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),

            const SizedBox(height: 24),

            if (hasToday) _buildTodayCard(),

            const SizedBox(height: 30),

            if (_hourlyForecast.isNotEmpty) 
              _buildHourlyList(),

            const SizedBox(height: 30),

            if (_dailyForecast.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _showForecastSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueAccent,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.calendar_month),
                  label: const Text("Vezi Prognoza pe 7 Zile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_locationLabel, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('$_timeLabel • $_todayDescription', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              Text(_todayEmoji, style: const TextStyle(fontSize: 32)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_currentTemp?.round()}°', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('H:${_todayHigh?.round()}°  L:${_todayLow?.round()}°', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDetailItem(Icons.air, '${_windSpeed?.round()} km/h'),
              _buildDetailItem(Icons.water_drop_outlined, '$_humidity%'),
              _buildDetailItem(Icons.speed, '${_pressure?.round()} hPa'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _HourlyForecast {
  final String time;
  final String temp;
  final String icon;
  _HourlyForecast({required this.time, required this.temp, required this.icon});
}

class _DailyForecast {
  final String day;
  final String fullDate;
  final String icon;
  final String high;
  final String low;
  final String description;
  final String windSpeed;
  final String rainChance;

  _DailyForecast({
    required this.day,
    required this.fullDate,
    required this.icon,
    required this.high,
    required this.low,
    required this.description,
    required this.windSpeed,
    required this.rainChance,
  });
}