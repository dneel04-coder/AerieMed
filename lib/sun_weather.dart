import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


class SunTimes {
  final DateTime sunrise;
  final DateTime sunset;
  final Duration dayLength;

  const SunTimes({required this.sunrise, required this.sunset, required this.dayLength});
}

SunTimes? calcSunTimes(double lat, double lon, DateTime date) {
  // Julian date
  final jd = _julianDay(date);

  final rise = _sunriseSet(jd, lat, lon, rising: true);
  final set = _sunriseSet(jd, lat, lon, rising: false);
  if (rise == null || set == null) return null;

  final riseLocal = date.toLocal().copyWith(
    hour: rise.floor(),
    minute: ((rise - rise.floor()) * 60).round(),
    second: 0,
  );
  final setLocal = date.toLocal().copyWith(
    hour: set.floor(),
    minute: ((set - set.floor()) * 60).round(),
    second: 0,
  );
  return SunTimes(
    sunrise: riseLocal,
    sunset: setLocal,
    dayLength: setLocal.difference(riseLocal),
  );
}

double _julianDay(DateTime d) {
  final a = ((14 - d.month) / 12).floor();
  final y = d.year + 4800 - a;
  final m = d.month + 12 * a - 3;
  return d.day +
      ((153 * m + 2) / 5).floor() +
      365 * y +
      (y / 4).floor() -
      (y / 100).floor() +
      (y / 400).floor() -
      32045.0;
}

double? _sunriseSet(double jd, double lat, double lon, {required bool rising}) {
  const zenith = 90.833;
  final lngHour = lon / 15;
  final t = rising ? jd + (6 - lngHour) / 24 : jd + (18 - lngHour) / 24;

  final M = (0.9856 * t) - 3.289;
  double L = M + 1.916 * _sind(M) + 0.020 * _sind(2 * M) + 282.634;
  L = _wrap(L, 360);

  double ra = _atan2d(_cosd(23.439) * _sind(L), _cosd(L)) / 15;
  ra = _wrap(ra, 24);
  if (ra - _wrap(L / 15, 24) > 6) ra -= 12;
  if (_wrap(L / 15, 24) - ra > 6) ra += 12;

  final sinDec = _sind(23.439) * _sind(L);
  final cosDec = _cosd(_asind(sinDec));

  final cosH = (_cosd(zenith) - sinDec * _sind(lat)) / (cosDec * _cosd(lat));
  if (cosH > 1 || cosH < -1) return null;

  double h = rising ? 360 - _acosd(cosH) : _acosd(cosH);
  h /= 15;

  final t2 = h + ra - 0.06571 * t - 6.622;
  return _wrap(t2 - lngHour, 24);
}

double _sind(double d) => math.sin(d * math.pi / 180);
double _cosd(double d) => math.cos(d * math.pi / 180);
double _asind(double x) => math.asin(x) * 180 / math.pi;
double _acosd(double x) => math.acos(x) * 180 / math.pi;
double _atan2d(double y, double x) => math.atan2(y, x) * 180 / math.pi;
double _wrap(double v, double max) => v - max * (v / max).floor();


class WeatherData {
  final String condition;
  final double tempC;
  final double windSpeedMs;
  final int windDeg;
  final int humidity;
  final double visibility;
  final String cityName;
  final String fetchedAt;

  const WeatherData({
    required this.condition, required this.tempC, required this.windSpeedMs,
    required this.windDeg, required this.humidity, required this.visibility,
    required this.cityName, required this.fetchedAt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> j) => WeatherData(
        condition: (j['weather'] as List).first['description'] ?? '',
        tempC: ((j['main']['temp'] as num) - 273.15).toDouble(),
        windSpeedMs: (j['wind']['speed'] as num).toDouble(),
        windDeg: (j['wind']['deg'] as num).toInt(),
        humidity: (j['main']['humidity'] as num).toInt(),
        visibility: ((j['visibility'] as num?) ?? 10000).toDouble() / 1000,
        cityName: j['name'] ?? '',
        fetchedAt: DateTime.now().toLocal().toString().substring(0, 16),
      );

  String toJson() => json.encode({
        'condition': condition, 'tempC': tempC, 'windSpeedMs': windSpeedMs,
        'windDeg': windDeg, 'humidity': humidity, 'visibility': visibility,
        'cityName': cityName, 'fetchedAt': fetchedAt,
      });

  static WeatherData fromCacheJson(String s) {
    final m = json.decode(s);
    return WeatherData(
      condition: m['condition'], tempC: m['tempC'], windSpeedMs: m['windSpeedMs'],
      windDeg: m['windDeg'], humidity: m['humidity'], visibility: m['visibility'],
      cityName: m['cityName'], fetchedAt: m['fetchedAt'],
    );
  }

  String get windDir {
    const dirs = ['N','NE','E','SE','S','SW','W','NW','N'];
    return dirs[((windDeg + 22.5) / 45).floor() % 8];
  }
}


class SunWeatherScreen extends StatefulWidget {
  const SunWeatherScreen({super.key});

