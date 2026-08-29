import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const BeehiveApp());
}

class BeehiveApp extends StatefulWidget {
  const BeehiveApp({super.key});

  @override
  State<BeehiveApp> createState() => _BeehiveAppState();
}

class _BeehiveAppState extends State<BeehiveApp> {
  String _currentLanguage = 'el';

  void _changeLanguage(String lang) {
    setState(() {
      _currentLanguage = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apiary Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFD97706),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: MultiHiveDashboard(
        currentLanguage: _currentLanguage,
        onLanguageChanged: _changeLanguage,
      ),
    );
  }
}

class DayForecast {
  final String dayName;
  final double maxTemp;
  final double minTemp;
  final double maxWindSpeedKmH;
  final int maxHumidity;
  final int weatherCode;

  DayForecast({
    required this.dayName,
    required this.maxTemp,
    required this.minTemp,
    required this.maxWindSpeedKmH,
    required this.maxHumidity,
    required this.weatherCode,
  });
}

class HiveNote {
  final String date;
  final String text;

  HiveNote({required this.date, required this.text});
}

class HiveData {
  String id;
  String name;
  String apiaryName;
  String regionDescription;
  DateTime sitePlacedDate;
  double currentWeight;
  double baselineWeight;
  double outdoorTemp;
  double outdoorHumidity;
  double batteryVolts;
  int batteryPct;
  int signalDbm;
  double latitude;
  double longitude;
  int satellitesLocked;

  int fireRiskCategoryToday;
  int fireRiskCategoryTomorrow;

  bool isTheftAlertTriggered;
  bool isInspectionMode;
  int inspectionRemaining;
  bool isTransportMode;
  DateTime? transportStartTime;
  int transportRemaining;
  bool isAutoRelocationEnabled;

  List<HiveNote> notes;
  List<DayForecast> weatherForecast;
  List<double> hourlyWeights48h;
  List<Map<String, dynamic>> locationHistory;
  Map<String, List<Map<String, dynamic>>> archivedYears;

  HiveData({
    required this.id,
    required this.name,
    required this.apiaryName,
    required this.regionDescription,
    required this.sitePlacedDate,
    required this.currentWeight,
    required this.baselineWeight,
    required this.outdoorTemp,
    required this.outdoorHumidity,
    required this.batteryVolts,
    required this.batteryPct,
    required this.signalDbm,
    required this.latitude,
    required this.longitude,
    required this.satellitesLocked,
    this.fireRiskCategoryToday = 2,
    this.fireRiskCategoryTomorrow = 3,
    this.isTheftAlertTriggered = false,
    this.isInspectionMode = false,
    this.inspectionRemaining = 45 * 60,
    this.isTransportMode = false,
    this.transportStartTime,
    this.transportRemaining = 24 * 3600,
    this.isAutoRelocationEnabled = true,
    required this.notes,
    required this.weatherForecast,
    required this.hourlyWeights48h,
    required this.locationHistory,
    required this.archivedYears,
  });
}

class MultiHiveDashboard extends StatefulWidget {
  final String currentLanguage;
  final ValueChanged<String> onLanguageChanged;

  const MultiHiveDashboard({
    super.key,
    required this.currentLanguage,
    required this.onLanguageChanged,
  });

  @override
  State<MultiHiveDashboard> createState() => _MultiHiveDashboardState();
}

class _MultiHiveDashboardState extends State<MultiHiveDashboard> {
  late List<HiveData> hives;
  int selectedHiveIndex = 0;

  Timer? _globalTicker;
  bool isSyncing = false;

  double _visibleHours = 48.0;
  double _scrollOffset = 0.0;
  double _baseScaleVisibleHours = 48.0;

