import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http; // Online message anuppa thevai
import 'dart:convert';

void main() async {
WidgetsFlutterBinding.ensureInitialized();
SharedPreferences prefs = await SharedPreferences.getInstance();
bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

runApp(MaterialApp(
debugShowCheckedModeBanner: false,
theme: ThemeData(
primarySwatch: Colors.red,
useMaterial3: true,
colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
),
home: isLoggedIn ? EmergencyAlertApp() : LoginPage(),
));
}

// --- 1. LOGIN PAGE ---
class LoginPage extends StatefulWidget {
@override
LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
final TextEditingController _idController = TextEditingController();
final TextEditingController _pwController = TextEditingController();

bool _isPasswordVisible = false;

Future<void> _validateAndLogin() async {
if (_idController.text.isNotEmpty && _pwController.text.length >= 6) {
SharedPreferences prefs = await SharedPreferences.getInstance();
await prefs.setBool('isLoggedIn', true);
if (!mounted) return;
Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => EmergencyAlertApp()));
} else {
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid ID and Password")));
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
body: Center(
child: SingleChildScrollView(
padding: const EdgeInsets.all(30),
child: Column(
children: [
const Icon(Icons.gpp_good_rounded, size: 100, color: Colors.redAccent),
const Text("AI SAFEGUARD", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
const SizedBox(height: 40),
TextField(controller: _idController, decoration: InputDecoration(labelText: "Email or Phone", border:
OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
const SizedBox(height: 20),
TextField(
controller: _pwController,
obscureText: !_isPasswordVisible,
decoration: InputDecoration(
labelText: "Password",
suffixIcon: IconButton(icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible)),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))
)
),
const SizedBox(height: 30),
SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style:
ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: _validateAndLogin, child:
const Text("LOGIN / JOIN NETWORK", style: TextStyle(color: Colors.white)))),
],
),
),
),
);
}
}

// --- 2. MAIN DASHBOARD (VOICE AI & ONLINE NETWORKING) ---
class EmergencyAlertApp extends StatefulWidget {
@override
_EmergencyAlertAppState createState() => _EmergencyAlertAppState();
}