  @override
  State<SunWeatherScreen> createState() => _SunWeatherScreenState();
}

class _SunWeatherScreenState extends State<SunWeatherScreen> {
  SunTimes? _sunTimes;
  WeatherData? _weather;
  bool _loadingWeather = false;
  String _apiKey = '';
  double? _lat, _lon;
  String _locationLabel = '';

  @override
  void initState() {
    super.initState();
    _loadCache();
    _calcSunForNow();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('owm_api_key') ?? '';
      final cached = prefs.getString('weather_cache');
      if (cached != null) _weather = WeatherData.fromCacheJson(cached);
      _lat = prefs.getDouble('weather_lat');
      _lon = prefs.getDouble('weather_lon');
      _locationLabel = prefs.getString('weather_location_label') ?? '';
    });
    if (_lat != null && _lon != null) {
      _calcSunForCoords(_lat!, _lon!);
    }
  }

  void _calcSunForNow() {
    final now = DateTime.now();
    // Use stored coords, or default to 0,0 placeholder
    final lat = _lat ?? 0;
    final lon = _lon ?? 0;
    setState(() => _sunTimes = calcSunTimes(lat, lon, now));
  }

  void _calcSunForCoords(double lat, double lon) {
    setState(() => _sunTimes = calcSunTimes(lat, lon, DateTime.now()));
  }

  Future<void> _fetchFromGps() async {
    setState(() => _loadingWeather = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Permission denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      await _fetchWeather(pos.latitude, pos.longitude, 'GPS location');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _loadingWeather = false);
  }

  Future<void> _fetchWeather(double lat, double lon, String label) async {
    if (_apiKey.isEmpty) {
      _promptApiKey();
      return;
    }
    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = WeatherData.fromJson(json.decode(response.body));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('weather_cache', data.toJson());
        await prefs.setDouble('weather_lat', lat);
        await prefs.setDouble('weather_lon', lon);
        await prefs.setString('weather_location_label', label);
        if (mounted) {
          setState(() {
            _weather = data;
            _lat = lat; _lon = lon;
            _locationLabel = label;
          });
          _calcSunForCoords(lat, lon);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Weather fetch failed: $e')));
      }
    }
  }

  void _promptApiKey() {
    final ctrl = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('OpenWeatherMap API Key'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Free API key from openweathermap.org/api', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'API key', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              setState(() => _apiKey = ctrl.text.trim());
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('owm_api_key', _apiKey);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '--:--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sun & Weather'),
        actions: [
          IconButton(icon: const Icon(Icons.vpn_key_outlined), tooltip: 'API Key', onPressed: _promptApiKey),
          IconButton(
            icon: _loadingWeather
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: 'Fetch weather',
            onPressed: _loadingWeather ? null : _fetchFromGps,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sun card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.wb_sunny, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text('Sun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (_locationLabel.isNotEmpty) ...[
                    const Spacer(),
                    Text(_locationLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ]),
                const SizedBox(height: 16),
                if (_sunTimes == null)
                  const Text('Fetch weather or enter location to calculate sun times.',
                      style: TextStyle(color: Colors.grey)),
                if (_sunTimes != null)
                  Row(children: [
                    Expanded(child: _sunCell(Icons.wb_twilight, 'Sunrise', _fmt(_sunTimes!.sunrise))),
                    Expanded(child: _sunCell(Icons.nights_stay_outlined, 'Sunset', _fmt(_sunTimes!.sunset))),
                    Expanded(child: _sunCell(Icons.timelapse, 'Daylight',
                        '${_sunTimes!.dayLength.inHours}h ${_sunTimes!.dayLength.inMinutes.remainder(60)}m')),
                  ]),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // Weather card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.cloud_outlined),
                  const SizedBox(width: 8),
                  const Text('Weather', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (_weather != null) ...[
                    const Spacer(),
                    Text('${_weather!.cityName}  •  ${_weather!.fetchedAt}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ]),
                const SizedBox(height: 12),
                if (_weather == null && !_loadingWeather)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('No weather data cached.',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _fetchFromGps,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('Fetch from GPS'),
                    ),
                    const SizedBox(height: 8),
                    Text('Requires OpenWeatherMap free API key.${_apiKey.isEmpty ? '' : '  Key saved.'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                if (_loadingWeather) const Center(child: CircularProgressIndicator()),
                if (_weather != null) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${_weather!.tempC.toStringAsFixed(1)}°C',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_weather!.condition, style: const TextStyle(fontSize: 15, color: Colors.grey)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    _wxChip(Icons.air, 'Wind',
                        '${(_weather!.windSpeedMs * 1.94384).toStringAsFixed(0)} kts ${_weather!.windDir}'),
                    _wxChip(Icons.water_drop_outlined, 'Humidity', '${_weather!.humidity}%'),
                    _wxChip(Icons.visibility_outlined, 'Vis', '${_weather!.visibility.toStringAsFixed(1)} km'),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadingWeather ? null : _fetchFromGps,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ]),
            ),
          ),

          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.info_outline, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Weather is cached on fetch — works offline after first load. Sunrise/sunset calculated locally using GPS coordinates.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sunCell(IconData icon, String label, String value) {
    return Column(children: [
      Icon(icon, color: Colors.amber, size: 22),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _wxChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text('$label: $value', style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}
