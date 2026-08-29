import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const SmartBeehiveApp());
}

class SmartBeehiveApp extends StatelessWidget {
  const SmartBeehiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apiary Live Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFFF59E0B),
        cardColor: const Color(0xFF1E293B),
      ),
      home: const DashboardScreen(),
    );
  }
}

class HiveDataPoint {
  final DateTime time;
  final double weight;
  final double internalTemp;
  final double humidity;

  HiveDataPoint({
    required this.time,
    required this.weight,
    required this.internalTemp,
    required this.humidity,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Hive Metrics
  double _currentWeight = 42.85;
  double _internalTemp = 34.8;
  double _internalHumidity = 58.2;
  double _batteryLevel = 94.0;
  final List<HiveDataPoint> _history = [];

  // Weather & Fire Protection Metrics (Xanthi, Greece)
  double _ambientTemp = 28.5;
  double _windSpeed = 16.0; // km/h
  double _windDirection = 45.0; // Degrees
  int _fireRiskCategory = 2; // Default Moderate
  bool _isLoadingWeather = false;
  String _fireRiskSourceDate = "Today";

  Timer? _telemetryTimer;
  Timer? _weatherTimer;

  final String _fireRiskJsonUrl =
      'https://raw.githubusercontent.com/BBRT2006/beehive_app/main/fire_risk.json';

  @override
  void initState() {
    super.initState();
    _seedHistoricalData();
    _fetchLiveWeatherData();
    _fetchLiveFireRisk();

    // Simulate real-time scale measurements every 4 seconds
    _telemetryTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _simulateTelemetryTick();
    });

    // Refresh weather & civil protection risk every 15 minutes
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      _fetchLiveWeatherData();
      _fetchLiveFireRisk();
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  void _seedHistoricalData() {
    final now = DateTime.now();
    double baseWeight = 41.5;
    for (int i = 24; i >= 0; i--) {
      final t = now.subtract(Duration(hours: i));
      baseWeight += (Random().nextDouble() - 0.45) * 0.15;
      _history.add(
        HiveDataPoint(
          time: t,
          weight: double.parse(baseWeight.toStringAsFixed(2)),
          internalTemp: 34.5 + Random().nextDouble() * 0.6,
          humidity: 55.0 + Random().nextDouble() * 6.0,
        ),
      );
    }
    _currentWeight = _history.last.weight;
  }

  void _simulateTelemetryTick() {
    setState(() {
      final change = (Random().nextDouble() - 0.48) * 0.05;
      _currentWeight = double.parse((_currentWeight + change).toStringAsFixed(2));
      _internalTemp = double.parse((34.8 + (Random().nextDouble() - 0.5) * 0.3).toStringAsFixed(1));
      _internalHumidity = double.parse((58.0 + (Random().nextDouble() - 0.5) * 1.5).toStringAsFixed(1));
      
      _history.add(
        HiveDataPoint(
          time: DateTime.now(),
          weight: _currentWeight,
          internalTemp: _internalTemp,
          humidity: _internalHumidity,
        ),
      );
      if (_history.length > 50) _history.removeAt(0);
    });
  }

  Future<void> _fetchLiveWeatherData() async {
    setState(() => _isLoadingWeather = true);
    try {
      // Xanthi Coordinates: 41.1349 N, 24.8880 E
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=41.1349&longitude=24.8880&current_weather=true',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current_weather'];
        setState(() {
          _ambientTemp = (current['temperature'] as num).toDouble();
          _windSpeed = (current['windspeed'] as num).toDouble();
          _windDirection = (current['winddirection'] as num).toDouble();
        });
      }
    } catch (_) {
      // Fallback defaults on network timeout
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _fetchLiveFireRisk() async {
    try {
      final res = await http
          .get(Uri.parse(_fireRiskJsonUrl))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final regions = data['regions'] as Map<String, dynamic>?;
        if (regions != null && regions.containsKey('Ξάνθη')) {
          setState(() {
            _fireRiskCategory = regions['Ξάνθη'] as int;
            if (data['lastUpdated'] != null) {
              _fireRiskSourceDate = (data['lastUpdated'] as String).substring(0, 10);
            }
          });
        }
      }
    } catch (_) {
      // Retains default category 2 if repository is pending first run
    }
  }

