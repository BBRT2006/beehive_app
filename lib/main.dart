import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:volume_controller/volume_controller.dart'; 

// Global foreground player
final AudioPlayer _foregroundPlayer = AudioPlayer();

// 1. Αυτή η συνάρτηση τρέχει στο παρασκήνιο (όταν το app είναι εντελώς κλειστό)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  debugPrint("🚨 ΞΥΠΝΗΜΑ ΣΤΟ ΠΑΡΑΣΚΗΝΙΟ: Ήρθε ειδοποίηση με ID: ${message.messageId}");
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  final title = message.notification?.title ?? message.data['title'] ?? '';
  final type = message.data['type'] ?? '';
  final hiveName = message.data['hive_name'] ?? 'Κυψέλη';
  final hiveId = message.data['hive_id'] ?? '';

  final isTheft = type == 'theft' || title.contains('ΚΛΟΠΗ') || title.contains('THEFT') || title.contains('ΣΥΝΑΓΕΡΜΟΣ');

  // --- ΑΥΣΤΗΡΗ ΑΠΟΦΥΓΗ ΔΙΠΛΟΤΥΠΩΝ (5-minute Debounce) ---
  final history = prefs.getStringList('alerts_history_log') ?? [];
  bool isDuplicate = false;
  
  for (var log in history) {
    try {
      final item = jsonDecode(log);
      final logTime = DateTime.parse(item['date']);
      // Αν υπάρχει ήδη κλοπή για αυτή την κυψέλη τα τελευταία 5 λεπτά, είναι διπλότυπο!
      if (isTheft && item['isTheft'] == true && item['hive_id'] == hiveId && DateTime.now().difference(logTime).inMinutes < 5) {
        isDuplicate = true;
        break;
      }
    } catch (_) {}
  }

  // Αγνόησε άδεια μηνύματα ή διπλότυπα
  if (isDuplicate || (title.isEmpty && (message.notification?.body ?? message.data['body'] ?? '').isEmpty && !isTheft)) {
    return;
  }

  // Καταγραφή στο ιστορικό
  final logEntry = jsonEncode({
    'title': isTheft ? '🚨 Συναγερμός Κλοπής' : (title.isNotEmpty ? title : 'Ειδοποίηση'),
    'body': message.notification?.body ?? message.data['body'] ?? '',
    'date': DateTime.now().toIso8601String(),
    'isTheft': isTheft,
    'hive_id': hiveId,
    'hive_name': hiveName,
  });
  history.insert(0, logEntry);
  await prefs.setStringList('alerts_history_log', history);

  // Αν είναι όντως κλοπή, βάρα τη σειρήνα
  if (isTheft) {
    await prefs.setBool('stop_alarm', false);

    // 1. Βάζουμε την ένταση στο 95% 
    try { VolumeController.instance.setVolume(0.95); } catch (_) {}

    // 2. Περιμένουμε 1.5 δευτερόλεπτο για να περάσει ο ήχος του Android 
    // και να προλάβει να εδραιωθεί το 95% volume.
    await Future.delayed(const Duration(milliseconds: 1500));

    // 3. Παίρνουμε τη νέα βάση έντασης
    double? baselineVol;
    try { baselineVol = await VolumeController.instance.getVolume(); } catch (_) {}

    // 4. Ξεκινάμε να ακούμε τα κουμπιά (Single-Click Kill Switch)
    try {
      VolumeController.instance.addListener((volume) async {
        if (baselineVol != null && (volume - baselineVol!).abs() > 0.02) {
          await prefs.setBool('stop_alarm', true); // Κλείνει με 1 κλικ!
        }
      });
    } catch (_) {}

    // 5. Παίζει το custom MP3 στο System Media Channel
    final AudioPlayer bgPlayer = AudioPlayer();
    try {
      await bgPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.media,
          contentType: AndroidContentType.music,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
      ));
      await bgPlayer.setReleaseMode(ReleaseMode.loop);
      await bgPlayer.play(AssetSource('audio/siren.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint("AudioPlayer Background Error: $e");
    }

    // 6. Κρατάμε το background isolate ζωντανό
    for (int i = 0; i < 300; i++) { 
      await Future.delayed(const Duration(seconds: 1));
      await prefs.reload(); 
      if (prefs.getBool('stop_alarm') == true) {
        break; // Ο χρήστης πάτησε το κουμπί έντασης!
      }
    }
    
    try { await bgPlayer.stop(); } catch(_) {}
    try { VolumeController.instance.removeListener(); } catch (_) {}
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://epushislkdntilbobdgk.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwdXNoaXNsa2RudGlsYm9iZGdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwNzc3MjUsImV4cCI6MjEwMzY1MzcyNX0.HjmJPQEKs_GHQtaN9Jk7kHB7AwaQdnJeq5_BvaCL3c0',
    );
  } catch (e) {
    debugPrint("⚠️ Supabase Init Error: $e");
  }

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final fcmToken = await FirebaseMessaging.instance.getToken().timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    if (fcmToken != null) {
      debugPrint("📱 TO ΜΟΝΑΔΙΚΟ FCM TOKEN ΑΥΤΟΥ ΤΟΥ ΚΙΝΗΤΟΥ ΕΙΝΑΙ: $fcmToken");
    }
  } catch (e) {
    debugPrint("⚠️ Firebase Init Error: $e");
  }

  runApp(const BeehiveApp());
}

final supabase = Supabase.instance.client;

class BeehiveApp extends StatefulWidget {
  const BeehiveApp({super.key});

  @override
  State<BeehiveApp> createState() => _BeehiveAppState();
}