class _EmergencyAlertAppState extends State<EmergencyAlertApp> {
final Telephony telephony = Telephony.instance;
List<String> contacts = [];
final TextEditingController _contactController = TextEditingController();

// AI Voice Assistant Variables
stt.SpeechToText _speech = stt.SpeechToText();
String _lastWords = "Listening for 'Help'...";
bool _isSpeechAvailable = false;
bool _isTriggered = false; // Anti-spam lock

@override
void initState() {
super.initState();
_initializeApp();
}

Future<void> _initializeApp() async {
await _checkPermissions();
await _loadSavedContacts();
_initSpeech();
}

Future<void> _checkPermissions() async {
await [Permission.sms, Permission.location, Permission.microphone].request();
}

// --- AI VOICE RECOGNITION CORE ---
void _initSpeech() async {
_isSpeechAvailable = await _speech.initialize(
onError: (val) => _restartListening(),
onStatus: (val) {
if (val == 'done' || val == 'notListening') _restartListening();
},
);
if (_isSpeechAvailable) _startListening();
}

void _startListening() {
if (!_isSpeechAvailable || _speech.isListening) return;

_speech.listen(
onResult: (result) {
setState(() {
_lastWords = result.recognizedWords.toLowerCase();

// AI TRIGGER: 'Help' sonna automatic-ah alert pogum
if ((_lastWords.contains("help") || _lastWords.contains("emergency") || _lastWords.contains("save me"))
&& !_isTriggered) {
_isTriggered = true;
handleAlertTrigger("VOICE AI DETECTED");

// 20 seconds lock to prevent repeat SMS
Future.delayed(const Duration(seconds: 20), () {
if (mounted) setState(() => _isTriggered = false);
});
}
});
},
listenFor: const Duration(minutes: 30),
pauseFor: const Duration(seconds: 5),
listenMode: stt.ListenMode.dictation, // Continuous listening-ku ithu thaan best
);
}

void _restartListening() {
Future.delayed(const Duration(seconds: 1), () {
if (mounted) _startListening();
});
}

Future<void> _loadSavedContacts() async {
SharedPreferences prefs = await SharedPreferences.getInstance();
setState(() { contacts = prefs.getStringList('my_contacts') ?? []; });
}

Future<void> _saveContacts() async {
SharedPreferences prefs = await SharedPreferences.getInstance();
await prefs.setStringList('my_contacts', contacts);
}

// --- ALERT TRIGGER: SMS + ONLINE CLOUD ---
Future<void> handleAlertTrigger(String type) async {
if (contacts.isEmpty) {
_showAppNotification("No contacts added!");
return;
}

_showAppNotification(" Initiating Alert: $type");

try {
Position pos = await Geolocator.getCurrentPosition(
desiredAccuracy: LocationAccuracy.high,
timeLimit: const Duration(seconds: 10)
);

String mapLink =
"https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";
String msg = "AI SAFEGUARD ALERT [$type]\nI am in trouble! Location: $mapLink";

// 1. Offline SMS Alert
for (String num in contacts) {
await telephony.sendSms(to: num, message: msg);
}

// 2. Online Cloud Alert (Networking)
_sendToCloudServer(type, mapLink, pos);

_showAppNotification(" SMS & Online Alerts Sent!");
} catch (e) {
_showAppNotification("GPS Error! Check Location settings.");
}
}

// ONLINE CLOUD LOGIC
Future<void> _sendToCloudServer(String type, String link, Position pos) async {
// Unga Central Server URL-ah inga kudukkalam
const String apiUrl = "https://your-central-ai-server.com/api/alert";

try {
final response = await http.post(
Uri.parse(apiUrl),
headers: {"Content-Type": "application/json"},
body: jsonEncode({
"type": type,
"location": link,
"lat": pos.latitude,
"lng": pos.longitude,
"timestamp": DateTime.now().toIso8601String()
}),
);
print("Cloud Networking Status: ${response.statusCode}");
} catch (e) {
print("Offline: Cloud sync failed, SMS sent.");
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text("AI Safeguard Panel"),
actions: [
IconButton(icon: const Icon(Icons.person_add), onPressed: _showContactDialog),
IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
],
),
body: Padding(
padding: const EdgeInsets.all(20),
child: Column(
children: [
Container(
padding: const EdgeInsets.all(15),
width: double.infinity,
decoration: BoxDecoration(
color: Colors.blue[50],
borderRadius: BorderRadius.circular(15),
border: Border.all(color: Colors.blue.shade100)
),
child: Column(
children: [
const Icon(Icons.mic, color: Colors.blue, size: 35),
const SizedBox(height: 5),
const Text("AI Voice Monitor Active", style: TextStyle(fontWeight: FontWeight.bold, fontSize:
16)),
Text("'$_lastWords'",
textAlign: TextAlign.center,
style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey[800])
),
],
),
),
const SizedBox(height: 25),
const Align(alignment: Alignment.centerLeft, child: Text("Emergency Contacts", style:
TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
contacts.isEmpty ? const Padding(padding: EdgeInsets.all(10), child: Text("No contacts added.")) :
_buildContactChips(),
const Spacer(),
_alertCard("CRITICAL EMERGENCY", "Immediate SMS & Cloud Alert", Colors.red[700]!,
Icons.warning_rounded, "CRITICAL"),
const SizedBox(height: 15),
_alertCard("GENERAL ASSISTANCE", "Medical/Security Request", Colors.orange[700]!,
Icons.medical_services, "GENERAL"),
const SizedBox(height: 20),
],
),
),
);
}

Widget _buildContactChips() {
return Wrap(spacing: 8, children: contacts.map((n) => Chip(
backgroundColor: Colors.red[50],
label: Text(n),
onDeleted: () { setState(() => contacts.remove(n)); _saveContacts(); }
)).toList());
}

Widget _alertCard(String title, String sub, Color col, IconData icon, String mode) {
return InkWell(
onTap: () => handleAlertTrigger(mode),
child: Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: col,
borderRadius: BorderRadius.circular(20),
boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))]
),
child: Row(
children: [
Icon(icon, color: Colors.white, size: 40),
const SizedBox(width: 20),
Expanded(
child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
Text(sub, style: const TextStyle(color: Colors.white70)),
]),
),
],
),
),
);
}

void _showAppNotification(String text) {
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior:
SnackBarBehavior.floating));
}

void _showContactDialog() {
showDialog(context: context, builder: (c) => AlertDialog(
title: const Text("Add Contact"),
content: TextField(controller: _contactController, keyboardType: TextInputType.phone, decoration: const
InputDecoration(hintText: "10 Digit Number")),
actions: [
TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
ElevatedButton(onPressed: () {
if (_contactController.text.length >= 10) {
setState(() => contacts.add(_contactController.text));
_saveContacts();
_contactController.clear();
Navigator.pop(context);
}
}, child: const Text("Save"))
],
));
}
Future<void> _logout() async {
SharedPreferences prefs = await SharedPreferences.getInstance();
await prefs.setBool('isLoggedIn', false);
if (!mounted) return;
Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginPage()));
}
}