  Color _getRiskColor(int cat) {
    switch (cat) {
      case 1:
        return const Color(0xFF10B981); // Low - Green
      case 2:
        return const Color(0xFF3B82F6); // Moderate - Blue
      case 3:
        return const Color(0xFFF59E0B); // High - Yellow
      case 4:
        return const Color(0xFFF97316); // Very High - Orange
      case 5:
        return const Color(0xFFEF4444); // Extreme - Red
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _getRiskText(int cat) {
    switch (cat) {
      case 1:
        return "Κατηγορία 1: Χαμηλή";
      case 2:
        return "Κατηγορία 2: Μέση";
      case 3:
        return "Κατηγορία 3: Υψηλή (Προσοχή στο κάπνισμα!)";
      case 4:
        return "Κατηγορία 4: Πολύ Υψηλή (Απαγόρευση Καπνιστηριού)";
      case 5:
        return "Κατηγορία 5: Κατάσταση Συναγερμού";
      default:
        return "Κατηγορία $cat";
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = _getRiskColor(_fireRiskCategory);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hive_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 10),
            Text(
              'Hive #01 • Xanthi Apiary',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: _isLoadingWeather
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: () {
              _fetchLiveWeatherData();
              _fetchLiveFireRisk();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fire Danger Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: riskColor, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, color: riskColor, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Χάρτης Πρόβλεψης Κινδύνου Πυρκαγιάς (ΓΓΠΠ)",
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getRiskText(_fireRiskCategory),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: riskColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: riskColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "CAT $_fireRiskCategory",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Primary Scale & Brood Indicators
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: "Scale Weight",
                    value: "${_currentWeight.toStringAsFixed(2)} kg",
                    subtext: "Δ 24h: +0.45 kg",
                    icon: Icons.scale_rounded,
                    accentColor: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: "Brood Temp",
                    value: "$_internalTemp °C",
                    subtext: "Optimal (34.5 - 35.5)",
                    icon: Icons.thermostat_rounded,
                    accentColor: const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: "Brood Humidity",
                    value: "$_internalHumidity %",
                    subtext: "Stable",
                    icon: Icons.water_drop_rounded,
                    accentColor: const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: "Solar Battery",
                    value: "${_batteryLevel.toInt()} %",
                    subtext: "3.92V • Charging",
                    icon: Icons.battery_charging_full_rounded,
                    accentColor: const Color(0xFFA855F7),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Ambient Conditions & Custom Windsock
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Apiary Microclimate (Live Open-Meteo)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text("Ambient Temp", style: TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text("$_ambientTemp °C", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("Wind Speed", style: TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text("$_windSpeed km/h", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("Windsock", style: TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Transform.rotate(
                                angle: (_windDirection * pi / 180),
                                child: CustomPaint(
                                  painter: WindsockPainter(speed: _windSpeed),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Weight History Graph
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("24h Net Weight Flow", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("HX711 Calibrated", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: SparklinePainter(points: _history),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color accentColor,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Icon(icon, color: accentColor, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(subtext, style: TextStyle(color: accentColor, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class WindsockPainter extends CustomPainter {
  final double speed;
  WindsockPainter({required this.speed});

  @override
  void paint(Canvas canvas, Size size) {
    final pole = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final orange = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.fill;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Mast
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), pole);

    // Dynamic deflection angle based on km/h
    final liftFactor = (speed / 40.0).clamp(0.2, 1.0);
    final sockPath = Path();
    sockPath.moveTo(size.width / 2, 6);
    sockPath.lineTo(size.width - 2, 6 + (14 * (1.0 - liftFactor)));
    sockPath.lineTo(size.width - 2, 16 + (14 * (1.0 - liftFactor)));
    sockPath.lineTo(size.width / 2, 20);
    sockPath.close();

    canvas.drawPath(sockPath, orange);

    // Decorative center stripe
    final stripe = Path();
    stripe.moveTo(size.width / 2 + 8, 8);
    stripe.lineTo(size.width / 2 + 16, 10);
    stripe.lineTo(size.width / 2 + 16, 17);
    stripe.lineTo(size.width / 2 + 8, 18);
    stripe.close();
    canvas.drawPath(stripe, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SparklinePainter extends CustomPainter {
  final List<HiveDataPoint> points;
  SparklinePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final minW = points.map((e) => e.weight).reduce(min);
    final maxW = points.map((e) => e.weight).reduce(max);
    final range = (maxW - minW) == 0 ? 1.0 : (maxW - minW);

    final linePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final normalizedY = (points[i].weight - minW) / range;
      final y = size.height - (normalizedY * (size.height - 20)) - 10;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gradient fill under the graph
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.3),
          const Color(0xFF10B981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}