  @override
  void initState() {
    super.initState();
    _initHives();
    _fetchLiveOnlineData();

    _globalTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      bool needsRebuild = false;
      for (var hive in hives) {
        if (hive.isInspectionMode) {
          if (hive.inspectionRemaining > 0) {
            hive.inspectionRemaining--;
            needsRebuild = true;
          } else {
            hive.isInspectionMode = false;
            needsRebuild = true;
          }
        }
        if (hive.isTransportMode) {
          if (hive.transportRemaining > 0) {
            hive.transportRemaining--;
            needsRebuild = true;
          } else {
            hive.isTransportMode = false;
            needsRebuild = true;
          }
        }
      }
      if (needsRebuild && mounted) setState(() {});
    });
  }

  void _initHives() {
    hives = [
      HiveData(
        id: 'hive_01',
        name: 'Κυψέλη #1 (Ελαιώνας)',
        apiaryName: 'Μελισσοκομείο Πευκοδάσος Ξάνθης',
        regionDescription: 'Πευκοδάσος Ξάνθης',
        sitePlacedDate: DateTime(2026, 8, 12),
        currentWeight: 47.10,
        baselineWeight: 38.20,
        outdoorTemp: 28.6,
        outdoorHumidity: 48.0,
        batteryVolts: 3.32,
        batteryPct: 94,
        signalDbm: -78,
        latitude: 41.1349,
        longitude: 24.8880,
        satellitesLocked: 8,
        fireRiskCategoryToday: 2,
        fireRiskCategoryTomorrow: 4,
        notes: [
          HiveNote(date: '24 Αυγ 2026', text: 'Προσθήκη 2ου πατώματος (μελιτοθάλαμος). Βασίλισσα υγιής, 7 πλαίσια γόνος.'),
          HiveNote(date: '18 Αυγ 2026', text: 'Έλεγχος για βαρρόα. Τοποθετήθηκαν ταινίες οξαλικού οξέος.'),
        ],
        weatherForecast: [
          DayForecast(dayName: 'Σήμερα', maxTemp: 28, minTemp: 19, maxWindSpeedKmH: 13.0, maxHumidity: 67, weatherCode: 1),
          DayForecast(dayName: 'Κυρ', maxTemp: 30, minTemp: 20, maxWindSpeedKmH: 22.0, maxHumidity: 75, weatherCode: 0),
          DayForecast(dayName: 'Δευ', maxTemp: 30, minTemp: 20, maxWindSpeedKmH: 14.0, maxHumidity: 71, weatherCode: 2),
          DayForecast(dayName: 'Τρι', maxTemp: 31, minTemp: 21, maxWindSpeedKmH: 20.0, maxHumidity: 75, weatherCode: 3),
          DayForecast(dayName: 'Τετ', maxTemp: 31, minTemp: 22, maxWindSpeedKmH: 12.0, maxHumidity: 77, weatherCode: 61),
        ],
        hourlyWeights48h: [
          45.60, 45.60, 45.58, 45.58, 45.55, 45.50,
          45.42, 45.30, 45.25, 45.40, 45.70, 45.95,
          46.10, 46.25, 46.35, 46.40, 46.38, 46.35,
          46.35, 46.35, 46.35, 46.34, 46.34, 46.33,
          46.30, 46.28, 46.25, 46.25, 46.22, 46.18,
          46.10, 46.05, 46.20, 46.45, 46.70, 46.90,
          47.05, 47.15, 47.20, 47.18, 47.15, 47.12,
          47.10, 47.10, 47.10, 47.10, 47.10, 47.10
        ],
        locationHistory: [
          {"day": "12 Αυγ (Άφιξη)", "weight": 38.20, "gain": "+0.00 kg"},
          {"day": "18 Αυγ", "weight": 41.50, "gain": "+1.70 kg"},
          {"day": "24 Αυγ", "weight": 44.90, "gain": "+1.80 kg"},
          {"day": "Σήμερα", "weight": 47.10, "gain": "+0.75 kg"},
        ],
        archivedYears: {
          "2026": [
            {
              "apiary": "Χαλκιδική (Πορτοκαλιά)",
              "locationRegion": "Χαλκιδική (Πορτοκαλεώνας)",
              "startDate": "15/05/2026",
              "endDate": "10/08/2026",
              "durationDays": 87,
              "initialWeight": 26.0,
              "finalWeight": 44.4,
              "totalGain": 18.40,
              "dailyAvgGain": 0.21,
              "chartData": [26.0, 27.5, 30.2, 33.8, 38.4, 42.1, 44.4],
              "checkpoints": [
                {"date": "15 Μαΐ", "weight": 26.0, "delta": "+0.00 kg"},
                {"date": "10 Αυγ", "weight": 44.4, "delta": "+18.40 kg"},
              ]
            }
          ]
        },
      ),
      HiveData(
        id: 'hive_02',
        name: 'Κυψέλη #2 (Ποταμός)',
        apiaryName: 'Μελισσοκομείο Κοιλάδα Νέστου',
        regionDescription: 'Κοιλάδα Νέστου',
        sitePlacedDate: DateTime(2026, 8, 15),
        currentWeight: 42.30,
        baselineWeight: 36.50,
        outdoorTemp: 29.1,
        outdoorHumidity: 52.0,
        batteryVolts: 3.30,
        batteryPct: 89,
        signalDbm: -82,
        latitude: 41.1120,
        longitude: 24.7730,
        satellitesLocked: 9,
        fireRiskCategoryToday: 1,
        fireRiskCategoryTomorrow: 2,
        notes: [
          HiveNote(date: '20 Αυγ 2026', text: 'Τροφοδοσία με ζαχαροζύμαρο 1kg. Καλή δραστηριότητα εισόδου.'),
        ],
        weatherForecast: [
          DayForecast(dayName: 'Σήμερα', maxTemp: 32, minTemp: 20, maxWindSpeedKmH: 21.0, maxHumidity: 55, weatherCode: 0),
          DayForecast(dayName: 'Κυρ', maxTemp: 33, minTemp: 21, maxWindSpeedKmH: 12.0, maxHumidity: 52, weatherCode: 0),
          DayForecast(dayName: 'Δευ', maxTemp: 31, minTemp: 19, maxWindSpeedKmH: 26.0, maxHumidity: 68, weatherCode: 2),
          DayForecast(dayName: 'Τρι', maxTemp: 29, minTemp: 18, maxWindSpeedKmH: 18.5, maxHumidity: 74, weatherCode: 3),
          DayForecast(dayName: 'Τετ', maxTemp: 28, minTemp: 17, maxWindSpeedKmH: 22.0, maxHumidity: 80, weatherCode: 61),
        ],
        hourlyWeights48h: [
          41.5, 41.5, 41.4, 41.4, 41.3, 41.2,
          41.0, 40.8, 41.0, 41.4, 41.8, 42.1,
          42.3, 42.5, 42.6, 42.6, 42.5, 42.4,
          42.3, 42.3, 42.3, 42.3, 42.3, 42.3,
          41.8, 41.8, 41.7, 41.6, 41.5, 41.4,
          41.2, 41.0, 41.3, 41.7, 42.0, 42.2,
          42.4, 42.5, 42.5, 42.4, 42.3, 42.3,
          42.3, 42.3, 42.3, 42.3, 42.3, 42.3
        ],
        locationHistory: [
          {"day": "15 Αυγ (Άφιξη)", "weight": 36.50, "gain": "+0.00 kg"},
          {"day": "Σήμερα", "weight": 42.30, "gain": "+5.80 kg"},
        ],
        archivedYears: {},
      )
    ];
  }

  HiveData get activeHive => hives[selectedHiveIndex];

  Future<void> _fetchLiveOnlineData() async {
    final hive = activeHive;
    try {
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${hive.latitude}&longitude=${hive.longitude}&daily=weathercode,temperature_2m_max,temperature_2m_min,windspeed_10m_max,relative_humidity_2m_max&timezone=auto',
      );
      final weatherRes = await http.get(weatherUrl).timeout(const Duration(seconds: 4));
      if (weatherRes.statusCode == 200) {
        final data = jsonDecode(weatherRes.body);
        final daily = data['daily'];
        final List<String> times = List<String>.from(daily['time']);
        final List maxTemps = daily['temperature_2m_max'];
        final List minTemps = daily['temperature_2m_min'];
        final List windSpeeds = daily['windspeed_10m_max'];
        final List humidities = daily['relative_humidity_2m_max'];
        final List weatherCodes = daily['weathercode'];

        final List<DayForecast> fetchedDays = [];
        final daysOfWeekEl = ['Κυρ', 'Δευ', 'Τρι', 'Τετ', 'Πεμ', 'Παρ', 'Σαβ'];
        final daysOfWeekEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        for (int i = 0; i < math.min(5, times.length); i++) {
          final dt = DateTime.parse(times[i]);
          String dName = i == 0
              ? (widget.currentLanguage == 'el' ? 'Σήμερα' : 'Today')
              : (widget.currentLanguage == 'el' ? daysOfWeekEl[dt.weekday % 7] : daysOfWeekEn[dt.weekday % 7]);

          fetchedDays.add(DayForecast(
            dayName: dName,
            maxTemp: (maxTemps[i] as num).toDouble(),
            minTemp: (minTemps[i] as num).toDouble(),
            maxWindSpeedKmH: (windSpeeds[i] as num).toDouble(),
            maxHumidity: (humidities[i] as num).toInt(),
            weatherCode: (weatherCodes[i] as num).toInt(),
          ));
        }

        setState(() {
          hive.weatherForecast = fetchedDays;
        });
      }

      final geoUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${hive.latitude}&lon=${hive.longitude}&accept-language=el',
      );
      final geoRes = await http.get(geoUrl, headers: {'User-Agent': 'BeehiveMonitorApp/1.0'}).timeout(const Duration(seconds: 4));
      if (geoRes.statusCode == 200) {
        final geoData = jsonDecode(geoRes.body);
        final address = geoData['address'];
        final String loc = address['village'] ?? address['town'] ?? address['city'] ?? address['municipality'] ?? address['county'] ?? 'Περιοχή';
        setState(() {
          hive.regionDescription = loc;
        });
      }
    } catch (_) {}
  }

  Map<String, String> get t {
    if (widget.currentLanguage == 'el') {
      return {
        'app_title': 'Επισκόπηση Μελισσοκομείου',
        'online': 'Συνδεδεμένο',
        'transport_radio_muted': 'Δεδομένα σε Σίγαση (Μόνο κατ\' απαίτηση)',
        'inspection_mode': 'Κατάσταση Επιθεώρησης',
        'inspection_active': 'Επιθεώρηση Ενεργή',
        'inspection_sub_off': 'Σίγαση συναγερμών κλοπής/ζημιάς',
        'inspection_sub_on': 'Συναγερμοί σε σίγαση (αυτόματη επαναφορά)',
        'total_weight': 'ΣΥΝΟΛΙΚΟ ΒΑΡΟΣ ΚΥΨΕΛΗΣ',
        'overall': 'συνολικά',
        'daily_gain': 'Ημερήσια Μεταβολή Βάρους',
        'ext_temp': 'Εξωτ. Θερμ.',
        'humidity': 'Υγρασία',
        'battery': 'Μπαταρία',
        'signal': 'Σήμα 4G',
        'curve_title': 'Καμπύλη Βάρους 48ώρου',
        'window': 'παράθυρο',
        'site_history': 'Ιστορικό Τοποθεσίας',
        'gps_location': 'Τοποθεσία Μελισσοκομείου',
        'sats_fixed': 'Δορυφόροι',
        'auto_detect_title': 'Αυτόματη Ανίχνευση Μεταφοράς',
        'transport_active': 'Μεταφορά Ενεργή (24h)',
        'transport_sub_on': 'Διακοπή δεδομένων • Μόνο κατ\' απαίτηση',
        'start_transport': 'Έναρξη Μεταφοράς (Σύρετε)',
        'stop_transport': 'Τερματισμός Μεταφοράς & Ονομασία',
        'request_reading': 'Άμεση Λήψη Μέτρησης Τώρα (Κατ\' απαίτηση)',
        'syncing': 'Συγχρονισμός...',
        'archives_header': 'ΕΤΗΣΙΟ ΑΡΧΕΙΟ ΣΥΓΚΟΜΙΔΗΣ',
        'season': 'Περίοδος',
        'language_select': 'Γλώσσα / Language',
        'rename_location': 'Μετονομασία Μελισσοκομείου',
        'post_transport_title': 'Ολοκλήρωση Μεταφοράς 🐝',
        'post_transport_desc': 'Η μεταφορά έληξε. Πληκτρολογήστε το όνομα του νέου μελισσοκομείου:',
        'add_hive': 'Προσθήκη Νέας Κυψέλης',
        'hives_list': 'ΟΙ ΚΥΨΕΛΕΣ ΜΟΥ',
        'hive_notes': 'Σημειώσεις Κυψέλης & Επεμβάσεις',
        'add_note': '+ Σημείωση',
        'weather_forecast': 'Πρόγνωση Καιρού 5 Ημερών',
        'fire_risk_header': 'Χάρτης Πρόβλεψης Κινδύνου Πυρκαγιάς (ΓΓΠΠ)',
        'today': 'ΣΗΜΕΡΑ',
        'tomorrow': 'ΑΥΡΙΟ',
        'allowed_short': 'ΕΠΙΤΡΕΠΕΤΑΙ',
        'warning_short': 'ΑΠΑΓΟΡΕΥΣΗ',
        'allowed_sub_short': 'Προσοχή στο καπνιστήρι',
        'warning_sub_short': 'Απαγόρευση καπνιστηριού & δάσους',
        'save': 'Αποθήκευση',
        'cancel': 'Ακύρωση',
        'slide_to_activate': 'Σύρετε για Άμεση Έναρξη Μεταφοράς 👉',
      };
    } else {
      return {
        'app_title': 'Apiary Monitor',
        'online': 'Online',
        'transport_radio_muted': 'Data Muted (On-Demand Only)',
        'inspection_mode': 'Inspection Mode',
        'inspection_active': 'Inspection Active',
        'inspection_sub_off': 'Mutes theft/movement alarms',
        'inspection_sub_on': 'Alarms muted (45m auto-off)',
        'total_weight': 'TOTAL HIVE WEIGHT',
        'overall': 'overall',
        'daily_gain': 'Net Daily Weight Gain',
        'ext_temp': 'Ext. Temp',
        'humidity': 'Humidity',
        'battery': 'Battery',
        'signal': 'Cellular',
        'curve_title': '48h Weight Curve',
        'window': 'window',
        'site_history': 'Site History',
        'gps_location': 'Apiary Location',
        'sats_fixed': 'Sats Fixed',
        'auto_detect_title': 'Auto Relocation Detection',
        'transport_active': 'Transport Mode Active (24h)',
        'transport_sub_on': 'Background data cut off • On-Demand only',
        'start_transport': 'Start Transport (Slide)',
        'stop_transport': 'End Transport & Name Apiary',
        'request_reading': 'Request Scale Reading Now (On-Demand)',
        'syncing': 'Syncing...',
        'archives_header': 'YEARLY HARVEST ARCHIVES',
        'season': 'Season',
        'language_select': 'Language / Γλώσσα',
        'rename_location': 'Rename Apiary Location',
        'post_transport_title': 'Transport Completed 🐝',
        'post_transport_desc': 'Transport period ended. Enter destination apiary name:',
        'add_hive': 'Add New Hive',
        'hives_list': 'MY HIVES',
        'hive_notes': 'Hive Notes & Logbook',
        'add_note': '+ Note',
        'weather_forecast': '5-Day Weather Forecast',
        'fire_risk_header': 'Civil Protection Fire Risk Forecast',
        'today': 'TODAY',
        'tomorrow': 'TOMORROW',
        'allowed_short': 'ALLOWED',
        'warning_short': 'RESTRICTED',
        'allowed_sub_short': 'Smoker caution advised',
        'warning_sub_short': 'Smoker & forest access banned',
        'save': 'Save',
        'cancel': 'Cancel',
        'slide_to_activate': 'Slide to Start Transport 👉',
      };
    }
  }

  String _formatDateString(DateTime d) {
    final months = widget.currentLanguage == 'el'
        ? ['Ιαν', 'Φεβ', 'Μαρ', 'Απρ', 'Μαϊ', 'Ιουν', 'Ιουλ', 'Αυγ', 'Σεπ', 'Οκτ', 'Νοε', 'Δεκ']
        : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.wb_cloudy;
    if (code <= 67) return Icons.grain;
    if (code <= 82) return Icons.shower;
    return Icons.thunderstorm;
  }

  Color _getFireCategoryColor(int category) {
    switch (category) {
      case 1:
        return const Color(0xFF22C55E);
      case 2:
        return const Color(0xFF3B82F6);
      case 3:
        return const Color(0xFFEAB308);
      case 4:
        return const Color(0xFFF97316);
      case 5:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFEAB308);
    }
  }

  String _getFireCategoryTitle(int category) {
    if (widget.currentLanguage == 'el') {
      switch (category) {
        case 1:
          return 'Κατηγ. 1 (Χαμηλή)';
        case 2:
          return 'Κατηγ. 2 (Μέση)';
        case 3:
          return 'Κατηγ. 3 (Υψηλή)';
        case 4:
          return 'Κατηγ. 4 (Πολύ Υψηλή)';
        case 5:
          return 'Κατηγ. 5 (Συναγερμός)';
        default:
          return 'Κατηγ. 3 (Υψηλή)';
      }
    } else {
      switch (category) {
        case 1:
          return 'Cat. 1 (Low)';
        case 2:
          return 'Cat. 2 (Mod)';
        case 3:
          return 'Cat. 3 (High)';
        case 4:
          return 'Cat. 4 (Very High)';
        case 5:
          return 'Cat. 5 (Extreme)';
        default:
          return 'Cat. 3 (High)';
      }
    }
  }

  String _getSignalText(int dbm) {
    if (activeHive.isTransportMode) return widget.currentLanguage == 'el' ? 'Σε Αναμονή' : 'Standby';
    bool isGreek = widget.currentLanguage == 'el';
    if (dbm >= -70) return isGreek ? 'Εξαιρετικό' : 'Excellent';
    if (dbm >= -85) return isGreek ? 'Ισχυρό' : 'Strong';
    if (dbm >= -100) return isGreek ? 'Καλό' : 'Good';
    if (dbm >= -110) return isGreek ? 'Αδύναμο' : 'Weak';
    return isGreek ? 'Πολύ Αδύναμο' : 'Very Weak';
  }

  Color _getSignalColor(int dbm) {
    if (activeHive.isTransportMode) return const Color(0xFF64748B);
    if (dbm >= -70) return const Color(0xFF16A34A);
    if (dbm >= -85) return const Color(0xFF0D9488);
    if (dbm >= -100) return const Color(0xFF0284C7);
    if (dbm >= -110) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  @override
  void dispose() {
    _globalTicker?.cancel();
    super.dispose();
  }

  void _showAddNoteDialog() {
    final controller = TextEditingController();
    DateTime selectedNoteDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.edit_note, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Text(t['add_note']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedNoteDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedNoteDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_month, size: 18, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Text(
                                _formatDateString(selectedNoteDate),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'π.χ. Προσθήκη πατώματος, θεραπεία βαρρόα...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      setState(() {
                        activeHive.notes.insert(
                          0,
                          HiveNote(
                            date: _formatDateString(selectedNoteDate),
                            text: controller.text.trim(),
                          ),
                        );
                      });
                    }
                    Navigator.pop(context);
                  },
                  child: Text(t['save']!),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: activeHive.apiaryName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['rename_location']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.currentLanguage == 'el' ? 'Όνομα Μελισσοκομείου' : 'Apiary Name',
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  setState(() {
                    activeHive.apiaryName = trimmed;
                  });
                }
                Navigator.pop(context);
              },
              child: Text(t['save']!),
            ),
          ],
        );
      },
    );
  }

  void _showPostTransportNameDialog() {
    final controller = TextEditingController(text: 'Μελισσοκομείο ${activeHive.regionDescription}');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.hive, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(child: Text(t['post_transport_title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          content: Column(
            mainAxisSize: minAxisSize,
            children: [
              Text(t['post_transport_desc']!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.currentLanguage == 'el' ? 'Όνομα Νέου Μελισσοκομείου' : 'New Apiary Name',
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
              onPressed: () {
                final chosenName = controller.text.trim();
                Navigator.pop(context);
                final finalName = chosenName.isNotEmpty ? chosenName : "Μελισσοκομείο ${activeHive.regionDescription}";
                _finalizeStay(finalName);
              },
              child: Text(t['save']!),
            ),
          ],
        );
      },
    );
  }

  MainAxisSize get minAxisSize => MainAxisSize.min;

  void _finalizeStay(String newApiaryName) {
    final double netGain = activeHive.currentWeight - activeHive.baselineWeight;
    final currentYear = activeHive.sitePlacedDate.year.toString();
    final int days = DateTime.now().difference(activeHive.sitePlacedDate).inDays.clamp(1, 999);

    final archiveRecord = {
      "apiary": activeHive.apiaryName,
      "locationRegion": activeHive.regionDescription,
      "startDate": "${activeHive.sitePlacedDate.day}/${activeHive.sitePlacedDate.month}/${activeHive.sitePlacedDate.year}",
      "endDate": "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
      "durationDays": days,
      "initialWeight": activeHive.baselineWeight,
      "finalWeight": activeHive.currentWeight,
      "totalGain": netGain,
      "dailyAvgGain": netGain / days,
    };

    setState(() {
      activeHive.isTransportMode = false;
      activeHive.transportStartTime = null;
      if (!activeHive.archivedYears.containsKey(currentYear)) {
        activeHive.archivedYears[currentYear] = [];
      }
      activeHive.archivedYears[currentYear]!.insert(0, archiveRecord);
      activeHive.apiaryName = newApiaryName;
      activeHive.sitePlacedDate = DateTime.now();
      activeHive.baselineWeight = activeHive.currentWeight;
      activeHive.locationHistory = [
        {"day": widget.currentLanguage == 'el' ? "1η Ημέρα (Άφιξη)" : "Day 1 (Arrival)", "weight": activeHive.currentWeight, "gain": "+0.00 kg"}
      ];
    });
  }

  void _showSlideToActivateDialog() {
    double sliderValue = 0.0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_shipping, color: Color(0xFFD97706), size: 26),
                        const SizedBox(width: 8),
                        Text(t['start_transport']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Stack(
                    children: [
                      Center(child: Text(t['slide_to_activate']!, style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.bold, fontSize: 13))),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 54,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: const Color(0xFFD97706),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 24),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: sliderValue,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) {
                            setModalState(() => sliderValue = val);
                            if (val >= 0.95) {
                              Navigator.pop(context);
                              setState(() {
                                activeHive.isTransportMode = true;
                                activeHive.transportStartTime = DateTime.now();
                                activeHive.transportRemaining = 24 * 3600;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        });
      },
    );
  }

  void _addNewHiveDialog() {
    final controller = TextEditingController(text: 'Κυψέλη #${hives.length + 1}');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['add_hive']!, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.currentLanguage == 'el' ? 'Όνομα Κυψέλης' : 'Hive Name',
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
              onPressed: () {
                final trimmed = controller.text.trim();
                final name = trimmed.isEmpty ? 'Κυψέλη #${hives.length + 1}' : trimmed;
                setState(() {
                  hives.add(HiveData(
                    id: 'hive_${hives.length + 1}',
                    name: name,
                    apiaryName: activeHive.apiaryName,
                    regionDescription: activeHive.regionDescription,
                    sitePlacedDate: DateTime.now(),
                    currentWeight: 35.0,
                    baselineWeight: 35.0,
                    outdoorTemp: activeHive.outdoorTemp,
                    outdoorHumidity: activeHive.outdoorHumidity,
                    batteryVolts: 3.32,
                    batteryPct: 100,
                    signalDbm: -75,
                    latitude: activeHive.latitude,
                    longitude: activeHive.longitude,
                    satellitesLocked: 8,
                    notes: [],
                    weatherForecast: List.from(activeHive.weatherForecast),
                    hourlyWeights48h: [
                      34.8, 34.8, 34.8, 34.8, 34.7, 34.7,
                      34.6, 34.5, 34.6, 34.8, 35.0, 35.1,
                      35.2, 35.3, 35.3, 35.2, 35.1, 35.0,
                      35.0, 35.0, 35.0, 35.0, 35.0, 35.0,
                      34.8, 34.8, 34.8, 34.8, 34.7, 34.7,
                      34.6, 34.5, 34.6, 34.8, 35.0, 35.1,
                      35.2, 35.3, 35.3, 35.2, 35.1, 35.0,
                      35.0, 35.0, 35.0, 35.0, 35.0, 35.0,
                    ],
                    locationHistory: [
                      {"day": "Σήμερα (Έναρξη)", "weight": 35.0, "gain": "+0.00 kg"}
                    ],
                    archivedYears: {},
                  ));
                  selectedHiveIndex = hives.length - 1;
                });
                Navigator.pop(context);
              },
              child: Text(t['save']!),
            ),
          ],
        );
      },
    );
  }

  String _formatTimer(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildFireRiskHalf({
    required String dayLabel,
    required int category,
  }) {
    bool isRestricted = category >= 4;
    Color statusColor = _getFireCategoryColor(category);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isRestricted ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRestricted ? const Color(0xFFEF4444) : const Color(0xFF86EFAC),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dayLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isRestricted ? const Color(0xFF991B1B) : const Color(0xFF166534),
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _getFireCategoryTitle(category),
                    style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isRestricted ? Icons.local_fire_department : Icons.verified_user,
                  color: isRestricted ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  size: 15,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isRestricted ? t['warning_short']! : t['allowed_short']!,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      color: isRestricted ? const Color(0xFF991B1B) : const Color(0xFF166534),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isRestricted ? t['warning_sub_short']! : t['allowed_sub_short']!,
              style: TextStyle(
                fontSize: 9.5,
                color: isRestricted ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hive = activeHive;
    final double netGain = hive.currentWeight - hive.baselineWeight;

    int totalPoints = hive.hourlyWeights48h.length;
    int count = _visibleHours.round().clamp(12, totalPoints);
    int maxStart = math.max(0, totalPoints - count);
    int startIndex = _scrollOffset.clamp(0.0, maxStart.toDouble()).floor();
    int endIndex = math.min(totalPoints, startIndex + count);
    List<double> displayedPoints = hive.hourlyWeights48h.sublist(startIndex, endIndex);

    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.hive, color: Colors.white, size: 36),
                        const SizedBox(height: 8),
                        Text(hive.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(t['app_title']!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),

                  // 🐝 ΛΙΣΤΑ ΚΥΨΕΛΩΝ ΣΤΟ DRAWER
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['hives_list']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Color(0xFFD97706), size: 22),
                          onPressed: () {
                            Navigator.pop(context);
                            _addNewHiveDialog();
                          },
                        )
                      ],
                    ),
                  ),
                  ...hives.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final h = entry.value;
                    final isSelected = idx == selectedHiveIndex;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.hive, color: isSelected ? const Color(0xFFD97706) : Colors.grey),
                      title: Text(h.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? const Color(0xFFD97706) : const Color(0xFF1E293B))),
                      trailing: Text('${h.currentWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      selected: isSelected,
                      selectedTileColor: const Color(0xFFFEF3C7),
                      onTap: () {
                        setState(() => selectedHiveIndex = idx);
                        _fetchLiveOnlineData();
                        Navigator.pop(context);
                      },
                    );
                  }),

                  const Divider(),

                  // ΕΤΗΣΙΟ ΑΡΧΕΙΟ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Text(t['archives_header']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B))),
                  ),
                  ...hive.archivedYears.entries.map((entry) => ExpansionTile(
                        initiallyExpanded: true,
                        leading: const Icon(Icons.folder_zip, color: Color(0xFFD97706)),
                        title: Text('${t['season']} ${entry.key} (${entry.value.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        children: entry.value.map((st) => ListTile(dense: true, title: Text(st['apiary']), trailing: Text('+${st['totalGain']} kg 🍯'))).toList(),
                      )),
                ],
              ),
            ),

            // 🌐 ΕΠΙΛΟΓΗ ΓΛΩΣΣΑΣ ΤΕΡΜΑ ΚΑΤΩ
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: widget.currentLanguage == 'el' ? const Color(0xFFD97706) : Colors.white,
                        foregroundColor: widget.currentLanguage == 'el' ? Colors.white : const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => widget.onLanguageChanged('el'),
                      child: const Text('🇬🇷 Ελληνικά', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: widget.currentLanguage == 'en' ? const Color(0xFFD97706) : Colors.white,
                        foregroundColor: widget.currentLanguage == 'en' ? Colors.white : const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => widget.onLanguageChanged('en'),
                      child: const Text('🇬🇧 English', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text(
          hive.name,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
        ),
        backgroundColor: const Color(0xFFD97706),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: isSyncing
                ? null
                : () async {
                    setState(() => isSyncing = true);
                    await _fetchLiveOnlineData();
                    setState(() {
                      isSyncing = false;
                      hive.currentWeight += 0.05;
                      hive.hourlyWeights48h.last = hive.currentWeight;
                    });
                  },
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: ListView(
            padding: const EdgeInsets.all(14.0),
            children: [
              // Top Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onLongPress: _showRenameDialog,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              hive.apiaryName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_note, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hive.isTransportMode ? const Color(0xFFF1F5F9) : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 7, color: hive.isTransportMode ? const Color(0xFF64748B) : const Color(0xFF16A34A)),
                        const SizedBox(width: 4),
                        Text(hive.isTransportMode ? t['transport_radio_muted']! : t['online']!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: hive.isTransportMode ? const Color(0xFF475569) : const Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 🚒 SPLIT FIRE HAZARD WIDGET
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFD97706)),
                            const SizedBox(width: 5),
                            Text(
                              t['fire_risk_header']!,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        const Text('ΓΓΠΠ 🛰️', style: TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildFireRiskHalf(
                          dayLabel: t['today']!,
                          category: hive.fireRiskCategoryToday,
                        ),
                        const SizedBox(width: 8),
                        _buildFireRiskHalf(
                          dayLabel: t['tomorrow']!,
                          category: hive.fireRiskCategoryTomorrow,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Inspection Mode Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: hive.isInspectionMode ? const Color(0xFFFEF3C7) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hive.isInspectionMode ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(hive.isInspectionMode ? Icons.build_circle : Icons.shield, color: hive.isInspectionMode ? const Color(0xFFB45309) : const Color(0xFF64748B), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hive.isInspectionMode ? t['inspection_active']! : t['inspection_mode']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: hive.isInspectionMode ? const Color(0xFF92400E) : const Color(0xFF1E293B))),
                          Text(hive.isInspectionMode ? t['inspection_sub_on']! : t['inspection_sub_off']!, style: TextStyle(fontSize: 11, color: hive.isInspectionMode ? const Color(0xFFB45309) : Colors.grey)),
                        ],
                      ),
                    ),
                    if (hive.isInspectionMode)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFB45309), borderRadius: BorderRadius.circular(6)),
                        child: Text(_formatTimer(hive.inspectionRemaining), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    Switch(
                      value: hive.isInspectionMode,
                      activeColor: const Color(0xFFD97706),
                      onChanged: (v) => setState(() {
                        hive.isInspectionMode = v;
                        hive.inspectionRemaining = 45 * 60;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Hero Weight Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: const Color(0xFFD97706).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['total_weight']!, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.22), borderRadius: BorderRadius.circular(12)),
                          child: Text('${netGain >= 0 ? '+' : ''}🍯 ${netGain.toStringAsFixed(1)} kg ${t['overall']}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(hive.currentWeight.toStringAsFixed(2), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(width: 6),
                        const Text('kg', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Compact 4-Metric Row
              Row(
                children: [
                  _compactTile(t['ext_temp']!, '${hive.outdoorTemp.toStringAsFixed(1)}°C', Icons.wb_sunny_outlined, Colors.orange),
                  const SizedBox(width: 6),
                  _compactTile(t['humidity']!, '${hive.outdoorHumidity.toStringAsFixed(0)}%', Icons.water_drop_outlined, Colors.blue),
                  const SizedBox(width: 6),
                  _compactTile(t['battery']!, '${hive.batteryPct}%', Icons.battery_charging_full, Colors.green),
                  _compactTile(t['signal']!, _getSignalText(hive.signalDbm), Icons.signal_cellular_alt, _getSignalColor(hive.signalDbm)),
                ],
              ),
              const SizedBox(height: 12),

              // 📈 48-HOUR WEIGHT CHART
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['curve_title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('${_visibleHours.toInt()}h ${t['window']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onScaleStart: (_) => _baseScaleVisibleHours = _visibleHours,
                      onScaleUpdate: (d) {
                        setState(() {
                          if (d.scale != 1.0) _visibleHours = (_baseScaleVisibleHours / d.scale).clamp(12.0, 48.0);
                          if (d.focalPointDelta.dx != 0) _scrollOffset = (_scrollOffset - (d.focalPointDelta.dx / 280) * _visibleHours).clamp(0.0, 48.0 - _visibleHours);
                        });
                      },
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        color: Colors.transparent,
                        child: CustomPaint(
                          painter: WeightChartPainter(data: displayedPoints),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 📝 ΣΗΜΕΙΩΣΕΙΣ ΚΥΨΕΛΗΣ
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sticky_note_2_outlined, color: Color(0xFFD97706), size: 20),
                            const SizedBox(width: 6),
                            Text(
                              t['hive_notes']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _showAddNoteDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t['add_note']!,
                              style: const TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (hive.notes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Δεν υπάρχουν καταγεγραμμένες σημειώσεις.', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: hive.notes.length > 3 ? 3 : hive.notes.length,
                        separatorBuilder: (context, index) => const Divider(height: 12, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final note = hive.notes[index];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                                child: Text(note.date, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(note.text, style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 🌤️ ΠΡΟΓΝΩΣΗ ΚΑΙΡΟΥ 5 ΗΜΕΡΩΝ (ΜΕ ΑΝΕΜΟ & ΑΝΕΜΟΥΡΙΟ)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wb_sunny_outlined, size: 18, color: Color(0xFFD97706)),
                            const SizedBox(width: 6),
                            Text(
                              t['weather_forecast']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        const Text('Open-Meteo Live 🛰️', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: hive.weatherForecast.map((day) {
                        bool isHighWind = day.maxWindSpeedKmH >= 18.0;
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                            decoration: BoxDecoration(
                              color: isHighWind ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isHighWind ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                                width: isHighWind ? 1.4 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(day.dayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                const SizedBox(height: 4),
                                Icon(_getWeatherIcon(day.weatherCode), size: 18, color: const Color(0xFFD97706)),
                                const SizedBox(height: 4),
                                Text(
                                  '${day.maxTemp.round()}° / ${day.minTemp.round()}°',
                                  style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // 💨 ΠΟΡΤΟΚΑΛΙ-ΑΣΠΡΟ ΑΝΕΜΟΥΡΙΟ + ΤΑΧΥΤΗΤΑ
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 15,
                                          height: 11,
                                          child: CustomPaint(painter: WindsockPainter(isAlert: isHighWind)),
                                        ),
                                        const SizedBox(width: 1),
                                        Text(
                                          '${day.maxWindSpeedKmH.round()}k',
                                          style: TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: isHighWind ? FontWeight.w900 : FontWeight.w700,
                                            color: isHighWind ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // 💧 ΣΤΑΓΟΝΑ ΥΓΡΑΣΙΑΣ
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.water_drop, size: 9, color: Color(0xFF3B82F6)),
                                        Text('${day.maxHumidity}%', style: const TextStyle(fontSize: 8.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 🗺️ ΧΑΡΤΗΣ ΤΟΠΟΘΕΣΙΑΣ
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 4),
                            Text(t['gps_location']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                          ],
                        ),
                        Text('${hive.satellitesLocked} ${t['sats_fixed']}', style: const TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 110,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(12),
                        image: const DecorationImage(
                          image: NetworkImage('https://static-maps.yandex.ru/1.x/?ll=24.8880,41.1349&z=14&l=sat&size=450,150'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(12))),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_pin, color: Colors.redAccent, size: 30),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  hive.regionDescription,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Auto-Detection Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hive.isAutoRelocationEnabled ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      hive.isAutoRelocationEnabled ? Icons.radar : Icons.radar_outlined,
                      color: hive.isAutoRelocationEnabled ? const Color(0xFF0284C7) : Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t['auto_detect_title']!,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                    ),
                    Switch(
                      value: hive.isAutoRelocationEnabled,
                      activeColor: const Color(0xFF0284C7),
                      onChanged: (val) {
                        setState(() => hive.isAutoRelocationEnabled = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Transport Button
              ElevatedButton(
                onPressed: hive.isTransportMode ? _showPostTransportNameDialog : _showSlideToActivateDialog,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  backgroundColor: hive.isTransportMode ? const Color(0xFF2563EB) : const Color(0xFFD97706),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(hive.isTransportMode ? Icons.check_circle : Icons.local_shipping, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      hive.isTransportMode ? t['stop_transport']! : t['start_transport']!,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (hive.isTransportMode) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatTimer(hive.transportRemaining),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Request Scale Reading Button
              OutlinedButton.icon(
                onPressed: isSyncing
                    ? null
                    : () async {
                        setState(() => isSyncing = true);
                        await _fetchLiveOnlineData();
                        setState(() {
                          isSyncing = false;
                          hive.currentWeight += 0.05;
                          hive.hourlyWeights48h.last = hive.currentWeight;
                        });
                      },
                icon: isSyncing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_sync),
                label: Text(isSyncing ? t['syncing']! : t['request_reading']!),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color == Colors.orange || color == Colors.blue || color == Colors.green ? const Color(0xFF1E293B) : color), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// 📈 48-HOUR CANVAS PAINTER
class WeightChartPainter extends CustomPainter {
  final List<double> data;
  WeightChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    double minVal = data.reduce(math.min);
    double maxVal = data.reduce(math.max);

    if (maxVal - minVal < 0.2) {
      minVal -= 0.5;
      maxVal += 0.5;
    } else {
      minVal -= 0.1;
      maxVal += 0.1;
    }

    final linePaint = Paint()
      ..color = const Color(0xFFD97706)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFF59E0B).withOpacity(0.35), const Color(0xFFF59E0B).withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = (data[i] - minVal) / (maxVal - minVal);
      final y = size.height - (normalizedY * (size.height - 10)) - 5;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final lastX = size.width;
    final lastNormalizedY = (data.last - minVal) / (maxVal - minVal);
    final lastY = size.height - (lastNormalizedY * (size.height - 10)) - 5;
    canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = const Color(0xFFB45309));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 💨 ΑΥΘΕΝΤΙΚΟ ΑΝΕΜΟΥΡΙΟ (WINDSOCK PAINTER)
class WindsockPainter extends CustomPainter {
  final bool isAlert;
  WindsockPainter({this.isAlert = false});

  @override
  void paint(Canvas canvas, Size size) {
    final orange = Paint()..color = isAlert ? const Color(0xFFEA580C) : const Color(0xFFF97316)..style = PaintingStyle.fill;
    final white = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final line = Paint()..color = isAlert ? const Color(0xFF9A3412) : const Color(0xFF94A3B8)..strokeWidth = 1.0..style = PaintingStyle.stroke;

    // Ropes on the left
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(3, size.height * 0.15), line);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(3, size.height * 0.85), line);

    void drawStripe(double x1, double x2, double h1, double h2, Paint p) {
      Path path = Path()
        ..moveTo(x1, (size.height - h1) / 2)
        ..lineTo(x2, (size.height - h2) / 2)
        ..lineTo(x2, (size.height + h2) / 2)
        ..lineTo(x1, (size.height + h1) / 2)
        ..close();
      canvas.drawPath(path, p);
    }

    // 4 Stripes: Orange - White - Orange - White
    drawStripe(3, 6, size.height * 0.9, size.height * 0.75, orange);
    drawStripe(6, 9, size.height * 0.75, size.height * 0.6, white);
    drawStripe(9, 12, size.height * 0.6, size.height * 0.45, orange);
    drawStripe(12, 15, size.height * 0.45, size.height * 0.3, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}