class _BeehiveAppState extends State<BeehiveApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authStateSubscription;

  String _currentLanguage = 'el';
  bool _isWeightGainNotificationEnabled = true; 
  bool _isSwarmingNotificationEnabled = true;
  
  int _telemetryIntervalMinutes = 60; 
  int _inspectionTimerMinutes = 45; 
  int _transportTimerHours = 24;

  @override
  void initState() {
    super.initState();
    _authStateSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showUpdatePasswordDialog();
        });
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  void _changeLanguage(String lang) => setState(() => _currentLanguage = lang);
  void _toggleWeightGainNotification(bool val) => setState(() => _isWeightGainNotificationEnabled = val); 
  void _toggleSwarmingNotification(bool val) => setState(() => _isSwarmingNotificationEnabled = val);

  void _showUpdatePasswordDialog() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    
    final pwdController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.lock_reset, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Text(_currentLanguage == 'el' ? 'Επαναφορά Κωδικού' : 'Reset Password', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentLanguage == 'el' ? 'Πληκτρολογήστε τον νέο σας κωδικό πρόσβασης.' : 'Enter your new password.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pwdController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _currentLanguage == 'el' ? 'Νέος Κωδικός' : 'New Password',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
                  onPressed: isUpdating ? null : () async {
                    if (pwdController.text.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_currentLanguage == 'el' ? 'Πρέπει να έχει 6+ χαρακτήρες.' : 'Must be at least 6 characters.')));
                      return;
                    }
                    setDialogState(() => isUpdating = true);
                    try {
                      await supabase.auth.updateUser(UserAttributes(password: pwdController.text.trim()));
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_currentLanguage == 'el' ? 'Ο κωδικός άλλαξε επιτυχώς!' : 'Password updated successfully!')));
                      }
                    } catch (e) {
                      setDialogState(() => isUpdating = false);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  child: isUpdating 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : Text(_currentLanguage == 'el' ? 'Αποθήκευση' : 'Save'),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey, 
      title: 'CleverScale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFD97706),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = supabase.auth.currentSession;
          if (session == null) {
            return AuthScreen(currentLanguage: _currentLanguage, onLanguageChanged: _changeLanguage);
          }
          return MultiHiveDashboard(
            currentLanguage: _currentLanguage,
            onLanguageChanged: _changeLanguage,
            isWeightGainNotificationEnabled: _isWeightGainNotificationEnabled,
            onWeightGainNotificationToggled: _toggleWeightGainNotification,
            isSwarmingNotificationEnabled: _isSwarmingNotificationEnabled,
            onSwarmingNotificationToggled: _toggleSwarmingNotification,
            telemetryIntervalMinutes: _telemetryIntervalMinutes,
            inspectionTimerMinutes: _inspectionTimerMinutes,
            transportTimerHours: _transportTimerHours,
            onSettingsChanged: (tel, insp, trans) {
              setState(() {
                _telemetryIntervalMinutes = tel;
                _inspectionTimerMinutes = insp;
                _transportTimerHours = trans;
              });
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// 1. AUTH SCREEN
// ==========================================
class AuthScreen extends StatefulWidget {
  final String currentLanguage;
  final ValueChanged<String> onLanguageChanged;
  const AuthScreen({super.key, required this.currentLanguage, required this.onLanguageChanged});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.length < 6) return;
    
    setState(() { 
      _isLoading = true; 
      _errorMessage = null; 
    });
    
    try {
      if (_isSignUp) {
        await supabase.auth.signUp(email: email, password: password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              widget.currentLanguage == 'el'
                ? 'Ο λογαριασμός δημιουργήθηκε! Συνδεθείτε.'
                : 'Account created! Please sign in.',
              style: const TextStyle(fontSize: 16),
            ),
          ));
        }
        setState(() => _isSignUp = false);
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.currentLanguage == 'el' ? 'Συμπληρώστε το email σας πάνω και πατήστε ξανά.' : 'Enter your email above and press again.')));
      return;
    }
    try {
      setState(() => _isLoading = true);
      await supabase.auth.resetPasswordForEmail(email, redirectTo: 'io.supabase.beehive://login-callback/');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.currentLanguage == 'el' ? 'Ελέγξτε το email σας για οδηγίες.' : 'Check your email for reset instructions.')));
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleLogin() async {
    try {
      setState(() => _isLoading = true);
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google, 
        redirectTo: kIsWeb ? Uri.base.origin : 'io.supabase.beehive://login-callback/',
      );
    } catch (_) {} 
    finally { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEl = widget.currentLanguage == 'el';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hive, size: 54, color: Color(0xFFD97706)),
                    const SizedBox(height: 10),
                    Text(
                      isEl ? 'Μελισσοκομικός Έλεγχος' : 'CleverScale Monitor', 
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                    ),
                    Text(
                      _isSignUp ? (isEl ? 'Δημιουργία Λογαριασμού' : 'Create Account') : (isEl ? 'Σύνδεση Μελισσοκόμου' : 'Beekeeper Login'), 
                      style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(10), 
                        margin: const EdgeInsets.only(bottom: 12), 
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)), 
                        child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 14)),
                      ),
                    TextField(
                      controller: _emailController, 
                      keyboardType: TextInputType.emailAddress, 
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Email', 
                        prefixIcon: const Icon(Icons.email_outlined), 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController, 
                      obscureText: true, 
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: isEl ? 'Κωδικός' : 'Password', 
                        prefixIcon: const Icon(Icons.lock_outline), 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity, 
                      height: 52, 
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD97706), 
                          foregroundColor: Colors.white, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ), 
                        onPressed: _isLoading ? null : _submitAuth, 
                        child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : Text(
                              _isSignUp ? (isEl ? 'Εγγραφή' : 'Sign Up') : (isEl ? 'Σύνδεση' : 'Sign In'), 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                      ),
                    ),
                    if (!_isSignUp)
                      TextButton(
                        onPressed: _resetPassword,
                        child: Text(isEl ? 'Ξεχάσατε τον κωδικό;' : 'Forgot your password?', style: const TextStyle(color: Colors.grey)),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(child: Divider()), 
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10), 
                          child: Text(isEl ? 'ή σύνδεση με' : 'or continue with', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ), 
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity, 
                      height: 52,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.g_mobiledata, size: 32, color: Color(0xFFEA4335)), 
                        label: const Text('Google', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16)), 
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ), 
                        onPressed: _isLoading ? null : _googleLogin,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() => _isSignUp = !_isSignUp), 
                      child: Text(
                        _isSignUp ? (isEl ? 'Έχετε ήδη λογαριασμό; Σύνδεση' : 'Have an account? Sign in') : (isEl ? 'Νέος χρήστης; Δημιουργία λογαριασμού' : 'New user? Sign up'), 
                        style: const TextStyle(fontSize: 14, color: Color(0xFFD97706), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. SETTINGS SCREEN
// ==========================================
class SettingsScreen extends StatefulWidget {
  final String currentLanguage;
  final ValueChanged<String> onLanguageChanged;
  final bool isWeightGainNotificationEnabled;
  final ValueChanged<bool> onWeightGainNotificationToggled;
  final bool isSwarmingNotificationEnabled;
  final ValueChanged<bool> onSwarmingNotificationToggled;
  
  final int telemetryIntervalMinutes;
  final int inspectionTimerMinutes;
  final int transportTimerHours;
  final Function(int, int, int) onSettingsChanged;

  const SettingsScreen({
    super.key, 
    required this.currentLanguage, 
    required this.onLanguageChanged,
    required this.isWeightGainNotificationEnabled,
    required this.onWeightGainNotificationToggled,
    required this.isSwarmingNotificationEnabled,
    required this.onSwarmingNotificationToggled,
    required this.telemetryIntervalMinutes, 
    required this.inspectionTimerMinutes,
    required this.transportTimerHours, 
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _telemetry;
  late int _inspection;
  late int _transport;
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    _telemetry = widget.telemetryIntervalMinutes;
    _inspection = widget.inspectionTimerMinutes;
    _transport = widget.transportTimerHours;
  }

  void _saveSettings() {
    widget.onSettingsChanged(_telemetry, _inspection, _transport);
  }

  String _formatTime(int minutes) {
    if (minutes < 60) return '$minutes ${widget.currentLanguage == 'el' ? 'λεπτά' : 'mins'}';
    double hrs = minutes / 60;
    return '${hrs.toStringAsFixed(hrs.truncateToDouble() == hrs ? 0 : 1)} ${widget.currentLanguage == 'el' ? 'ώρες' : 'hrs'}';
  }

  Future<void> _linkGoogle() async {
    try {
      setState(() => _linking = true);
      await supabase.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.origin : 'io.supabase.beehive://login-callback/',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            widget.currentLanguage == 'el' ? 'Ολοκληρώθηκε η σύνδεση λογαριασμού!' : 'Account linked successfully!',
            style: const TextStyle(fontSize: 16),
          ),
        ));
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message, style: const TextStyle(fontSize: 16))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to link Google.', style: const TextStyle(fontSize: 16))));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEl = widget.currentLanguage == 'el';
    final user = supabase.auth.currentUser;
    final identities = user?.identities ?? [];
    final hasGoogle = identities.any((i) => i.provider == 'google');

    return Scaffold(
      appBar: AppBar(
        title: Text(isEl ? 'Ρυθμίσεις' : 'Settings', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22)),
        backgroundColor: const Color(0xFFD97706),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.timer, color: Color(0xFFD97706)),
              title: Text(
                isEl ? 'ΧΡΟΝΟΔΙΑΚΟΠΤΕΣ & ΣΥΧΝΟΤΗΤΑ' : 'SYSTEM TIMERS & INTERVALS', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cell_tower, color: Color(0xFFD97706), size: 20), 
                        const SizedBox(width: 8), 
                        Text(isEl ? 'Συχνότητα Τηλεμετρίας' : 'Telemetry Interval', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Text(_formatTime(_telemetry), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706), fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _telemetry.toDouble(),
                  min: 30, max: 300, divisions: 9, 
                  activeColor: const Color(0xFFD97706),
                  onChanged: (val) { setState(() => _telemetry = val.toInt()); _saveSettings(); },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    isEl ? '* Οι αλλαγές εφαρμόζονται μετά την επόμενη επικοινωνία της ζυγαριάς.' : '* Changes take effect after the scale\'s next scheduled wake-up.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.build_circle, color: Color(0xFFD97706), size: 20), 
                        const SizedBox(width: 8), 
                        Text(isEl ? 'Χρονόμετρο Επιθεώρησης' : 'Inspection Timer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Text(_formatTime(_inspection), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706), fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _inspection.toDouble(),
                  min: 15, max: 120, divisions: 7, 
                  activeColor: const Color(0xFFD97706),
                  onChanged: (val) { setState(() => _inspection = val.toInt()); _saveSettings(); },
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_shipping, color: Color(0xFFD97706), size: 20), 
                        const SizedBox(width: 8), 
                        Text(isEl ? 'Χρονόμετρο Μεταφοράς' : 'Transport Timer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Text('$_transport ${isEl ? 'ώρες' : 'hrs'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706), fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _transport.toDouble(),
                  min: 6, max: 48, divisions: 7, 
                  activeColor: const Color(0xFFD97706),
                  onChanged: (val) { setState(() => _transport = val.toInt()); _saveSettings(); },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.app_settings_alt, color: Color(0xFFD97706)),
              title: Text(
                isEl ? 'ΛΕΙΤΟΥΡΓΙΕΣ ΕΦΑΡΜΟΓΗΣ' : 'APP FEATURES', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                // 1kg Gain Notification
                Row(
                  children: [
                    Icon(
                      widget.isWeightGainNotificationEnabled ? Icons.trending_up : Icons.trending_up,
                      color: widget.isWeightGainNotificationEnabled ? const Color(0xFF0284C7) : Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isEl ? 'Ειδοποίηση Αύξησης 1kg/24h' : '1kg/24h Gain Alert', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(isEl ? 'Λήψη ειδοποίησης σε μεγάλη νεκταροέκκριση' : 'Get notified during heavy nectar flow', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.isWeightGainNotificationEnabled,
                      activeColor: const Color(0xFF0284C7),
                      onChanged: widget.onWeightGainNotificationToggled,
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Swarming Alert Toggle
                Row(
                  children: [
                    Icon(
                      widget.isSwarmingNotificationEnabled ? Icons.flight_takeoff : Icons.flight_takeoff_outlined,
                      color: widget.isSwarmingNotificationEnabled ? const Color(0xFFD97706) : Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isEl ? 'Ειδοποίηση Σμηνουργίας (1.2-3.8kg)' : 'Swarming Event Alert (1.2-3.8kg)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(isEl ? 'Ανίχνευση ξαφνικής απώλειας βάρους σμήνους' : 'Detect sudden colony weight loss from swarming', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.isSwarmingNotificationEnabled,
                      activeColor: const Color(0xFFD97706),
                      onChanged: widget.onSwarmingNotificationToggled,
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.language, color: Color(0xFFD97706), size: 22),
                    const SizedBox(width: 8),
                    Text(isEl ? 'Γλώσσα Εφαρμογής' : 'Application Language', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: widget.currentLanguage == 'el' ? const Color(0xFFD97706) : Colors.white, 
                          foregroundColor: widget.currentLanguage == 'el' ? Colors.white : const Color(0xFF1E293B),
                        ), 
                        onPressed: () => widget.onLanguageChanged('el'), 
                        child: const Text('🇬🇷 Ελληνικά', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: widget.currentLanguage == 'en' ? const Color(0xFFD97706) : Colors.white, 
                          foregroundColor: widget.currentLanguage == 'en' ? Colors.white : const Color(0xFF1E293B),
                        ), 
                        onPressed: () => widget.onLanguageChanged('en'), 
                        child: const Text('🇬🇧 English', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.person, color: Color(0xFFD97706)),
              title: Text(
                isEl ? 'ΡΥΘΜΙΣΕΙΣ ΛΟΓΑΡΙΑΣΜΟΥ' : 'ACCOUNT SETTINGS', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 22),
                    const SizedBox(width: 8),
                    Text(isEl ? 'Πληροφορίες Χρήστη' : 'User Information', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  ],
                ),
                const Divider(height: 20),
                Text('Email: ${user?.email ?? "N/A"}', style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text('User ID: ${user?.id ?? "N/A"}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.g_mobiledata, size: 38, color: Color(0xFFEA4335)),
                  title: const Text('Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(
                    hasGoogle ? (isEl ? 'Συνδεδεμένο' : 'Connected') : (isEl ? 'Μη συνδεδεμένο' : 'Not Connected'),
                    style: TextStyle(fontSize: 13, color: hasGoogle ? Colors.green : Colors.grey),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasGoogle ? Colors.grey.shade300 : const Color(0xFFD97706),
                      foregroundColor: hasGoogle ? Colors.black54 : Colors.white,
                    ),
                    onPressed: (_linking || hasGoogle) ? null : _linkGoogle,
                    child: Text(hasGoogle ? (isEl ? 'Συνδέθηκε' : 'Linked') : (isEl ? 'Σύνδεση' : 'Connect'), style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.white,
            leading: const Icon(Icons.logout, color: Colors.redAccent, size: 24),
            title: Text(
              isEl ? 'Αποσύνδεση Λογαριασμού' : 'Log Out', 
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onTap: () { 
              Navigator.pop(context); 
              supabase.auth.signOut(); 
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ==========================================
// 3. DATA MODELS
// ==========================================
class DayForecast {
  final String dayName; 
  final String dateStr; 
  final double maxTemp; 
  final double minTemp;
  final double maxWindSpeedKmH; 
  final int maxHumidity; 
  final int weatherCode; 
  final int rainProbability;

  DayForecast({
    required this.dayName, 
    required this.dateStr, 
    required this.maxTemp, 
    required this.minTemp, 
    required this.maxWindSpeedKmH, 
    required this.maxHumidity, 
    required this.weatherCode, 
    required this.rainProbability,
  });
}

class HiveNote {
  final String date; 
  String text; 

  HiveNote({
    required this.date, 
    required this.text,
  });
}

class HiveData {
  String id;
  String name;
  String apiaryName;
  String regionDescription;
  DateTime sitePlacedDate;
  DateTime? lastTelemetryTime;
  double currentWeight;
  double baselineWeight;
  double preInspectionWeight; 
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

  List<HiveNote> notes;
  List<DayForecast> weatherForecast;
  List<double> hourlyWeights48h;
  List<Map<String, dynamic>> locationHistory;
  Map<String, List<Map<String, dynamic>>> archivedYears;
  
  List<LatLng> recentPath;

  HiveData({
    required this.id, 
    required this.name, 
    required this.apiaryName, 
    required this.regionDescription,
    required this.sitePlacedDate, 
    this.lastTelemetryTime, 
    required this.currentWeight, 
    required this.baselineWeight,
    this.preInspectionWeight = 0.0,
    required this.outdoorTemp, 
    required this.outdoorHumidity, 
    required this.batteryVolts,
    required this.batteryPct, 
    required this.signalDbm, 
    required this.satellitesLocked, 
    required this.latitude, 
    required this.longitude,
    this.fireRiskCategoryToday = 2, 
    this.fireRiskCategoryTomorrow = 2, 
    this.isTheftAlertTriggered = false,
    this.isInspectionMode = false, 
    this.inspectionRemaining = 2700, 
    this.isTransportMode = false, 
    this.transportStartTime,
    this.transportRemaining = 86400, 
    required this.notes, 
    required this.weatherForecast, 
    required this.hourlyWeights48h,
    required this.locationHistory, 
    required this.archivedYears,
    this.recentPath = const [],
  });
}

// ==========================================
// 4. MAIN MULTI-HIVE DASHBOARD
// ==========================================
class MultiHiveDashboard extends StatefulWidget {
  final String currentLanguage;
  final ValueChanged<String> onLanguageChanged;
  final bool isWeightGainNotificationEnabled;
  final ValueChanged<bool> onWeightGainNotificationToggled;
  final bool isSwarmingNotificationEnabled;
  final ValueChanged<bool> onSwarmingNotificationToggled;
  
  final int telemetryIntervalMinutes;
  final int inspectionTimerMinutes;
  final int transportTimerHours;
  final Function(int, int, int) onSettingsChanged;

  const MultiHiveDashboard({
    super.key, 
    required this.currentLanguage, 
    required this.onLanguageChanged,
    required this.isWeightGainNotificationEnabled,
    required this.onWeightGainNotificationToggled,
    required this.isSwarmingNotificationEnabled,
    required this.onSwarmingNotificationToggled,
    required this.telemetryIntervalMinutes, 
    required this.inspectionTimerMinutes,
    required this.transportTimerHours, 
    required this.onSettingsChanged,
  });

  @override
  State<MultiHiveDashboard> createState() => _MultiHiveDashboardState();
}

class _MultiHiveDashboardState extends State<MultiHiveDashboard> {
  List<HiveData> hives = [];
  int selectedHiveIndex = 0;
  bool isLoadingHives = true;

  Timer? _globalTicker;
  Timer? _sirenTimer;
  bool _blinkRed = false;

  bool isSyncing = false;

  double _visibleHours = 48.0;
  double _scrollOffset = 0.0;
  double _baseScaleVisibleHours = 48.0;
  
  String? _activeDrawerEditHiveId; 
  double? _crosshairX;
  bool _showTransportSlider = false; 
  
  SharedPreferences? _prefs;

  Future<void> _saveDeviceToken() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await supabase.from('user_tokens').upsert({
          'user_id': user.id,
          'token': token,
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ FCM Token saved to Supabase');
      }
    } catch (e) {
      debugPrint('Error saving Token: $e');
    }
  }

  // Silences the sound ONLY
  Future<void> _silenceSirenOnly() async {
    try { await _foregroundPlayer.stop(); } catch(_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stop_alarm', true);
  }

  // Silences sound AND dismisses the theft alert in state and cloud
  Future<void> _dismissAlert(HiveData hive) async {
    await _silenceSirenOnly();
    setState(() => hive.isTheftAlertTriggered = false);
    try {
      await supabase.from('hives').update({'is_theft_alert_triggered': false}).eq('hive_id', hive.id);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _loadUserHives();
    _saveDeviceToken();
    
    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint("🔔 Foreground message arrived!");
      
      final title = message.notification?.title ?? message.data['title'] ?? '';
      final type = message.data['type'] ?? '';
      final hiveId = message.data['hive_id'] ?? '';
      final hiveName = message.data['hive_name'] ?? 'Κυψέλη';
      final isTheft = type == 'theft' || title.contains('ΚΛΟΠΗ') || title.contains('THEFT') || title.contains('ΣΥΝΑΓΕΡΜΟΣ');

      // --- DEDUPLICATION LOGIC FOREGROUND ---
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('alerts_history_log') ?? [];
      bool isDuplicate = false;
      
      for (var log in history) {
        try {
          final item = jsonDecode(log);
          final logTime = DateTime.parse(item['date']);
          if (isTheft && item['isTheft'] == true && item['hive_id'] == hiveId && DateTime.now().difference(logTime).inMinutes < 5) {
            isDuplicate = true;
            break;
          }
        } catch (_) {}
      }

      if (isDuplicate || (title.isEmpty && (message.notification?.body ?? message.data['body'] ?? '').isEmpty && !isTheft)) {
        return;
      }

      final logEntry = jsonEncode({
        'title': isTheft ? '🚨 Συναγερμός Κλοπής' : (title.isNotEmpty ? title : 'Ειδοποίηση'),
        'body': message.notification?.body ?? message.data['body'] ?? '',
        'date': DateTime.now().toIso8601String(),
        'isTheft': isTheft,
        'hive_id': hiveId,
        'hive_name': hiveName,
      });
      history.insert(0, logEntry);
      await prefs.setStringList('alerts_history_log', history);
      setState(() {}); 

      if (isTheft) {
        try { VolumeController.instance.setVolume(0.95); } catch (_) {}

        await Future.delayed(const Duration(milliseconds: 1500));
        
        try {
          await _foregroundPlayer.setAudioContext(AudioContext(
            android: AudioContextAndroid(
              usageType: AndroidUsageType.media,
              contentType: AndroidContentType.music,
              audioFocus: AndroidAudioFocus.gainTransientExclusive,
            ),
          ));
          await _foregroundPlayer.setReleaseMode(ReleaseMode.loop);
          await _foregroundPlayer.play(AssetSource('audio/siren.mp3'), volume: 1.0);
        } catch (e) {
          debugPrint("AudioPlayer Foreground Error: $e");
        }
      }
      _loadUserHives(); 
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("🔔 App opened via notification!");
      _loadUserHives(); 
    });

    // Hardware volume button listener (Single-Click Kill Switch)
    try {
      double? lastVol;
      VolumeController.instance.getVolume().then((v) => lastVol = v).catchError((_) {});
      VolumeController.instance.addListener((volume) {
        if (lastVol != null && (volume - lastVol!).abs() > 0.02) {
          final h = activeHive;
          if (h != null && h.isTheftAlertTriggered) {
            _silenceSirenOnly();
          }
        }
        lastVol = volume;
      });
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) { 
      _checkDisplayName(); 
    });

    _globalTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (hives.isEmpty) return;
      bool needsRebuild = false;
      for (var hive in hives) {
        if (hive.isInspectionMode) {
          if (hive.inspectionRemaining > 0) { 
            hive.inspectionRemaining--; 
            needsRebuild = true; 
          } else { 
            hive.isInspectionMode = false; 
            double weightDiff = hive.currentWeight - hive.preInspectionWeight;
            hive.baselineWeight += weightDiff; 
            needsRebuild = true; 
            _syncHiveToCloud(hive);
          }
        }
        if (hive.isTransportMode) {
          if (hive.transportRemaining > 0) { 
            hive.transportRemaining--; 
            needsRebuild = true; 
          } else { 
            hive.isTransportMode = false; 
            needsRebuild = true; 
            _syncHiveToCloud(hive);
          }
        }
      }

      bool hasTheft = hives.any((h) => h.isTheftAlertTriggered);
      if (hasTheft && _sirenTimer == null) {
        _sirenTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
          if (mounted) setState(() => _blinkRed = !_blinkRed);
        });
      } else if (!hasTheft && _sirenTimer != null) {
        _sirenTimer?.cancel();
        _sirenTimer = null;
        if (mounted) setState(() => _blinkRed = false);
      }

      if (needsRebuild && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sirenTimer?.cancel();
    _globalTicker?.cancel();
    try {
      _foregroundPlayer.dispose();
    } catch(_) {}
    try {
      VolumeController.instance.removeListener();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
  }
  
  Future<void> _checkDisplayName() async {
    final user = supabase.auth.currentUser;
    if (user != null && (user.userMetadata == null || user.userMetadata!['display_name'] == null || user.userMetadata!['display_name'] == '')) {
      _showDisplayNameDialog();
    }
  }

  void _showDisplayNameDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.currentLanguage == 'el' ? 'Καλώς ήρθατε!' : 'Welcome!',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.currentLanguage == 'el' ? 'Πώς να σας αποκαλούμε;' : 'What should we call you?', 
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController, 
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: widget.currentLanguage == 'el' ? 'Όνομα Μελισσοκόμου' : 'Beekeeper Name', 
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706), 
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await supabase.auth.updateUser(UserAttributes(data: {'display_name': name}));
                if (mounted) { 
                  setState(() {}); 
                  Navigator.pop(ctx); 
                }
              }
            },
            child: Text(t['save']!, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _syncHiveToCloud(HiveData hive) async {
    try {
      await supabase.from('hives').update({
        'apiary_name': hive.apiaryName,
        'baseline_weight': hive.baselineWeight,
        'notes': hive.notes.map((n) => {'date': n.date, 'text': n.text}).toList(),
        'location_history': hive.locationHistory,
        'archived_years': hive.archivedYears,
      }).eq('hive_id', hive.id);
    } catch (e) {
      debugPrint('Failed to sync hive data: $e');
    }
  }

  Future<void> _loadUserHives() async {
    if (!mounted) return;
    setState(() => isLoadingHives = true);
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) { 
        if (mounted) setState(() => isLoadingHives = false); 
        return; 
      }

      final res = await supabase.from('hives').select().eq('owner_id', user.id).order('created_at');
      final List<dynamic> rows = res as List<dynamic>;

      if (rows.isEmpty) {
        if (mounted) {
          setState(() { 
            hives = []; 
            isLoadingHives = false; 
          });
        }
      } else {
        List<HiveData> loaded = [];
        for (var r in rows) {
          final Map<String, dynamic> row = r as Map<String, dynamic>;
          
          final notesRaw = row['notes'] as List<dynamic>? ?? [];
          List<HiveNote> parsedNotes = notesRaw.map((n) => HiveNote(date: n['date'], text: n['text'])).toList();
          
          final histRaw = row['location_history'] as List<dynamic>? ?? [
            {"day": widget.currentLanguage == 'el' ? "1η Ημέρα (Άφιξη)" : "Day 1 (Arrival)", "weight": 40.0, "gain": "+0.00 kg"}
          ];
          List<Map<String, dynamic>> parsedHist = histRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

          final archRaw = row['archived_years'] as Map<String, dynamic>? ?? {};
          Map<String, List<Map<String, dynamic>>> parsedArch = {};
          archRaw.forEach((k, v) {
            parsedArch[k] = (v as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });

          loaded.add(HiveData(
            id: row['hive_id'] ?? 'N/A', 
            name: row['hive_name'] ?? 'Κυψέλη', 
            apiaryName: row['apiary_name'] ?? 'Μελισσοκομείο Ξάνθης',
            regionDescription: 'Ξάνθη', 
            sitePlacedDate: DateTime.now(), 
            lastTelemetryTime: DateTime.now().subtract(const Duration(minutes: 5)),
            currentWeight: 45.0, 
            baselineWeight: ((row['baseline_weight'] as num?) ?? 40.0).toDouble(), 
            outdoorTemp: 28.0, 
            outdoorHumidity: 50.0, 
            batteryVolts: 3.32,
            batteryPct: 95, 
            signalDbm: -78, 
            latitude: 41.1349, 
            longitude: 24.8880, 
            satellitesLocked: 8,
            isTheftAlertTriggered: row['is_theft_alert_triggered'] ?? false,
            notes: parsedNotes,
            weatherForecast: [], 
            hourlyWeights48h: [45.0, 45.1, 45.3, 45.2, 45.5, 45.6],
            locationHistory: parsedHist,
            archivedYears: parsedArch,
            recentPath: [],
          ));
        }
        if (mounted) {
          setState(() { 
            hives = loaded; 
            if (selectedHiveIndex >= hives.length) selectedHiveIndex = 0; 
            isLoadingHives = false; 
          });
          _fetchLiveOnlineData();
          _fetchSupabaseTelemetry();
        }
      }
    } catch (e) { 
      debugPrint("Load Hives Error: $e");
      if (mounted) setState(() => isLoadingHives = false); 
    }
  }

  HiveData? get activeHive {
    if (hives.isEmpty || selectedHiveIndex >= hives.length) return null;
    return hives[selectedHiveIndex];
  }

  Future<void> _fetchSupabaseTelemetry() async {
    final hive = activeHive;
    if (hive == null) return;
    
    try {
      final res = await supabase
          .from('telemetry')
          .select()
          .eq('hive_id', hive.id)
          .order('created_at', ascending: false)
          .limit(48);
          
      final List<dynamic> data = res as List<dynamic>;

      if (data.isNotEmpty && mounted) {
        final Map<String, dynamic> latest = data.first as Map<String, dynamic>;
        setState(() {
          if (latest['created_at'] != null) {
            hive.lastTelemetryTime = DateTime.parse(latest['created_at']).toLocal();
          }
          if (latest['weight'] != null) hive.currentWeight = (latest['weight'] as num).toDouble();
          if (latest['temp'] != null) hive.outdoorTemp = (latest['temp'] as num).toDouble();
          if (latest['humidity'] != null) hive.outdoorHumidity = (latest['humidity'] as num).toDouble();
          if (latest['battery_pct'] != null) hive.batteryPct = (latest['battery_pct'] as num).toInt();
          if (latest['battery_mv'] != null) hive.batteryVolts = (latest['battery_mv'] as num).toDouble() / 1000.0;
          if (latest['signal_dbm'] != null) hive.signalDbm = (latest['signal_dbm'] as num).toInt();
          if (latest['latitude'] != null) hive.latitude = (latest['latitude'] as num).toDouble();
          if (latest['longitude'] != null) hive.longitude = (latest['longitude'] as num).toDouble();
          if (latest['satellites'] != null) hive.satellitesLocked = (latest['satellites'] as num).toInt();

          List<double> weights = [];
          List<LatLng> path = []; 
          
          for (var r in data.reversed) {
            final row = r as Map<String, dynamic>;
            weights.add((row['weight'] as num).toDouble());
            
            if (row['latitude'] != null && row['longitude'] != null) {
              path.add(LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble()));
            }
          }
          
          if (weights.isNotEmpty) hive.hourlyWeights48h = weights;
          if (path.isNotEmpty) hive.recentPath = path; 
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLiveOnlineData() async {
    final hive = activeHive;
    if (hive == null) return;
    
    try {
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${hive.latitude}&longitude=${hive.longitude}&current=temperature_2m,relative_humidity_2m&hourly=relative_humidity_2m&daily=weathercode,temperature_2m_max,temperature_2m_min,windspeed_10m_max,precipitation_probability_max&timezone=auto',
      );
      final weatherRes = await http.get(weatherUrl).timeout(const Duration(seconds: 4));
      
      if (weatherRes.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(weatherRes.body);

        if (data['current'] != null) {
          setState(() { 
            hive.outdoorTemp = (data['current']['temperature_2m'] as num).toDouble(); 
            hive.outdoorHumidity = (data['current']['relative_humidity_2m'] as num).toDouble(); 
          });
        }

        final Map<String, dynamic> daily = data['daily'];
        final Map<String, dynamic>? hourly = data['hourly'];

        final List<dynamic> times = daily['time'];
        final List<dynamic> maxTemps = daily['temperature_2m_max'];
        final List<dynamic> minTemps = daily['temperature_2m_min'];
        final List<dynamic> windSpeeds = daily['windspeed_10m_max'];
        final List<dynamic> weatherCodes = daily['weathercode'];
        final List<dynamic> rainProbabilities = daily['precipitation_probability_max'] ?? [];
        final List<dynamic> hourlyHumidities = hourly != null ? hourly['relative_humidity_2m'] : [];

        final List<DayForecast> fetchedDays = [];
        final daysOfWeekEl = ['Κυρ', 'Δευ', 'Τρι', 'Τετ', 'Πεμ', 'Παρ', 'Σαβ'];
        final daysOfWeekEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        for (int i = 0; i < math.min(5, times.length); i++) {
          final dt = DateTime.parse(times[i].toString());
          String dName = i == 0 
            ? (widget.currentLanguage == 'el' ? 'Σήμερα' : 'Today') 
            : (widget.currentLanguage == 'el' ? daysOfWeekEl[dt.weekday % 7] : daysOfWeekEn[dt.weekday % 7]);

          String formattedDate = '${dt.day}/${dt.month}';

          int avgHumidity = 50;
          if (hourlyHumidities.isNotEmpty) {
            double sum = 0;
            int count = 0;
            for (int h = i * 24; h < (i + 1) * 24 && h < hourlyHumidities.length; h++) {
              sum += (hourlyHumidities[h] as num).toDouble();
              count++;
            }
            if (count > 0) {
              avgHumidity = (sum / count).round();
            }
          }

          int rainProb = 0;
          if (rainProbabilities.length > i && rainProbabilities[i] != null) {
            rainProb = (rainProbabilities[i] as num).toInt();
          }

          fetchedDays.add(DayForecast(
            dayName: dName, 
            dateStr: formattedDate, 
            maxTemp: (maxTemps[i] as num).toDouble(), 
            minTemp: (minTemps[i] as num).toDouble(), 
            maxWindSpeedKmH: (windSpeeds[i] as num).toDouble(), 
            maxHumidity: avgHumidity, 
            weatherCode: (weatherCodes[i] as num).toInt(), 
            rainProbability: rainProb,
          ));
        }

        setState(() { 
          hive.weatherForecast = fetchedDays; 
        });
      }

      final fireRiskUrl = Uri.parse(
        'https://raw.githubusercontent.com/BBRT2006/beehive_app/main/fire_risk.json',
      );
      final fireRiskRes = await http.get(fireRiskUrl).timeout(const Duration(seconds: 4));
      
      if (fireRiskRes.statusCode == 200) {
        final fireData = jsonDecode(fireRiskRes.body);
        final regions = fireData['regions'] as Map<String, dynamic>?;
        if (regions != null) {
          setState(() { 
            hive.fireRiskCategoryToday = regions['Ξάνθη'] ?? 2; 
            hive.fireRiskCategoryTomorrow = regions['Ξάνθη'] ?? 2; 
          });
        }
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

  void _showFirstTimeScaleSyncDialog() {
    final hiveIdController = TextEditingController();
    final pinController = TextEditingController();
    final nameController = TextEditingController();
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Color(0xFFD97706), size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.currentLanguage == 'el' ? 'Σύνδεση Νέας Ζυγαριάς' : 'Scale Hardware Pairing',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.currentLanguage == 'el'
                        ? 'Εισάγετε το ID, το μυστικό PIN της συσκευασίας και ένα όνομα.'
                        : 'Enter the Hardware ID, the secret PIN from the box, and a custom name.',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)),
                      child: Text(dialogError!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13.5)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: hiveIdController,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Hardware Hive ID',
                      hintText: 'CS-12345',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: widget.currentLanguage == 'el' ? 'Μυστικό PIN' : 'Secret PIN',
                      hintText: '1234',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: widget.currentLanguage == 'el' ? 'Όνομα Κυψέλης' : 'Hive Name',
                      hintText: 'Κυψέλη #1',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final hid = hiveIdController.text.trim();
                          final pin = pinController.text.trim();
                          final name = nameController.text.trim();
                          
                          if (hid.isEmpty || pin.isEmpty) {
                            setDialogState(() {
                              dialogError = widget.currentLanguage == 'el' ? 'Συμπληρώστε το ID και το PIN.' : 'Please enter the ID and PIN.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            dialogError = null;
                          });

                          try {
                            final user = supabase.auth.currentUser;
                            if (user == null) throw Exception("Not logged in");

                            final response = await supabase
                                .from('hives')
                                .update({
                                  'owner_id': user.id,
                                  'hive_name': name.isNotEmpty ? name : hid,
                                  'is_theft_alert_triggered': false,
                                })
                                .eq('hive_id', hid)
                                .eq('pin', pin)
                                .isFilter('owner_id', null)
                                .select();

                            if (response.isEmpty) {
                              throw Exception("Invalid ID/PIN or already claimed.");
                            }

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                              _loadUserHives();
                            }
                          } catch (e) {
                            debugPrint('SUPABASE ERROR: $e');
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = widget.currentLanguage == 'el'
                                  ? 'Λάθος ID/PIN ή η ζυγαριά ανήκει σε άλλον.'
                                  : 'Invalid ID/PIN or scale already claimed.';
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(t['save']!, style: const TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, String> get t {
    if (widget.currentLanguage == 'el') {
      return {
        'app_title': 'Επισκόπηση Μελισσοκομείου', 
        'online': 'Συνδεδεμένο', 
        'transport_radio_muted': 'Σε Κατάσταση Μεταφοράς (Σίγαση)',
        'inspection_mode': 'Κατάσταση Επιθεώρησης', 
        'inspection_active': 'Επιθεώρηση Ενεργή', 
        'inspection_sub_off': 'Σίγαση συναγερμών', 
        'inspection_sub_on': 'Συναγερμοί σε σίγαση',
        'total_weight': 'ΣΥΝΟΛΙΚΟ ΒΑΡΟΣ ΚΥΨΕΛΗΣ', 
        'overall': 'συνολικά', 
        'ext_temp': 'Εξωτ. Θερμ.', 
        'humidity': 'Υγρασία', 
        'battery': 'Μπαταρία', 
        'signal': 'Σήμα 4G',
        'curve_title': 'Καμπύλη Βάρους', 
        'window': 'παράθυρο', 
        'gps_location': 'Τοποθεσία Μελισσοκομείου', 
        'start_transport': 'Έναρξη Μεταφοράς',
        'stop_transport': 'Τερματισμός Μεταφοράς', 
        'request_reading': 'Λήψη Νέας Μέτρησης', 
        'syncing': 'Συγχρονισμός...', 
        'archives_header': 'ΕΤΗΣΙΟ ΑΡΧΕΙΟ ΣΥΓΚΟΜΙΔΗΣ',
        'weight_after_transfer': 'Βάρος μετά την τελευταία μεταφορά',
        'season': 'Περίοδος', 
        'rename_location': 'Μετονομασία Μελισσοκομείου', 
        'rename_hive': 'Μετονομασία Κυψέλης', 
        'post_transport_title': 'Ολοκλήρωση Μεταφοράς 🐝',
        'post_transport_desc': 'Η μεταφορά έληξε. Πληκτρολογήστε το όνομα του νέου μελισσοκομείου:', 
        'add_hive': 'Προσθήκη Νέας Κυψέλης', 
        'hives_list': 'ΟΙ ΚΥΨΕΛΕΣ ΜΟΥ',
        'hive_notes': 'Σημειώσεις Κυψέλης', 
        'google_maps_open': 'Google Maps',
        'add_note': '+ Σημείωση', 
        'weather_forecast': 'Πρόγνωση Καιρού 5 Ημερών', 
        'fire_risk_header': 'Χάρτης Πρόβλεψης Κινδύνου Πυρκαγιάς',
        'today': 'ΣΗΜΕΡΑ', 
        'tomorrow': 'ΑΥΡΙΟ', 
        'allowed_short': 'ΕΠΙΤΡΕΠΕΤΑΙ', 
        'warning_short': 'ΑΠΑΓΟΡΕΥΣΗ', 
        'allowed_sub_short': 'Προσοχή στο καπνιστήρι',
        'warning_sub_short': 'Απαγόρευση καπνιστηριού', 
        'save': 'Αποθήκευση', 
        'cancel': 'Ακύρωση', 
        'settings': 'Ρυθμίσεις', 
        'logout': 'Αποσύνδεση',
        'delete_hive': 'Αφαίρεση Κυψέλης', 
        'delete_confirm': 'Η ζυγαριά θα αφαιρεθεί από τον λογαριασμό σας. Είστε σίγουροι;', 
        'delete': 'Αφαίρεση', 
        'cancel_transfer': 'Ακύρωση', 
        'add_later': 'Αργότερα',
      };
    } else {
      return {
        'app_title': 'Apiary Monitor', 
        'online': 'Online', 
        'transport_radio_muted': 'Transport Mode (Muted)',
        'inspection_mode': 'Inspection Mode', 
        'inspection_active': 'Inspection Active', 
        'inspection_sub_off': 'Mutes theft/movement alarms', 
        'inspection_sub_on': 'Alarms muted',
        'total_weight': 'TOTAL HIVE WEIGHT', 
        'overall': 'overall', 
        'ext_temp': 'Ext. Temp', 
        'humidity': 'Humidity', 
        'battery': 'Battery', 
        'signal': 'Cellular',
        'curve_title': 'Weight Curve', 
        'window': 'window', 
        'gps_location': 'Apiary Location', 
        'start_transport': 'Start Transport',
        'stop_transport': 'End Transport', 
        'request_reading': 'Request Scale Reading', 
        'syncing': 'Syncing...', 
        'archives_header': 'YEARLY HARVEST ARCHIVES',
        'weight_after_transfer': 'Weight since last transfer',
        'season': 'Season', 
        'rename_location': 'Rename Apiary Location', 
        'rename_hive': 'Rename Hive', 
        'post_transport_title': 'Transport Completed 🐝',
        'post_transport_desc': 'Transport period ended. Enter destination apiary name:', 
        'add_hive': 'Add New Hive', 
        'hives_list': 'MY HIVES',
        'hive_notes': 'Hive Notes', 
        'google_maps_open': 'Google Maps',
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
        'settings': 'Settings', 
        'logout': 'Log Out',
        'delete_hive': 'Unlink Hive', 
        'delete_confirm': 'The scale will be unlinked from your account. Are you sure?', 
        'delete': 'Unlink', 
        'cancel_transfer': 'Cancel', 
        'add_later': 'Later',
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
      case 1: return const Color(0xFF22C55E); 
      case 2: return const Color(0xFF3B82F6); 
      case 3: return const Color(0xFFEAB308); 
      case 4: return const Color(0xFFF97316); 
      case 5: return const Color(0xFFEF4444); 
      default: return const Color(0xFFEAB308);
    }
  }

  String _getFireCategoryTitle(int category) {
    if (widget.currentLanguage == 'el') {
      switch (category) { 
        case 1: return 'Κατηγ. 1 (Χαμηλή)'; 
        case 2: return 'Κατηγ. 2 (Μέση)'; 
        case 3: return 'Κατηγ. 3 (Υψηλή)'; 
        case 4: return 'Κατηγ. 4 (Πολύ Υψηλή)'; 
        case 5: return 'Κατηγ. 5 (Συναγερμός)'; 
        default: return 'Κατηγ. 3 (Υψηλή)'; 
      }
    } else {
      switch (category) { 
        case 1: return 'Cat. 1 (Low)'; 
        case 2: return 'Cat. 2 (Mod)'; 
        case 3: return 'Cat. 3 (High)'; 
        case 4: return 'Cat. 4 (Very High)'; 
        case 5: return 'Cat. 5 (Extreme)'; 
        default: return 'Cat. 3 (High)'; 
      }
    }
  }

  String _getSignalText(int dbm) {
    final hive = activeHive;
    if (hive != null && hive.isTransportMode) return widget.currentLanguage == 'el' ? 'Σε Αναμονή' : 'Standby';
    bool isGreek = widget.currentLanguage == 'el';
    if (dbm >= -70) return isGreek ? 'Εξαιρετικό' : 'Excellent';
    if (dbm >= -85) return isGreek ? 'Ισχυρό' : 'Strong';
    if (dbm >= -100) return isGreek ? 'Καλό' : 'Good';
    if (dbm >= -110) return isGreek ? 'Αδύναμο' : 'Weak';
    return isGreek ? 'Πολύ Αδύναμο' : 'Very Weak';
  }

  Color _getSignalColor(int dbm) {
    final hive = activeHive;
    if (hive != null && hive.isTransportMode) return const Color(0xFF64748B);
    if (dbm >= -70) return const Color(0xFF16A34A);
    if (dbm >= -85) return const Color(0xFF0D9488);
    if (dbm >= -100) return const Color(0xFF0284C7);
    if (dbm >= -110) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  void _showAddNoteDialog({HiveNote? existingNote}) {
    final controller = TextEditingController(text: existingNote?.text ?? '');
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
                  const Icon(Icons.edit_note, color: Color(0xFFD97706), size: 26),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t['add_note']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  if (existingNote != null)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          activeHive!.notes.remove(existingNote);
                        });
                        _syncHiveToCloud(activeHive!);
                        Navigator.pop(context);
                      },
                    )
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
                        lastDate: DateTime(2035)
                      );
                      if (picked != null) setDialogState(() => selectedNoteDate = picked);
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
                              const Icon(Icons.calendar_month, size: 20, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Text(
                                existingNote != null ? existingNote.date : _formatDateString(selectedNoteDate), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
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
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'π.χ. Προσθήκη πατώματος...', 
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey), 
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706), 
                    foregroundColor: Colors.white, 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty && activeHive != null) {
                      setState(() {
                        if (existingNote != null) {
                          existingNote.text = controller.text.trim();
                        } else {
                          activeHive!.notes.insert(0, HiveNote(date: _formatDateString(selectedNoteDate), text: controller.text.trim()));
                        }
                      });
                      _syncHiveToCloud(activeHive!);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(t['save']!, style: const TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRenameDialog() {
    if (activeHive == null) return;
    final controller = TextEditingController(text: activeHive!.apiaryName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['rename_location']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          content: TextField(
            controller: controller, 
            autofocus: true, 
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: widget.currentLanguage == 'el' ? 'Όνομα Μελισσοκομείου' : 'Apiary Name', 
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey, fontSize: 16))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white), 
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty && activeHive != null) {
                  setState(() => activeHive!.apiaryName = trimmed);
                  _syncHiveToCloud(activeHive!);
                }
                Navigator.pop(context);
              }, 
              child: Text(t['save']!, style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameHiveDialog(HiveData targetHive) {
    final controller = TextEditingController(text: targetHive.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['rename_hive']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          content: TextField(
            controller: controller, 
            autofocus: true, 
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: widget.currentLanguage == 'el' ? 'Όνομα Κυψέλης / Ζυγαριάς' : 'Hive / Scale Name', 
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey, fontSize: 16))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white), 
              onPressed: () async {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  try { 
                    await supabase.from('hives').update({'hive_name': trimmed}).eq('hive_id', targetHive.id); 
                    await _loadUserHives(); 
                  } catch (_) {}
                }
                if (mounted) Navigator.pop(context);
              }, 
              child: Text(t['save']!, style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteHive(HiveData targetHive) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['delete_hive']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            widget.currentLanguage == 'el' 
              ? 'Η ζυγαριά θα αφαιρεθεί από τον λογαριασμό σας. Το ιστορικό της θα παραμείνει αποθηκευμένο. Είστε σίγουροι;' 
              : 'The scale will be unlinked from your account. Its history will remain saved. Are you sure?', 
            style: const TextStyle(fontSize: 16)
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel']!, style: const TextStyle(color: Colors.grey, fontSize: 16))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), 
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => isLoadingHives = true);
                try { 
                  // Reset owner to null
                  await supabase.from('hives').update({
                    'owner_id': null,
                    'is_theft_alert_triggered': false
                  }).eq('hive_id', targetHive.id); 
                  await _loadUserHives(); 
                } catch (e) { 
                  if (mounted) setState(() => isLoadingHives = false); 
                }
              }, 
              child: Text(t['delete']!, style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _showPostTransportNameDialog() {
    if (activeHive == null) return;
    final controller = TextEditingController(text: 'Μελισσοκομείο ${activeHive!.regionDescription}');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.hive, color: Color(0xFFD97706), size: 26),
              const SizedBox(width: 8),
              Expanded(child: Text(t['post_transport_title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t['post_transport_desc']!, style: const TextStyle(fontSize: 15, color: Colors.grey)),
              const SizedBox(height: 14),
              TextField(
                controller: controller, 
                autofocus: true, 
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: widget.currentLanguage == 'el' ? 'Όνομα Νέου Μελισσοκομείου' : 'New Apiary Name', 
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
            ],
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() { 
                      activeHive!.isTransportMode = false; 
                      activeHive!.transportStartTime = null; 
                    });
                    _syncHiveToCloud(activeHive!);
                    Navigator.pop(context);
                  },
                  child: Text(t['cancel_transfer']!, style: const TextStyle(color: Colors.red, fontSize: 16)),
                ),
                TextButton(
                  onPressed: () { 
                    _finalizeStay(activeHive!.apiaryName);
                    Navigator.pop(context); 
                  }, 
                  child: Text(t['add_later']!, style: const TextStyle(fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white), 
                  onPressed: () {
                    final chosenName = controller.text.trim();
                    Navigator.pop(context);
                    final finalName = chosenName.isNotEmpty ? chosenName : "Μελισσοκομείο ${activeHive!.regionDescription}";
                    _finalizeStay(finalName);
                  }, 
                  child: Text(t['save']!, style: const TextStyle(fontSize: 16)),
                ),
              ],
            )
          ],
        );
      },
    );
  }

  void _finalizeStay(String newApiaryName) {
    if (activeHive == null) return;
    final double netGain = activeHive!.currentWeight - activeHive!.baselineWeight;
    final currentYear = activeHive!.sitePlacedDate.year.toString();
    final int days = DateTime.now().difference(activeHive!.sitePlacedDate).inDays.clamp(1, 999);

    final archiveRecord = {
      "apiary": activeHive!.apiaryName,
      "locationRegion": activeHive!.regionDescription,
      "startDate": "${activeHive!.sitePlacedDate.day}/${activeHive!.sitePlacedDate.month}/${activeHive!.sitePlacedDate.year}",
      "endDate": "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
      "durationDays": days,
      "initialWeight": activeHive!.baselineWeight,
      "finalWeight": activeHive!.currentWeight,
      "totalGain": netGain,
      "dailyAvgGain": netGain / days,
      "history": List<Map<String, dynamic>>.from(activeHive!.locationHistory),
    };

    setState(() {
      activeHive!.isTransportMode = false;
      activeHive!.transportStartTime = null;
      if (!activeHive!.archivedYears.containsKey(currentYear)) {
        activeHive!.archivedYears[currentYear] = [];
      }
      activeHive!.archivedYears[currentYear]!.insert(0, archiveRecord);
      activeHive!.apiaryName = newApiaryName;
      activeHive!.sitePlacedDate = DateTime.now();
      activeHive!.baselineWeight = activeHive!.currentWeight;
      activeHive!.locationHistory = [
        {"day": widget.currentLanguage == 'el' ? "1η Ημέρα (Άφιξη)" : "Day 1 (Arrival)", "weight": activeHive!.currentWeight, "gain": "+0.00 kg"}
      ];
    });
    
    _syncHiveToCloud(activeHive!);
  }

  void _showArchiveDetailsDialog(Map<String, dynamic> st) {
    List<double> archWeights = [];
    if (st['history'] != null) {
      archWeights = (st['history'] as List).map((e) => (e['weight'] as num).toDouble()).toList();
    }
    if (archWeights.isEmpty) {
      archWeights = [(st['initialWeight'] as num).toDouble(), (st['finalWeight'] as num).toDouble()];
    }
    if (archWeights.length == 1) {
      archWeights.add(archWeights[0]); 
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.history, color: Color(0xFFD97706), size: 26),
              const SizedBox(width: 8),
              Expanded(child: Text(st['apiary'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📍 Τοποθεσία: ${st['locationRegion']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const Divider(),
                Text('📅 Από: ${st['startDate']}', style: const TextStyle(fontSize: 16)),
                Text('📅 Έως: ${st['endDate']}', style: const TextStyle(fontSize: 16)),
                Text('⏳ Διάρκεια: ${st['durationDays']} ημέρες', style: const TextStyle(fontSize: 16)),
                const Divider(),
                Text('⚖️ Αρχικό Βάρος: ${(st['initialWeight'] as num).toDouble().toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 16)),
                Text('⚖️ Τελικό Βάρος: ${(st['finalWeight'] as num).toDouble().toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                
                Container(
                  height: 100,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300)
                  ),
                  child: CustomPaint(
                    painter: WeightChartPainter(
                      data: archWeights,
                      visibleHours: archWeights.length.toDouble(), 
                      scrollOffset: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Συνολική Αύξηση: +${(st['totalGain'] as num).toDouble().toStringAsFixed(1)} kg 🍯', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Μέση Ημερήσια: +${(st['dailyAvgGain'] as num).toDouble().toStringAsFixed(3)} kg/day', style: const TextStyle(fontSize: 14, color: Color(0xFF92400E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  for (var year in activeHive!.archivedYears.keys) {
                    activeHive!.archivedYears[year]?.remove(st);
                  }
                });
                _syncHiveToCloud(activeHive!);
                Navigator.pop(ctx);
              }, 
              child: Text(t['delete']!, style: const TextStyle(fontSize: 16, color: Colors.redAccent))
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(fontSize: 16))),
          ],
        );
      }
    );
  }

  void _showOverallHistoryDialog(HiveData hive) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t['weight_after_transfer']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Container(
                  height: 130,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: CustomPaint(
                    painter: WeightChartPainter(
                      data: hive.hourlyWeights48h,
                      visibleHours: 48,
                      scrollOffset: 0,
                    ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: hive.locationHistory.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final loc = hive.locationHistory[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                loc['day'] ?? '', 
                                overflow: TextOverflow.ellipsis, 
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${loc['weight']} kg (${loc['gain']})', 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text('OK', style: TextStyle(fontSize: 16)),
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

  Widget _buildFireRiskHalf({required String dayLabel, required String dateStr, required int category}) {
    bool isRestricted = category >= 4;
    Color statusColor = _getFireCategoryColor(category);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isRestricted ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isRestricted ? const Color(0xFFEF4444) : const Color(0xFF86EFAC), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      dayLabel, 
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: isRestricted ? const Color(0xFF991B1B) : const Color(0xFF166534), letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($dateStr)', 
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isRestricted ? const Color(0xFF7F1D1D) : const Color(0xFF14532D)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    _getFireCategoryTitle(category), 
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(isRestricted ? Icons.local_fire_department : Icons.verified_user, color: isRestricted ? const Color(0xFFDC2626) : const Color(0xFF16A34A), size: 17),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isRestricted ? t['warning_short']! : t['allowed_short']!, 
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: isRestricted ? const Color(0xFF991B1B) : const Color(0xFF166534)), 
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isRestricted ? t['warning_sub_short']! : t['allowed_sub_short']!, 
              style: TextStyle(fontSize: 11.5, color: isRestricted ? const Color(0xFFB91C1C) : const Color(0xFF15803D)), 
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
    if (isLoadingHives) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFD97706))));

    if (hives.isEmpty || activeHive == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t['app_title']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 19)),
          backgroundColor: const Color(0xFFD97706),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => SettingsScreen(
                    currentLanguage: widget.currentLanguage, 
                    onLanguageChanged: widget.onLanguageChanged, 
                    isWeightGainNotificationEnabled: widget.isWeightGainNotificationEnabled,
                    onWeightGainNotificationToggled: widget.onWeightGainNotificationToggled,
                    isSwarmingNotificationEnabled: widget.isSwarmingNotificationEnabled,
                    onSwarmingNotificationToggled: widget.onSwarmingNotificationToggled,
                    telemetryIntervalMinutes: widget.telemetryIntervalMinutes, 
                    inspectionTimerMinutes: widget.inspectionTimerMinutes, 
                    transportTimerHours: widget.transportTimerHours, 
                    onSettingsChanged: widget.onSettingsChanged,
                  )
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut())
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.scale, size: 64, color: Color(0xFFD97706)),
              const SizedBox(height: 12),
              Text(
                widget.currentLanguage == 'el' ? 'Δεν βρέθηκε συνδεδεμένη ζυγαριά.' : 'No scales registered yet.', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706), 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.add_link),
                label: Text(widget.currentLanguage == 'el' ? 'Σύνδεση Πρώτης Ζυγαριάς' : 'Pair First Scale', style: const TextStyle(fontSize: 16)),
                onPressed: _showFirstTimeScaleSyncDialog,
              )
            ],
          ),
        ),
      );
    }

    final hive = activeHive!;
    final double netGain = hive.currentWeight - hive.baselineWeight;
    final isEl = widget.currentLanguage == 'el';
    
    // OFFLINE / TAMPER CHECK
    bool isOffline = false;
    bool isOfflineDismissed = false;
    if (hive.lastTelemetryTime != null) {
      int minutesSinceLast = DateTime.now().difference(hive.lastTelemetryTime!).inMinutes;
      if (minutesSinceLast > (widget.telemetryIntervalMinutes + 15)) {
        String? deletedTimestamp = _prefs?.getString('deleted_${hive.id}');
        if (deletedTimestamp != hive.lastTelemetryTime.toString()) {
          isOffline = true;
          String? dismissedTimestamp = _prefs?.getString('dismissed_${hive.id}');
          if (dismissedTimestamp == hive.lastTelemetryTime.toString()) {
            isOfflineDismissed = true;
          }
        }
      }
    }

    // DRAWER NOTIFICATION HISTORY LIST
    List<Widget> drawerAlertWidgets = [];

    // 1. Add Active Theft Alerts
    for (var h in hives) {
      if (h.isTheftAlertTriggered) {
        drawerAlertWidgets.add(
          ListTile(
            dense: true,
            leading: const Icon(Icons.warning, color: Colors.redAccent),
            title: Text(isEl ? '🚨 Συναγερμός: ${h.name}' : '🚨 Theft Alarm: ${h.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            subtitle: Text(isEl ? 'Ανιχνεύθηκε κραδασμός & απότομη πτώση βάρους' : 'Vibration & weight drop detected'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  child: Text(isEl ? 'Χάρτης' : 'Map', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (c) => MapTrackingScreen(hive: h)));
                  },
                ),
              ],
            ),
          ),
        );
      }
    }

    // 2. Add Saved FCM/Theft Alert Logs
    final loggedAlerts = _prefs?.getStringList('alerts_history_log') ?? [];
    for (var log in loggedAlerts) {
      try {
        final Map<String, dynamic> item = jsonDecode(log);
        final date = DateTime.tryParse(item['date'] ?? '') ?? DateTime.now();
        final isTheftItem = item['isTheft'] == true;

        drawerAlertWidgets.add(
          ListTile(
            dense: true,
            leading: Icon(isTheftItem ? Icons.warning_amber_rounded : Icons.info_outline, color: isTheftItem ? Colors.red : Colors.blue),
            title: Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item['body'] ?? ''}\n${_formatDateString(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () async {
                bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(isEl ? 'Επιβεβαίωση Διαγραφής' : 'Confirm Deletion'),
                    content: Text(isEl ? 'Θέλετε να διαγράψετε αυτή την ειδοποίηση από το ιστορικό;' : 'Delete this alert from history?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isEl ? 'Ακύρωση' : 'Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true), 
                        child: Text(isEl ? 'Διαγραφή' : 'Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  loggedAlerts.remove(log);
                  await _prefs?.setStringList('alerts_history_log', loggedAlerts);
                  setState(() {});
                }
              },
            ),
          ),
        );
      } catch (_) {}
    }

    // 3. Add Offline/Connection Lost Warnings
    for (var h in hives) {
      if (h.lastTelemetryTime != null) {
        int mins = DateTime.now().difference(h.lastTelemetryTime!).inMinutes;
        if (mins > (widget.telemetryIntervalMinutes + 15)) {
          String? deletedTimestamp = _prefs?.getString('deleted_${h.id}');
          if (deletedTimestamp != h.lastTelemetryTime.toString()) {
            String? dis = _prefs?.getString('dismissed_${h.id}');
            if (dis == h.lastTelemetryTime.toString()) {
              drawerAlertWidgets.add(
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.wifi_off, color: Colors.orange),
                  title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isEl ? 'Απώλεια Σήματος: ${_formatDateString(h.lastTelemetryTime!)}' : 'Signal Lost: ${_formatDateString(h.lastTelemetryTime!)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        child: Text(isEl ? 'Επαναφορά' : 'Restore', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          _prefs?.remove('dismissed_${h.id}');
                          setState((){});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(isEl ? 'Επιβεβαίωση' : 'Confirm'),
                              content: Text(isEl ? 'Διαγραφή ειδοποίησης από το ιστορικό;' : 'Delete alert from history?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isEl ? 'Ακύρωση' : 'Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isEl ? 'Διαγραφή' : 'Delete', style: const TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            _prefs?.setString('deleted_${h.id}', h.lastTelemetryTime.toString());
                            setState((){});
                          }
                        },
                      )
                    ],
                  ),
                )
              );
            }
          }
        }
      }
    }

    // 24h Trend Calculation
    int index24h = math.max(0, hive.hourlyWeights48h.length - 25);
    double weight24hAgo = hive.hourlyWeights48h.isNotEmpty ? hive.hourlyWeights48h[index24h] : hive.currentWeight;
    double weightDiff24h = hive.currentWeight - weight24hAgo;

    // Dynamic Zoom & Pan Logic
    int totalPoints = hive.hourlyWeights48h.length;
    int count = _visibleHours.round().clamp(2, totalPoints);
    double maxOffset = math.max(0, totalPoints - count).toDouble();
    _scrollOffset = _scrollOffset.clamp(0.0, maxOffset);

    int startIndex = (totalPoints - count - _scrollOffset).floor();
    if (startIndex < 0) startIndex = 0;
    int endIndex = math.min(totalPoints, startIndex + count);
    List<double> displayedPoints = hive.hourlyWeights48h.sublist(startIndex, endIndex);

    String todayDateStr = hive.weatherForecast.isNotEmpty ? hive.weatherForecast[0].dateStr : '';
    String tomDateStr = hive.weatherForecast.length > 1 ? hive.weatherForecast[1].dateStr : '';

    final now = DateTime.now();
    final bool isFireSeason = now.month >= 5 && now.month <= 10;
    final bool showTomorrowFireRisk = now.hour >= 14;

    final user = supabase.auth.currentUser;
    final displayName = user?.userMetadata?['display_name'] ?? user?.email ?? '';

    String offlineBannerStr = '';
    if (hive.lastTelemetryTime != null) {
      final hr = hive.lastTelemetryTime!.hour.toString().padLeft(2, '0');
      final min = hive.lastTelemetryTime!.minute.toString().padLeft(2, '0');
      offlineBannerStr = isEl ? 'Τελευταία ενημέρωση: $hr:$min' : 'Last update: $hr:$min';
    }

    return Scaffold(
      backgroundColor: _blinkRed ? Colors.red.shade800 : const Color(0xFFF1F5F9), 
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.account_circle, color: Colors.white, size: 40),
                        const SizedBox(height: 8),
                        Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['hives_list']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Color(0xFFD97706), size: 24), 
                          onPressed: () { 
                            Navigator.pop(context); 
                            _showFirstTimeScaleSyncDialog(); 
                          },
                        )
                      ],
                    ),
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: hives.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = hives.removeAt(oldIndex);
                        hives.insert(newIndex, item);
                        if (selectedHiveIndex == oldIndex) {
                          selectedHiveIndex = newIndex;
                        } else if (selectedHiveIndex > oldIndex && selectedHiveIndex <= newIndex) {
                          selectedHiveIndex--;
                        } else if (selectedHiveIndex < oldIndex && selectedHiveIndex >= newIndex) {
                          selectedHiveIndex++;
                        }
                      });
                    },
                    itemBuilder: (context, idx) {
                      final h = hives[idx];
                      final isSelected = idx == selectedHiveIndex;
                      final isEditing = _activeDrawerEditHiveId == h.id;
                      
                      return ListTile(
                        key: ValueKey(h.id),
                        dense: true,
                        leading: Icon(Icons.hive, color: isSelected ? const Color(0xFFD97706) : Colors.grey, size: 24),
                        title: Text(
                          h.name, 
                          style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? const Color(0xFFD97706) : const Color(0xFF1E293B), fontSize: 16),
                        ),
                        trailing: isEditing
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 22), onPressed: () { setState(() => _activeDrawerEditHiveId = null); _showRenameHiveDialog(h); }),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22), onPressed: () { setState(() => _activeDrawerEditHiveId = null); _confirmDeleteHive(h); }),
                                IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 22), onPressed: () { setState(() => _activeDrawerEditHiveId = null); }),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${h.currentWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ReorderableDragStartListener(
                                  index: idx, 
                                  child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.drag_handle, color: Colors.grey, size: 24)),
                                ),
                              ],
                            ),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFFFEF3C7),
                        onLongPress: () {
                          setState(() {
                            _activeDrawerEditHiveId = isEditing ? null : h.id;
                          });
                        },
                        onTap: () {
                          if (isEditing) {
                            setState(() => _activeDrawerEditHiveId = null);
                          } else {
                            setState(() => selectedHiveIndex = idx);
                            _fetchLiveOnlineData();
                            _fetchSupabaseTelemetry();
                            Navigator.pop(context);
                          }
                        },
                      );
                    },
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4), 
                    child: Text(t['archives_header']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                  ),
                  ...hive.archivedYears.entries.map((entry) => ExpansionTile(
                        initiallyExpanded: false,
                        leading: const Icon(Icons.folder_zip, color: Color(0xFFD97706), size: 24),
                        title: Text('${t['season']} ${entry.key} (${entry.value.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        children: entry.value.map((st) => ListTile(
                          dense: true, 
                          title: Text(st['apiary'], style: const TextStyle(fontSize: 14)), 
                          trailing: Text('+${(st['totalGain'] as num).toDouble().toStringAsFixed(1)} kg 🍯', style: const TextStyle(fontSize: 14)),
                          onTap: () => _showArchiveDetailsDialog(st),
                        )).toList(),
                      )),
                  const Divider(),
                  
                  // NOTIFICATION HISTORY (DRAWER SECTION)
                  ExpansionTile(
                    initiallyExpanded: true,
                    leading: const Icon(Icons.notifications_active, color: Colors.redAccent, size: 24),
                    title: Text(
                      isEl ? 'Ιστορικό Ειδοποιήσεων' : 'Alerts History', 
                      style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    children: drawerAlertWidgets.isEmpty 
                        ? [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                isEl ? 'Καμία ενεργή ειδοποίηση στο ιστορικό.' : 'No active dismissed alerts.',
                                style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                            )
                          ]
                        : drawerAlertWidgets,
                  ),
                  const Divider(),
                  
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF1E293B), size: 24),
                    title: Text(t['settings']!, style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => SettingsScreen(
                            currentLanguage: widget.currentLanguage, 
                            onLanguageChanged: widget.onLanguageChanged, 
                            isWeightGainNotificationEnabled: widget.isWeightGainNotificationEnabled,
                            onWeightGainNotificationToggled: widget.onWeightGainNotificationToggled,
                            isSwarmingNotificationEnabled: widget.isSwarmingNotificationEnabled,
                            onSwarmingNotificationToggled: widget.onSwarmingNotificationToggled,
                            telemetryIntervalMinutes: widget.telemetryIntervalMinutes, 
                            inspectionTimerMinutes: widget.inspectionTimerMinutes, 
                            transportTimerHours: widget.transportTimerHours, 
                            onSettingsChanged: widget.onSettingsChanged,
                          )
                        ),
                      );
                    },
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
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 19), 
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFFD97706),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFD97706),
        onRefresh: () async {
          setState(() => isSyncing = true);
          await _syncHiveToCloud(hive);
          await _fetchLiveOnlineData();
          await _fetchSupabaseTelemetry();
          setState(() => isSyncing = false);
        },
        child: Center(
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
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), 
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_note, size: 20, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: hive.isTransportMode ? const Color(0xFFF1F5F9) : const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 9, color: hive.isTransportMode ? const Color(0xFF64748B) : const Color(0xFF16A34A)),
                          const SizedBox(width: 4),
                          Text(
                            hive.isTransportMode ? t['transport_radio_muted']! : t['online']!, 
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hive.isTransportMode ? const Color(0xFF475569) : const Color(0xFF16A34A)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                
                // THEFT ALARM BANNER
                if (hive.isTheftAlertTriggered)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D), 
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.white, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.currentLanguage == 'el' ? '🚨 ΣΥΝΑΓΕΡΜΟΣ ΚΛΟΠΗΣ!' : '🚨 THEFT ALARM TRIGGERED!', 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.currentLanguage == 'el' 
                              ? 'Ανιχνεύθηκε απότομη πτώση βάρους & κραδασμοί. Αν είστε εσείς, απενεργοποιήστε τον συναγερμό παρακάτω.'
                              : 'Sudden weight drop & vibrations detected. If this is you, deactivate the alarm below.',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black87,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.radar, size: 20),
                                label: const Text('Track Down', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () async {
                                  await _silenceSirenOnly(); 
                                  if (context.mounted) {
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (context) => MapTrackingScreen(hive: hive)
                                    ));
                                  }
                                }, 
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF7F1D1D),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                                label: Text(widget.currentLanguage == 'el' ? 'Λήξη Alarm' : 'Deactivate', style: const TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () async {
                                  await _silenceSirenOnly();

                                  if (!context.mounted) return;
                                  
                                  bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(widget.currentLanguage == 'el' ? 'Επιβεβαίωση' : 'Confirm'),
                                      content: Text(widget.currentLanguage == 'el' 
                                        ? 'Θέλετε σίγουρα να κλείσετε τον συναγερμό και να απενεργοποιηθεί η ειδοποίηση;' 
                                        : 'Are you sure you want to deactivate this alarm?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: Text(widget.currentLanguage == 'el' ? 'Ακύρωση' : 'Cancel'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text(widget.currentLanguage == 'el' ? 'Λήξη' : 'Dismiss'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    _dismissAlert(hive);
                                  }
                                }, 
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.currentLanguage == 'el' ? '* Όσο δεν απενεργοποιείται, γίνεται καταγραφή GPS κάθε 2 λεπτά' : '* Until deactivated, GPS is tracked every 2 mins',
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),

                // OFFLINE / TAMPER WARNING BANNER
                if (isOffline && !isOfflineDismissed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDC2626))),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.currentLanguage == 'el' ? 'Απώλεια Σήματος / Πιθανή Βλάβη' : 'Connection Lost / Possible Fault', 
                                    style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    offlineBannerStr,
                                    style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                _prefs?.setString('dismissed_${hive.id}', hive.lastTelemetryTime.toString());
                                setState(() {});
                              }, 
                              child: Text(widget.currentLanguage == 'el' ? 'Απόκρυψη' : 'Dismiss', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                              onPressed: () {
                                showDialog(
                                  context: context, 
                                  builder: (ctx) => AlertDialog(
                                    title: Text(widget.currentLanguage == 'el' ? 'Στοιχεία Τελευταίου Σήματος' : 'Last Known Location', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Lat: ${hive.latitude}\nLon: ${hive.longitude}', style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                                        const SizedBox(height: 10),
                                        Text(widget.currentLanguage == 'el' ? 'Η ζυγαριά ίσως έχασε το ρεύμα (κομμένο καλώδιο) ή βρίσκεται εκτός εμβέλειας δικτύου.' : 'Scale may have lost power (cut wire) or exited network range.', style: const TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.map, size: 16),
                                        label: const Text('Map'),
                                        onPressed: () async {
                                          final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${hive.latitude},${hive.longitude}');
                                          if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                                        }
                                      )
                                    ],
                                  )
                                );
                              }, 
                              icon: const Icon(Icons.search, size: 16),
                              label: Text(widget.currentLanguage == 'el' ? 'Έλεγχος' : 'Investigate', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

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
                      Icon(hive.isInspectionMode ? Icons.build_circle : Icons.shield, color: hive.isInspectionMode ? const Color(0xFFB45309) : const Color(0xFF64748B), size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hive.isInspectionMode ? t['inspection_active']! : t['inspection_mode']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: hive.isInspectionMode ? const Color(0xFF92400E) : const Color(0xFF1E293B))),
                            Text(hive.isInspectionMode ? t['inspection_sub_on']! : t['inspection_sub_off']!, style: TextStyle(fontSize: 13, color: hive.isInspectionMode ? const Color(0xFFB45309) : Colors.grey)),
                          ],
                        ),
                      ),
                      if (hive.isInspectionMode)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFB45309), borderRadius: BorderRadius.circular(6)),
                          child: Text(_formatTimer(hive.inspectionRemaining), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                        ),
                      Switch(
                        value: hive.isInspectionMode,
                        activeColor: const Color(0xFFD97706),
                        onChanged: (v) => setState(() {
                          if (v) {
                            hive.isInspectionMode = true;
                            hive.inspectionRemaining = widget.inspectionTimerMinutes * 60;
                            hive.preInspectionWeight = hive.currentWeight; 
                          } else {
                            hive.isInspectionMode = false;
                            double diff = hive.currentWeight - hive.preInspectionWeight;
                            hive.baselineWeight += diff;
                          }
                          _syncHiveToCloud(hive);
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
                          Text(t['total_weight']!, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                          Row(
                            children: [
                              Icon(weightDiff24h >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: weightDiff24h >= 0 ? Colors.greenAccent : Colors.redAccent, size: 18),
                              const SizedBox(width: 4),
                              Text('${weightDiff24h > 0 ? '+' : ''}${weightDiff24h.toStringAsFixed(1)} kg (24h)', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(hive.currentWeight.toStringAsFixed(2), style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(width: 6),
                          const Text('kg', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white70)),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => _showOverallHistoryDialog(hive),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.22), borderRadius: BorderRadius.circular(12)),
                            child: Text('${netGain >= 0 ? '+' : ''}🍯 ${netGain.toStringAsFixed(1)} kg ${t['overall']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4-Metric Compact Row
                Row(
                  children: [
                    Expanded(child: _compactTile(t['ext_temp']!, '${hive.outdoorTemp.toStringAsFixed(1)}°C', Icons.wb_sunny_outlined, Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(child: _compactTile(t['humidity']!, '${hive.outdoorHumidity.toStringAsFixed(0)}%', Icons.water_drop_outlined, Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _compactTile(t['battery']!, '${hive.batteryPct}%', Icons.battery_charging_full, Colors.green)),
                    const SizedBox(width: 8),
                    Expanded(child: _compactTile(t['signal']!, _getSignalText(hive.signalDbm), Icons.signal_cellular_alt, _getSignalColor(hive.signalDbm))),
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
                          Text(t['curve_title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${_visibleHours.toInt()}h ${t['window']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onScaleStart: (_) => _baseScaleVisibleHours = _visibleHours,
                        onScaleUpdate: (d) {
                          setState(() {
                            if (d.scale != 1.0) _visibleHours = (_baseScaleVisibleHours / d.scale).clamp(6.0, 48.0);
                            if (d.focalPointDelta.dx != 0) {
                              _scrollOffset = (_scrollOffset - (d.focalPointDelta.dx / 280) * _visibleHours).clamp(0.0, maxOffset);
                            }
                          });
                        },
                        onLongPressStart: (d) => setState(() => _crosshairX = d.localPosition.dx),
                        onLongPressMoveUpdate: (d) => setState(() => _crosshairX = d.localPosition.dx),
                        onLongPressEnd: (d) => setState(() => _crosshairX = null),
                        child: Container(
                          height: 190, 
                          width: double.infinity,
                          color: Colors.transparent,
                          child: CustomPaint(
                            painter: WeightChartPainter(
                              data: displayedPoints, 
                              crosshairX: _crosshairX,
                              visibleHours: _visibleHours,
                              scrollOffset: _scrollOffset,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 📝 NOTES SECTION
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
                              const Icon(Icons.sticky_note_2_outlined, color: Color(0xFFD97706), size: 22),
                              const SizedBox(width: 6),
                              Text(
                                t['hive_notes']!,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _showAddNoteDialog(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                t['add_note']!,
                                style: const TextStyle(color: Color(0xFF92400E), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hive.notes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Δεν υπάρχουν καταγεγραμμένες σημειώσεις.', style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic)),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: hive.notes.length > 3 ? 3 : hive.notes.length,
                          separatorBuilder: (context, index) => const Divider(height: 12, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, index) {
                            final note = hive.notes[index];
                            return InkWell(
                              onTap: () => _showAddNoteDialog(existingNote: note),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                                    child: Text(note.date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(note.text, style: const TextStyle(fontSize: 14, color: Color(0xFF334155)))),
                                  const Icon(Icons.edit, size: 16, color: Colors.grey),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 🚒 SPLIT FIRE HAZARD WIDGET
                if (isFireSeason) ...[
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
                                const Icon(Icons.local_fire_department, size: 18, color: Color(0xFFD97706)),
                                const SizedBox(width: 5),
                                Text(t['fire_risk_header']!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEFF6FF),
                                foregroundColor: const Color(0xFF1D4ED8),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('ΓΓΠΠ', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final url = Uri.parse('https://civilprotection.gov.gr/arxeio-imerision-xartwn');
                                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildFireRiskHalf(dayLabel: t['today']!, dateStr: todayDateStr, category: hive.fireRiskCategoryToday),
                            if (showTomorrowFireRisk) ...[
                              const SizedBox(width: 8),
                              _buildFireRiskHalf(dayLabel: t['tomorrow']!, dateStr: tomDateStr, category: hive.fireRiskCategoryTomorrow),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 🌤️ 5-DAY WEATHER FORECAST
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
                              const Icon(Icons.wb_sunny_outlined, size: 20, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(t['weather_forecast']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                            ],
                          ),
                          const Text('Open-Meteo Live 🛰️', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: hive.weatherForecast.map((day) {
                          bool isHighWind = day.maxWindSpeedKmH >= 30.0;
                          bool isRainRisk = day.rainProbability >= 65 || (day.weatherCode >= 51 && day.weatherCode <= 67) || (day.weatherCode >= 80 && day.weatherCode <= 82);

                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                              decoration: BoxDecoration(
                                color: isHighWind ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isHighWind ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0), width: isHighWind ? 1.4 : 1.0),
                              ),
                              child: Stack(
                                children: [
                                  if (isRainRisk)
                                    const Positioned(top: 0, right: 2, child: Icon(Icons.beach_access, size: 16, color: Color(0xFF2563EB))),
                                  Column(
                                    children: [
                                      Text(day.dayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                      Text(day.dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Icon(_getWeatherIcon(day.weatherCode), size: 20, color: const Color(0xFFD97706)),
                                      const SizedBox(height: 4),
                                      Text('${day.maxTemp.round()}° / ${day.minTemp.round()}°', style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          if (isHighWind)
                                            SizedBox(width: 15, height: 11, child: CustomPaint(painter: WindsockPainter(isAlert: true)))
                                          else
                                            const SizedBox(width: 15, height: 11),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.water_drop, size: 11, color: Color(0xFF3B82F6)),
                                              Text('${day.maxHumidity}%', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                            ],
                                          ),
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

                // INTERACTIVE MAPS & LOCATION
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
                              const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 4),
                              Text(t['gps_location']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                            ],
                          ),
                          InkWell(
                            onTap: () async {
                              final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${hive.latitude},${hive.longitude}');
                              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.map, size: 16, color: Colors.blueAccent),
                                const SizedBox(width: 4),
                                Text(t['google_maps_open']!, style: const TextStyle(fontSize: 13, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
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
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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

                // TRANSPORT MODE
                if (hive.isTransportMode)
                  ElevatedButton.icon(
                    onPressed: _showPostTransportNameDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t['stop_transport']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
                          child: Text(_formatTimer(hive.transportRemaining), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  )
                else if (!_showTransportSlider)
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showTransportSlider = true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      backgroundColor: const Color(0xFFD97706),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.local_shipping, color: Colors.white),
                    label: Text(t['start_transport']!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                  )
                else
                  SlideToStartTransport(
                    label: t['start_transport']!,
                    onTriggered: () {
                      setState(() {
                        hive.isTransportMode = true;
                        hive.transportStartTime = DateTime.now();
                        hive.transportRemaining = widget.transportTimerHours * 3600;
                        _showTransportSlider = false;
                      });
                      _syncHiveToCloud(hive);
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color == Colors.orange || color == Colors.blue || color == Colors.green ? const Color(0xFF1E293B) : color), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ==========================================
// CUSTOM SLIDE TO ACTIVATE WIDGET
// ==========================================
class SlideToStartTransport extends StatefulWidget {
  final String label;
  final VoidCallback onTriggered;
  const SlideToStartTransport({super.key, required this.label, required this.onTriggered});
  @override
  State<SlideToStartTransport> createState() => _SlideToStartTransportState();
}
class _SlideToStartTransportState extends State<SlideToStartTransport> {
  double _dragPosition = 0.0;
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - 56;
        return Container(
          height: 56,
          decoration: BoxDecoration(color: const Color(0xFFD97706).withOpacity(0.15), borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3))),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(child: Text('${widget.label} >>', style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.bold, fontSize: 16))),
              Positioned(
                left: _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_triggered) return;
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0) _dragPosition = 0;
                      if (_dragPosition >= maxDrag) {
                        _dragPosition = maxDrag;
                        _triggered = true;
                        widget.onTriggered();
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (!_triggered) setState(() => _dragPosition = 0.0);
                  },
                  child: Container(
                    width: 56, height: 56,
                    decoration: const BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle),
                    child: const Icon(Icons.local_shipping, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 5. DYNAMIC 48-HOUR CANVAS PAINTER 
// ==========================================
class WeightChartPainter extends CustomPainter {
  final List<double> data;
  final double? crosshairX;
  final double visibleHours;
  final double scrollOffset;

  WeightChartPainter({
    required this.data, 
    this.crosshairX,
    required this.visibleHours,
    required this.scrollOffset,
  });

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

    final double chartHeight = size.height - 25; 

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), gridPaint);
    canvas.drawLine(Offset(0, chartHeight / 2), Offset(size.width, chartHeight / 2), gridPaint);
    canvas.drawLine(Offset(0, chartHeight), Offset(size.width, chartHeight), gridPaint);

    void drawText(String text, double x, double y, {bool alignRight = false, bool alignCenter = false}) {
      final textSpan = TextSpan(text: text, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.bold));
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      
      double dx = x;
      if (alignRight) dx = x - textPainter.width;
      else if (alignCenter) dx = x - (textPainter.width / 2);
      
      textPainter.paint(canvas, Offset(dx, y));
    }

    drawText('${maxVal.toStringAsFixed(1)} kg', 4, 2);
    drawText('${minVal.toStringAsFixed(1)} kg', 4, chartHeight - 14);

    final linePaint = Paint()..color = const Color(0xFFD97706)..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..shader = LinearGradient(colors: [const Color(0xFFF59E0B).withOpacity(0.35), const Color(0xFFF59E0B).withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Rect.fromLTWH(0, 0, size.width, chartHeight))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = (data[i] - minVal) / (maxVal - minVal);
      final y = chartHeight - (normalizedY * (chartHeight - 10)) - 5;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, chartHeight);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final lastX = size.width;
    final lastNormalizedY = (data.last - minVal) / (maxVal - minVal);
    final lastY = chartHeight - (lastNormalizedY * (chartHeight - 10)) - 5;
    canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = const Color(0xFFB45309));

    // DYNAMIC X-AXIS
    double rightHour = scrollOffset; 
    double leftHour = scrollOffset + visibleHours;
    
    double interval = visibleHours <= 12 ? 3 : (visibleHours <= 24 ? 6 : 12);
    
    int firstTick = (rightHour / interval).ceil() * interval.toInt();
    for (int h = firstTick; h <= leftHour; h += interval.toInt()) {
      double x = size.width * (1.0 - (h - rightHour) / visibleHours);
      String label = h == 0 ? 'Τώρα' : '-${h}h';
      
      bool isRightEdge = h == 0;
      bool alignCenter = !isRightEdge;
      drawText(label, x, chartHeight + 8, alignRight: isRightEdge, alignCenter: alignCenter);
    }

    if (crosshairX != null && crosshairX! >= 0 && crosshairX! <= size.width && data.length > 1) {
      int index = (crosshairX! / stepX).round().clamp(0, data.length - 1);
      double snappedX = index * stepX;
      double val = data[index];
      double normalizedY = (val - minVal) / (maxVal - minVal);
      double snappedY = chartHeight - (normalizedY * (chartHeight - 10)) - 5;
      
      double pointHour = leftHour - (index / (data.length - 1)) * visibleHours;
      String timeLabel = pointHour <= 0.1 ? 'Τώρα' : '-${pointHour.toStringAsFixed(1)}h';

      canvas.drawLine(Offset(snappedX, 0), Offset(snappedX, chartHeight), Paint()..color = const Color(0xFF64748B)..strokeWidth = 1.5);
      canvas.drawCircle(Offset(snappedX, snappedY), 6, Paint()..color = const Color(0xFF2563EB));
      
      final tipTp = TextPainter(
        text: TextSpan(text: '${val.toStringAsFixed(1)} kg\n$timeLabel', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      
      double boxX = snappedX - (tipTp.width / 2) - 6;
      if (boxX < 0) boxX = 0;
      if (boxX + tipTp.width + 12 > size.width) boxX = size.width - tipTp.width - 12;

      canvas.drawRect(
        Rect.fromLTWH(boxX, snappedY - 38, tipTp.width + 12, tipTp.height + 8),
        Paint()..color = Colors.black87,
      );
      tipTp.paint(canvas, Offset(boxX + 6, snappedY - 34));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// WINDSOCK PAINTER
class WindsockPainter extends CustomPainter {
  final bool isAlert;
  WindsockPainter({this.isAlert = false});

  @override
  void paint(Canvas canvas, Size size) {
    final orange = Paint()..color = (isAlert ? const Color(0xFFEA580C) : const Color(0xFFF97316))..style = PaintingStyle.fill;
    final white = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final line = Paint()..color = (isAlert ? const Color(0xFF9A3412) : const Color(0xFF94A3B8))..strokeWidth = 1.0..style = PaintingStyle.stroke;

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

    drawStripe(3, 6, size.height * 0.9, size.height * 0.75, orange);
    drawStripe(6, 9, size.height * 0.75, size.height * 0.6, white);
    drawStripe(9, 12, size.height * 0.6, size.height * 0.45, orange);
    drawStripe(12, 15, size.height * 0.45, size.height * 0.3, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// 6. MAP TRACKING SCREEN (THEFT RECOVERY)
// ==========================================
class MapTrackingScreen extends StatefulWidget {
  final HiveData hive;
  const MapTrackingScreen({super.key, required this.hive});

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  late List<LatLng> _path;
  bool _isRefreshing = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _path = widget.hive.recentPath.isNotEmpty 
        ? List<LatLng>.from(widget.hive.recentPath) 
        : [LatLng(widget.hive.latitude, widget.hive.longitude)];
  }

  Future<void> _refreshLocation() async {
    setState(() => _isRefreshing = true);
    try {
      final res = await supabase
          .from('telemetry')
          .select()
          .eq('hive_id', widget.hive.id)
          .order('created_at', ascending: false)
          .limit(48);

      final List<dynamic> data = res as List<dynamic>;
      if (data.isNotEmpty) {
        List<LatLng> newPath = [];
        for (var r in data.reversed) {
          final row = r as Map<String, dynamic>;
          if (row['latitude'] != null && row['longitude'] != null) {
            newPath.add(LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble()));
          }
        }
        if (newPath.isNotEmpty) {
          setState(() => _path = newPath);
          _mapController.move(_path.last, 16.0); 
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Τοποθεσία ανανεώθηκε επιτυχώς!'), 
              backgroundColor: Colors.green
            ));
          }
        }
      }
    } catch (e) {
      debugPrint("Map Refresh Error: $e");
    }
    setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final lastPos = _path.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 Εντοπισμός Ζυγαριάς', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF7F1D1D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: lastPos,
          initialZoom: 16.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.beehive_app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: _path,
                color: Colors.redAccent,
                strokeWidth: 4.0,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              ..._path.map((pos) => Marker(
                point: pos,
                width: 14, height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              )),
              Marker(
                point: lastPos,
                width: 60, height: 60,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, color: Colors.red, size: 55),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7F1D1D),
        foregroundColor: Colors.white,
        icon: _isRefreshing 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.refresh),
        label: const Text('Ανανέωση Θέσης'),
        onPressed: _isRefreshing ? null : _refreshLocation,
      ),
    );
  }
}