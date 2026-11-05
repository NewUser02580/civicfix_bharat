import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'firebase_options.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://wpucqhplzqrpexscwshm.supabase.co',
    anonKey: 'sb_publishable_4b6MD6wxgUHR7y6--m26qw_sL_KJRnZ',
  );

  // A separate Supabase anonymous session is used only for photo uploads.
  // Firebase Authentication remains responsible for CivicFix user accounts.
  final supabaseAuth = Supabase.instance.client.auth;
  if (supabaseAuth.currentSession == null) {
    await supabaseAuth.signInAnonymously();
  }

  runApp(const CivicFixApp());
}

// ───────────────────────── DESIGN TOKENS ─────────────────────────
// Navy for authority, saffron + green as a quiet nod to the tricolour.
const navy = Color(0xFF12264A);
const blue = Color(0xFF2457D6);
const saffron = Color(0xFFFF9933);
const green = Color(0xFF138808);
const background = Color(0xFFF4F6FA);
const muted = Color(0xFF6F7C93);
const borderColor = Color(0xFFE6EBF3);

class CivicFixApp extends StatelessWidget {
  const CivicFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CivicFix Bharat',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: navy,
          titleTextStyle: TextStyle(
            color: navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: navy,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFFE3EBFF),
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? navy : muted,
            ),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ───────────────────────── SHARED HELPERS ─────────────────────────
class CategoryMeta {
  final String name;
  final IconData icon;
  final Color color;
  final Color tint;
  const CategoryMeta(this.name, this.icon, this.color, this.tint);
}

const categoryList = [
  CategoryMeta('Potholes', Icons.add_road_rounded, Color(0xFFEA6A12),
      Color(0xFFFFEBD9)),
  CategoryMeta('Garbage', Icons.delete_outline_rounded, Color(0xFF168657),
      Color(0xFFDDF6E8)),
  CategoryMeta('Streetlights', Icons.lightbulb_outline_rounded,
      Color(0xFFB98300), Color(0xFFFFF2C9)),
  CategoryMeta('Drainage', Icons.water_drop_outlined, Color(0xFF2457D6),
      Color(0xFFDDEBFF)),
  CategoryMeta('Water Supply', Icons.water_outlined, Color(0xFF6D47C9),
      Color(0xFFE9E1FF)),
  CategoryMeta('Other Issues', Icons.more_horiz_rounded, Color(0xFFD1366B),
      Color(0xFFFFE1E9)),
];

CategoryMeta metaFor(String name) => categoryList.firstWhere(
      (c) => c.name == name,
  orElse: () => categoryList.last,
);

class StatusStyle {
  final Color color;
  final Color bg;
  final IconData icon;
  const StatusStyle(this.color, this.bg, this.icon);

  static StatusStyle of(String status) {
    switch (status) {
      case 'Resolved':
        return const StatusStyle(
            Color(0xFF168657), Color(0xFFE1F5E9), Icons.check_circle_rounded);
      case 'In Progress':
        return const StatusStyle(
            Color(0xFFB7791F), Color(0xFFFFF1D6), Icons.autorenew_rounded);
      default:
        return const StatusStyle(
            blue, Color(0xFFE5EEFF), Icons.schedule_rounded);
    }
  }
}

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

InputDecoration fieldDecoration(String label, IconData icon, {Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFF6F8FC),
    border: border(borderColor),
    enabledBorder: border(borderColor),
    focusedBorder: border(blue, 1.6),
  );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = StatusStyle.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 12, color: s.color),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: s.color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!,
                    style: const TextStyle(color: muted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class ReportPhoto extends StatelessWidget {
  final String path;
  final double? width;
  final double height;
  final BoxFit fit;

  const ReportPhoto({
    super.key,
    required this.path,
    this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  Widget _placeholder({bool loading = false}) => Container(
    width: width,
    height: height,
    color: const Color(0xFFE8EEFB),
    alignment: Alignment.center,
    child: loading
        ? const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    )
        : const Icon(Icons.image_not_supported_outlined, color: blue),
  );

  @override
  Widget build(BuildContext context) {
    final isCloud = path.startsWith('http://') || path.startsWith('https://');
    if (isCloud) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (c, child, p) =>
        p == null ? child : _placeholder(loading: true),
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (!File(path).existsSync()) return _placeholder();
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}

// ───────────────────────── MODEL ─────────────────────────
class CivicReport {
  final String id;
  final String category;
  final String description;
  final String photoPath;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String status;
  final String department;
  final String adminNote;

  const CivicReport({
    required this.id,
    required this.category,
    required this.description,
    required this.photoPath,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.status = 'Submitted',
    this.department = '',
    this.adminNote = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'category': category,
    'description': description,
    'photoPath': photoPath,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'assignedDepartment': department,
    'adminNote': adminNote,
  };

  factory CivicReport.fromMap(Map<String, dynamic> map) {
    return CivicReport(
      id: map['id'] as String,
      category: map['category'] as String,
      description: map['description'] as String,
      photoPath: map['photoPath'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      status: map['status'] as String? ?? 'Submitted',
      department: map['assignedDepartment'] as String? ?? '',
      adminNote: map['adminNote'] as String? ?? '',
    );
  }
}

// ───────────────────── LOCAL CACHE + FIREBASE CLOUD STORAGE ─────────────────────
class ReportStorage {
  static const String storageKey = 'civicfix_reports';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<List<CivicReport>> loadReports() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _db
        .collection('reports')
        .where('userId', isEqualTo: user.uid)
        .get();

    final reports = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      data['createdAt'] =
          (data['createdAt'] as Timestamp).toDate().toIso8601String();
      return CivicReport.fromMap(data);
    }).toList();
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await saveLocalReports(reports);
    return reports;
  }

  static Future<List<CivicReport>> loadLocalReports() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved == null || saved.isEmpty) return [];
    try {
      final List<dynamic> data = jsonDecode(saved) as List<dynamic>;
      return data
          .map((item) => CivicReport.fromMap(
        Map<String, dynamic>.from(item as Map),
      ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLocalReports(List<CivicReport> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(reports.map((report) => report.toMap()).toList()),
    );
  }

  static Future<CivicReport> saveToCloud(CivicReport report) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in before submitting a report.');
    }

    String photoUrl = report.photoPath;
    if (!report.photoPath.startsWith('http://') &&
        !report.photoPath.startsWith('https://')) {
      final file = File(report.photoPath);
      if (!await file.exists()) {
        throw StateError(
            'The selected report photo could not be found on this device.');
      }

      // Storage access is restricted by the RLS policy to this Supabase
      // anonymous user's own first-level folder.
      final storageUser = _supabase.auth.currentUser;
      if (storageUser == null) {
        throw StateError(
            'Photo upload session is missing. Please restart the app.');
      }

      final extension = report.photoPath.toLowerCase().split('.').last;
      final contentType = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      final objectPath = '${storageUser.id}/${report.id}.$extension';

      await _supabase.storage.from('civicfix-photos').upload(
        objectPath,
        file,
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
      photoUrl =
          _supabase.storage.from('civicfix-photos').getPublicUrl(objectPath);
    }

    final cloudData = <String, dynamic>{
      'category': report.category,
      'description': report.description,
      'photoPath': photoUrl,
      'latitude': report.latitude,
      'longitude': report.longitude,
      'createdAt': Timestamp.fromDate(report.createdAt),
      'status': report.status,
      'userId': user.uid,
      'userEmail': user.email,
    };
    await _db.collection('reports').doc(report.id).set(cloudData);

    return CivicReport(
      id: report.id,
      category: report.category,
      description: report.description,
      photoPath: photoUrl,
      latitude: report.latitude,
      longitude: report.longitude,
      createdAt: report.createdAt,
      status: report.status,
    );
  }
}

// ───────────────────────── HOME ─────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedTab = 0;
  bool loading = true;
  List<CivicReport> reports = [];

  @override
  void initState() {
    super.initState();
    loadSavedReports();
  }

  Future<void> loadSavedReports() async {
    try {
      final savedReports = await ReportStorage.loadReports();
      if (!mounted) return;
      setState(() {
        reports = savedReports;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load cloud reports: $error')),
      );
    }
  }

  Future<void> openReport({String category = 'Other Issues'}) async {
    if (FirebaseAuth.instance.currentUser == null) {
      final shouldLogin = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (shouldLogin != true || !mounted) return;
      await loadSavedReports();
    }
    if (!mounted) return;

    final result = await Navigator.push<CivicReport>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(initialCategory: category),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final cloudReport = await ReportStorage.saveToCloud(result);
      if (!mounted) return;
      setState(() {
        reports.insert(0, cloudReport);
        selectedTab = 1;
      });
      await ReportStorage.saveLocalReports(reports);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for improving your city!'),
          backgroundColor: Color(0xFF168657),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save report or upload photo: $error')),
      );
    }
  }

  int get resolvedCount => reports.where((r) => r.status == 'Resolved').length;

  int get inProgressCount =>
      reports.where((r) => r.status == 'In Progress').length;

  int get pendingCount => reports.where((r) => r.status == 'Submitted').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
          index: selectedTab,
          children: [
            dashboard(),
            ReportsScreen(
              reports: reports,
              onRefresh: loadSavedReports,
              onReport: () => openReport(),
            ),
            ImpactScreen(
              total: reports.length,
              resolved: resolvedCount,
              inProgress: inProgressCount,
              pending: pendingCount,
            ),
            ProfileScreen(onAuthChanged: loadSavedReports),
          ],
        ),
      ),
      floatingActionButton: selectedTab == 0 && !loading
          ? FloatingActionButton.extended(
        onPressed: () => openReport(),
        backgroundColor: saffron,
        foregroundColor: navy,
        elevation: 3,
        icon: const Icon(Icons.add_a_photo_rounded),
        label: const Text(
          'Report',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
          // Refresh cloud report statuses whenever the citizen opens My Reports.
          if (index == 1 && FirebaseAuth.instance.currentUser != null) {
            loadSavedReports();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: navy),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded, color: navy),
            label: 'My Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.volunteer_activism_outlined),
            selectedIcon: Icon(Icons.volunteer_activism_rounded, color: navy),
            label: 'Impact',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: navy),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget dashboard() {
    final user = FirebaseAuth.instance.currentUser;
    final first = (user?.displayName ?? '').trim().split(' ').first;
    final greeting = first.isEmpty ? 'Hello, citizen' : 'Hello, $first';

    return RefreshIndicator(
      onRefresh: loadSavedReports,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.location_city_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'CivicFix Bharat · Your city, your responsibility',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor),
                ),
                child: IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You are all caught up!')),
                    );
                  },
                  icon: const Icon(Icons.notifications_none_rounded,
                      color: navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _heroBanner(),
          const SizedBox(height: 24),
          const SectionTitle('Your civic activity'),
          const SizedBox(height: 12),
          Row(
            children: [
              statCard('Total', '${reports.length}',
                  Icons.description_outlined, blue, const Color(0xFFE5EEFF)),
              const SizedBox(width: 10),
              statCard('Resolved', '$resolvedCount',
                  Icons.check_circle_outline_rounded, green,
                  const Color(0xFFE1F5E9)),
              const SizedBox(width: 10),
              statCard('In progress', '$inProgressCount',
                  Icons.pending_actions_rounded, const Color(0xFFB7791F),
                  const Color(0xFFFFF1D6)),
            ],
          ),
          const SizedBox(height: 26),
          const SectionTitle(
            'Report by category',
            subtitle: 'Tap the issue you noticed around you.',
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categoryList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 11,
              mainAxisSpacing: 11,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final item = categoryList[index];
              return AppCard(
                padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                onTap: () => openReport(category: item.name),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: item.tint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(item.icon, color: item.color, size: 26),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      item.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 26),
          SectionTitle(
            'Recent reports',
            trailing: TextButton(
              onPressed: () => setState(() => selectedTab = 1),
              child: const Text('View all'),
            ),
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.campaign_outlined, size: 40, color: blue),
                  const SizedBox(height: 10),
                  const Text(
                    'No reports yet',
                    style: TextStyle(
                        color: navy, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Spot a problem? Add a photo and location and we will send it to the right team.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => openReport(),
                    style: FilledButton.styleFrom(backgroundColor: navy),
                    child: const Text('Report your first issue'),
                  ),
                ],
              ),
            )
          else
            ...reports.take(3).map((report) => ReportTile(report: report)),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Small actions. Cleaner streets. Stronger communities.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0E1D3A), Color(0xFF1F4A93)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -50,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: saffron.withValues(alpha: 0.14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'See a problem?\nBe the solution.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Report civic issues in your area and track every fix from submission to resolution.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => openReport(),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Report an issue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: saffron,
                      foregroundColor: navy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Tricolour accent strip
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(child: Container(height: 4, color: saffron)),
                        Expanded(child: Container(height: 4, color: Colors.white)),
                        Expanded(
                            child: Container(
                                height: 4, color: const Color(0xFF2FA82A))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget statCard(
      String title, String number, IconData icon, Color color, Color tint) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 9),
            Text(
              number,
              style: const TextStyle(
                color: navy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── REPORT FORM ─────────────────────────
class ReportScreen extends StatefulWidget {
  final String initialCategory;

  const ReportScreen({super.key, required this.initialCategory});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late String category;

  final descriptionController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  XFile? selectedImage;
  Position? currentPosition;
  bool gettingLocation = false;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
    descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  int get completedSteps =>
      (descriptionController.text.trim().isNotEmpty ? 1 : 0) +
          (selectedImage != null ? 1 : 0) +
          (currentPosition != null ? 1 : 0);

  Future<void> chooseImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add photo evidence',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: navy),
              ),
              const SizedBox(height: 4),
              const Text(
                'A clear photo helps the team find and fix the issue faster.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE5EEFF),
                  child: Icon(Icons.camera_alt_rounded, color: blue),
                ),
                title: const Text('Take a photo'),
                subtitle: const Text('Open your phone camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFDDF6E8),
                  child: Icon(Icons.photo_library_rounded,
                      color: Color(0xFF137650)),
                ),
                title: const Text('Choose from gallery'),
                subtitle: const Text('Select an existing image'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    try {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );

      if (!mounted) return;

      if (image != null) {
        setState(() => selectedImage = image);
      }
    } catch (error) {
      if (!mounted) return;
      showMessage('Could not select photo: $error');
    }
  }

  Future<void> getCurrentLocation() async {
    setState(() => gettingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        showMessage('Please turn on Location/GPS on your phone.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        showMessage('Location permission was denied.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        showMessage(
            'Location permission is blocked. Enable it in app settings.');
        await Geolocator.openAppSettings();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;

      setState(() => currentPosition = position);
      showMessage('Current GPS location captured successfully.');
    } catch (error) {
      if (!mounted) return;
      showMessage('Could not get location: $error');
    } finally {
      if (mounted) {
        setState(() => gettingLocation = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget stepHeader(int n, String title, bool done) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? green : navy,
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
              color: navy, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }

  Widget categorySection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categoryList.map((c) {
        final selected = c.name == category;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => setState(() => category = c.name),
          avatar: Icon(c.icon, size: 18, color: selected ? navy : c.color),
          label: Text(c.name),
          labelStyle: TextStyle(
            color: navy,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
          selectedColor: c.tint,
          backgroundColor: Colors.white,
          showCheckmark: false,
          side: BorderSide(color: selected ? c.color : borderColor),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        );
      }).toList(),
    );
  }

  Widget photoSection() {
    if (selectedImage == null) {
      return InkWell(
        onTap: chooseImage,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB9CDF5), width: 1.4),
          ),
          child: const Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Icon(Icons.add_a_photo_rounded, color: blue, size: 27),
              ),
              SizedBox(height: 12),
              Text(
                'Add a photo',
                style: TextStyle(
                    color: navy, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                'Take one now or choose from your gallery',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.file(
              File(selectedImage!.path),
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.check_circle_rounded, color: green, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Photo attached',
                  style: TextStyle(
                      color: navy, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              TextButton(onPressed: chooseImage, child: const Text('Change')),
              IconButton(
                onPressed: () => setState(() => selectedImage = null),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget locationSection() {
    final has = currentPosition != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: has ? const Color(0xFFF1FAF4) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: has ? const Color(0xFFBFE5CC) : borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: has ? const Color(0xFFDDF6E8) : const Color(0xFFE5EEFF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  has ? Icons.location_on_rounded : Icons.location_on_outlined,
                  color: has ? green : blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Issue location',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: navy, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    if (has)
                      SelectableText(
                        '${currentPosition!.latitude.toStringAsFixed(6)}, '
                            '${currentPosition!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(color: navy, fontSize: 12.5),
                      )
                    else
                      const Text(
                        'Stand near the issue, then capture your GPS position.',
                        style: TextStyle(color: muted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: gettingLocation ? null : getCurrentLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: navy,
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: Color(0xFFC9D5EA)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              icon: gettingLocation
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.my_location_rounded),
              label: Text(
                gettingLocation
                    ? 'Getting location...'
                    : has
                    ? 'Refresh location'
                    : 'Get current location',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> submitReport() async {
    if (descriptionController.text.trim().isEmpty) {
      showMessage('Please describe the issue first.');
      return;
    }

    if (selectedImage == null) {
      showMessage('Please attach a photo as evidence.');
      return;
    }

    if (currentPosition == null) {
      showMessage('Please capture the current GPS location.');
      return;
    }

    setState(() => submitting = true);

    try {
      final appDirectory = await getApplicationDocumentsDirectory();
      final extension = selectedImage!.path.contains('.')
          ? selectedImage!.path.split('.').last
          : 'jpg';

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final permanentPath = '${appDirectory.path}/civic_$id.$extension';

      await File(selectedImage!.path).copy(permanentPath);

      final report = CivicReport(
        id: id,
        category: category,
        description: descriptionController.text.trim(),
        photoPath: permanentPath,
        latitude: currentPosition!.latitude,
        longitude: currentPosition!.longitude,
        createdAt: DateTime.now(),
      );

      if (!mounted) return;
      Navigator.pop(context, report);
    } catch (error) {
      if (!mounted) return;
      showMessage('Could not save report photo: $error');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = metaFor(category);
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: meta.tint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(meta.icon, color: meta.color, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Reporting: $category',
                        style: const TextStyle(
                            color: navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5),
                      ),
                    ),
                    Text(
                      '$completedSteps of 3 done',
                      style: const TextStyle(color: muted, fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: completedSteps / 3,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE8EDF5),
                    valueColor: const AlwaysStoppedAnimation<Color>(saffron),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'What kind of issue is it?',
            style: TextStyle(
                color: navy, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          categorySection(),
          const SizedBox(height: 26),
          stepHeader(1, 'Describe the problem',
              descriptionController.text.trim().isNotEmpty),
          const SizedBox(height: 12),
          TextField(
            controller: descriptionController,
            maxLines: 5,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What happened, and where exactly? Add landmarks if you can.',
              hintStyle: const TextStyle(color: muted, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: blue, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 14),
          stepHeader(2, 'Photo evidence', selectedImage != null),
          const SizedBox(height: 12),
          photoSection(),
          const SizedBox(height: 24),
          stepHeader(3, 'Location', currentPosition != null),
          const SizedBox(height: 12),
          locationSection(),
          const SizedBox(height: 28),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: submitting ? null : submitReport,
              icon: submitting
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
                  : const Icon(Icons.send_rounded),
              label: Text(submitting ? 'Saving report...' : 'Submit report'),
              style: FilledButton.styleFrom(
                backgroundColor: navy,
                textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── REPORT CARD ─────────────────────────
class ReportTile extends StatelessWidget {
  final CivicReport report;

  const ReportTile({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final meta = metaFor(report.category);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportDetailsScreen(report: report),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ReportPhoto(path: report.photoPath, width: 78, height: 88),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(meta.icon, size: 16, color: meta.color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        report.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  report.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: muted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    StatusChip(status: report.status),
                    const Spacer(),
                    const Icon(Icons.schedule_rounded, size: 12, color: muted),
                    const SizedBox(width: 3),
                    Text(timeAgo(report.createdAt),
                        style: const TextStyle(color: muted, fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── REPORT DETAILS ─────────────────────────
class ReportDetailsScreen extends StatelessWidget {
  final CivicReport report;

  const ReportDetailsScreen({super.key, required this.report});

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month/$year · $hour:$minute $period';
  }

  Future<void> _openMap(BuildContext context) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${report.latitude},${report.longitude}',
    );
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the map.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the map.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = metaFor(report.category);

    return Scaffold(
      backgroundColor: background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: navy,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.92),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: navy),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  ReportPhoto(
                      path: report.photoPath,
                      width: double.infinity,
                      height: 280),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          navy.withValues(alpha: 0.75),
                        ],
                        stops: const [0.5, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: meta.tint,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(meta.icon, color: meta.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.category,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _formatDate(report.createdAt),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusChip(status: report.status),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: Column(
                children: [
                  _detailCard(
                    icon: Icons.track_changes_rounded,
                    title: 'Progress',
                    child: _timeline(),
                  ),
                  if (report.adminNote.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _detailCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Update from the team',
                      child: Text(
                        report.adminNote,
                        style: const TextStyle(
                            color: navy, fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _detailCard(
                    icon: Icons.notes_rounded,
                    title: 'Issue description',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        report.description,
                        style: const TextStyle(
                            color: navy, fontSize: 13, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailCard(
                    icon: Icons.location_on_outlined,
                    title: 'Reported location',
                    child: Column(
                      children: [
                        _coordinateRow(
                            'Latitude', report.latitude.toStringAsFixed(6)),
                        const SizedBox(height: 10),
                        _coordinateRow(
                            'Longitude', report.longitude.toStringAsFixed(6)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: () => _openMap(context),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('View on map'),
                            style: FilledButton.styleFrom(
                              backgroundColor: navy,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline() {
    const steps = ['Submitted', 'In Progress', 'Resolved'];
    int current = steps.indexOf(report.status);
    if (current < 0) current = 0;

    String subtitle(int i) {
      switch (i) {
        case 0:
          return 'Recorded ${timeAgo(report.createdAt)}';
        case 1:
          if (current >= 1) {
            return report.department.isNotEmpty
                ? 'Assigned to ${report.department}'
                : 'The team is working on it';
          }
          return 'Waiting for the team to pick this up';
        default:
          return current >= 2 ? 'Issue fixed. Thank you!' : 'Not resolved yet';
      }
    }

    return Column(
      children: List.generate(steps.length, (i) {
        final done = i <= current;
        final last = i == steps.length - 1;
        final s = StatusStyle.of(steps[i]);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: done ? s.color : const Color(0xFFE8EDF5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        done ? Icons.check_rounded : Icons.circle,
                        size: done ? 15 : 6,
                        color: done ? Colors.white : const Color(0xFFB3BDCE),
                      ),
                    ),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: i < current
                              ? s.color
                              : const Color(0xFFE8EDF5),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i],
                        style: TextStyle(
                          color: done ? navy : muted,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle(i),
                          style: const TextStyle(color: muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _detailCard(
      {required IconData icon, required String title, required Widget child}) {
    return AppCard(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: blue, size: 19),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      color: navy, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _coordinateRow(String label, String value) => Row(
    children: [
      Expanded(
          child: Text(label,
              style: const TextStyle(color: muted, fontSize: 12.5))),
      SelectableText(value,
          style: const TextStyle(
              color: navy, fontWeight: FontWeight.w800, fontSize: 12.5)),
    ],
  );
}

// ───────────────────────── MY REPORTS ─────────────────────────
class ReportsScreen extends StatefulWidget {
  final List<CivicReport> reports;
  final Future<void> Function() onRefresh;
  final VoidCallback onReport;

  const ReportsScreen({
    super.key,
    required this.reports,
    required this.onRefresh,
    required this.onReport,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    const filters = ['All', 'Submitted', 'In Progress', 'Resolved'];
    int countFor(String f) => f == 'All'
        ? widget.reports.length
        : widget.reports.where((r) => r.status == f).length;
    final shown = filter == 'All'
        ? widget.reports
        : widget.reports.where((r) => r.status == filter).toList();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          const Text(
            'My reports',
            style: TextStyle(
                fontSize: 27, fontWeight: FontWeight.w800, color: navy),
          ),
          const SizedBox(height: 4),
          const Text(
            'Track the civic issues you have submitted.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final selected = f == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => filter = f),
                    label: Text('$f (${countFor(f)})'),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    selectedColor: navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: selected ? navy : borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          if (shown.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(28),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const Icon(Icons.assignment_outlined,
                        size: 52, color: blue),
                    const SizedBox(height: 12),
                    Text(
                      filter == 'All' ? 'No reports yet' : 'Nothing here yet',
                      style: const TextStyle(
                          color: navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      filter == 'All'
                          ? 'Your submitted civic reports will appear here.'
                          : 'No reports are marked "$filter" right now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                    if (filter == 'All') ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: widget.onReport,
                        style: FilledButton.styleFrom(backgroundColor: navy),
                        child: const Text('Report an issue'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ...shown.map((report) => ReportTile(report: report)),
        ],
      ),
    );
  }
}

// ───────────────────────── CIVIC IMPACT ─────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.16);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = saffron;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

class ImpactScreen extends StatelessWidget {
  final int total;
  final int resolved;
  final int inProgress;
  final int pending;

  const ImpactScreen({
    super.key,
    required this.total,
    required this.resolved,
    required this.inProgress,
    required this.pending,
  });

  String get level {
    if (total == 0) return 'New citizen';
    if (total < 3) return 'Active citizen';
    if (total < 10) return 'Community hero';
    return 'Civic champion';
  }

  String get nextGoal {
    if (total == 0) return 'Submit your first report to get started.';
    if (total < 3) return '${3 - total} more to become a community hero.';
    if (total < 10) return '${10 - total} more to become a civic champion.';
    return 'You have reached the top level. Keep going!';
  }

  @override
  Widget build(BuildContext context) {
    final double resolutionRate = total == 0 ? 0 : resolved / total;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your civic impact',
            style: TextStyle(
                color: navy, fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'See how your reports are helping your city.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E1D3A), Color(0xFF1F4A93)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: resolutionRate),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CustomPaint(
                      painter: _RingPainter(value),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(value * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text('resolved',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('reports submitted',
                          style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: saffron,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          level,
                          style: const TextStyle(
                              color: navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(nextGoal,
                style: const TextStyle(color: muted, fontSize: 12.5)),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Report statistics'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _impactCard('Resolved', resolved,
                    Icons.check_circle_rounded, green, const Color(0xFFE1F5E9)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _impactCard(
                    'In progress',
                    inProgress,
                    Icons.pending_actions_rounded,
                    const Color(0xFFB7791F),
                    const Color(0xFFFFF1D6)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _impactCard('Submitted', pending,
                    Icons.hourglass_empty_rounded, blue,
                    const Color(0xFFE5EEFF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _impactCard(
                    'Resolution rate',
                    (resolutionRate * 100).round(),
                    Icons.trending_up_rounded,
                    const Color(0xFF7652B5),
                    const Color(0xFFEDE5FF),
                    suffix: '%'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFE0B8)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.volunteer_activism_rounded,
                    color: Color(0xFFD97706), size: 30),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Together we make a difference',
                        style: TextStyle(
                            color: navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Every report helps create cleaner, safer neighbourhoods. Keep reporting and be a responsible citizen.',
                        style:
                        TextStyle(color: muted, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _impactCard(
      String title,
      int value,
      IconData icon,
      Color iconColor,
      Color backgroundColor, {
        String suffix = '',
      }) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(height: 13),
          Text(
            '$value$suffix',
            style: const TextStyle(
                color: navy, fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
                color: muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── PROFILE ─────────────────────────
class ProfileScreen extends StatelessWidget {
  final Future<void> Function() onAuthChanged;
  const ProfileScreen({super.key, required this.onAuthChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isSignedIn = user != null;
        if (!isSignedIn) {
          return _profileContent(context, null, false, false);
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future:
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, roleSnapshot) {
            final role =
                roleSnapshot.data?.data()?['role']?.toString() ?? 'citizen';
            final isAdmin = role == 'admin';
            return _profileContent(context, user, true, isAdmin);
          },
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Log out?'),
        content: const Text('You can log back in any time to see your reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay logged in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      await onAuthChanged();
    }
  }

  Widget _menuTile(IconData icon, String title, String? subtitle,
      {VoidCallback? onTap, Color color = blue}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(title,
          style: TextStyle(
              color: color == Colors.red ? Colors.red : navy,
              fontWeight: FontWeight.w700,
              fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, color: muted),
    );
  }

  Widget _profileContent(
      BuildContext context, User? user, bool isSignedIn, bool isAdmin) {
    final name = isSignedIn
        ? (user!.displayName?.isNotEmpty == true
        ? user.displayName!
        : (isAdmin ? 'CivicFix Administrator' : 'Signed-in citizen'))
        : 'Welcome to CivicFix';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0E1D3A), Color(0xFF1F4A93)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: Colors.white,
                child: Icon(
                  isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : (isSignedIn
                      ? Icons.verified_user_rounded
                      : Icons.person_rounded),
                  size: 42,
                  color: navy,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                isSignedIn
                    ? (user!.email ?? '')
                    : 'Sign in to save and track your reports in the cloud.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              if (isSignedIn) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: saffron,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isAdmin ? 'Administrator' : 'Citizen',
                    style: const TextStyle(
                        color: navy, fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (!isSignedIn) ...[
          FilledButton.icon(
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                    const AuthScreen(initialMode: AuthMode.login)),
              );
              if (changed == true) await onAuthChanged();
            },
            icon: const Icon(Icons.login_rounded),
            label: const Text('Login'),
            style: FilledButton.styleFrom(
              backgroundColor: navy,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                    const AuthScreen(initialMode: AuthMode.signup)),
              );
              if (changed == true) await onAuthChanged();
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Create an account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: navy,
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: const BorderSide(color: Color(0xFFC9D5EA)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ] else ...[
          if (isAdmin) ...[
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminDashboardScreen()),
              ),
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('Open admin dashboard'),
              style: FilledButton.styleFrom(
                backgroundColor: saffron,
                foregroundColor: navy,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                _menuTile(Icons.email_outlined, 'Email',
                    user!.email ?? 'Not available'),
                const Divider(height: 1),
                _menuTile(Icons.badge_outlined, 'Account role',
                    isAdmin ? 'Administrator' : 'Citizen'),
                const Divider(height: 1),
                _menuTile(Icons.cloud_done_outlined, 'Cloud reports',
                    'Your reports are linked to this account.'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              _menuTile(
                Icons.info_outline_rounded,
                'About CivicFix Bharat',
                'A citizen-focused civic issue reporting app.',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'CivicFix Bharat',
                  applicationLegalese: 'Your city. Your responsibility.',
                ),
              ),
              if (isSignedIn) ...[
                const Divider(height: 1),
                _menuTile(Icons.logout_rounded, 'Log out', null,
                    color: Colors.red, onTap: () => _confirmLogout(context)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ───────────────────────── ADMIN DASHBOARD ─────────────────────────
// Visible only to accounts whose Firestore users/{uid}.role is admin.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin dashboard')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load reports. Check Firestore rules.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          String statusOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              (d.data()['status'] ?? 'Submitted').toString();
          final pending = docs.where((d) => statusOf(d) == 'Submitted').length;
          final progress =
              docs.where((d) => statusOf(d) == 'In Progress').length;
          final resolved = docs.where((d) => statusOf(d) == 'Resolved').length;
          final shown = filter == 'All'
              ? docs
              : docs.where((d) => statusOf(d) == filter).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E1D3A), Color(0xFF1F4A93)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Civic issue overview',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      '${docs.length} total reports',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      _adminCount('Submitted', pending),
                      _adminCount('In progress', progress),
                      _adminCount('Resolved', resolved),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SectionTitle('Manage reports'),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Submitted', 'In Progress', 'Resolved']
                      .map((f) {
                    final selected = f == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => filter = f),
                        label: Text(f),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                        selectedColor: navy,
                        backgroundColor: Colors.white,
                        side: BorderSide(color: selected ? navy : borderColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child: Text('No reports match this filter.',
                        style: TextStyle(color: muted)),
                  ),
                )
              else
                ...shown.map(
                        (doc) => _AdminReportCard(reportId: doc.id, data: doc.data())),
            ],
          );
        },
      ),
    );
  }

  Widget _adminCount(String label, int value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    ),
  );
}

class _AdminReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  const _AdminReportCard({required this.reportId, required this.data});

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'Submitted').toString();
    final category = (data['category'] ?? 'Civic issue').toString();
    final meta = metaFor(category);
    final description = (data['description'] ?? '').toString();
    final email = (data['userEmail'] ?? data['userId'] ?? 'Citizen').toString();
    final department = (data['assignedDepartment'] ?? 'Not assigned').toString();
    final photoUrl = (data['photoPath'] ?? '').toString();
    final latitude = _asDouble(data['latitude']);
    final longitude = _asDouble(data['longitude']);
    final createdAt = data['createdAt'];
    final dateText = createdAt is Timestamp
        ? createdAt.toDate().toLocal().toString().split('.').first
        : 'Date unavailable';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: meta.tint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(meta.icon, color: meta.color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                      color: navy, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 12),
          if (photoUrl.startsWith('https://') || photoUrl.startsWith('http://'))
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                photoUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                  height: 180,
                  alignment: Alignment.center,
                  color: const Color(0xFFE5EEFF),
                  child: const CircularProgressIndicator(),
                ),
                errorBuilder: (context, error, stack) => _photoUnavailable(
                  'Photo could not be loaded. Check the stored photo URL and bucket access.',
                ),
              ),
            )
          else
            _photoUnavailable('No uploaded photo URL was saved for this report.'),
          const SizedBox(height: 12),
          Text(
            description.isEmpty ? 'No description provided.' : description,
            style: const TextStyle(color: navy, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.person_outline, 'Citizen', email),
          _infoRow(Icons.calendar_today_outlined, 'Submitted', dateText),
          _infoRow(Icons.account_tree_outlined, 'Department', department),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: latitude != null && longitude != null
                      ? SelectableText(
                    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: navy, fontSize: 12),
                  )
                      : const Text('GPS coordinates are not available.',
                      style: TextStyle(color: muted, fontSize: 11.5)),
                ),
                if (latitude != null && longitude != null)
                  TextButton.icon(
                    onPressed: () => _openMap(context, latitude, longitude),
                    icon: const Icon(Icons.map_outlined, size: 17),
                    label: const Text('Map'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showUpdateDialog(context),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Update report'),
              style: FilledButton.styleFrom(
                backgroundColor: navy,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Widget _photoUnavailable(String message) => Container(
    width: double.infinity,
    height: 120,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF3FA),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.image_not_supported_outlined,
            color: muted, size: 30),
        const SizedBox(height: 7),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: blue, size: 15),
        const SizedBox(width: 7),
        Text('$label: ',
            style: const TextStyle(color: muted, fontSize: 11.5)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: navy, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Future<void> _openMap(
      BuildContext context, double latitude, double longitude) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open location: $error')),
        );
      }
    }
  }

  Future<void> _showUpdateDialog(BuildContext context) async {
    String selectedStatus = (data['status'] ?? 'Submitted').toString();
    String selectedDepartment =
    (data['assignedDepartment'] ?? 'Roads & Infrastructure').toString();
    final noteController = TextEditingController(
      text: (data['adminNote'] ?? '').toString(),
    );
    const departments = [
      'Roads & Infrastructure',
      'Sanitation',
      'Street Lighting',
      'Water Supply',
      'Drainage',
      'Other',
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Update civic report',
              style: TextStyle(color: navy, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: ['Submitted', 'In Progress', 'Resolved']
                      .contains(selectedStatus)
                      ? selectedStatus
                      : 'Submitted',
                  decoration:
                  fieldDecoration('Report status', Icons.flag_outlined),
                  items: const [
                    DropdownMenuItem(
                        value: 'Submitted', child: Text('Submitted')),
                    DropdownMenuItem(
                        value: 'In Progress', child: Text('In Progress')),
                    DropdownMenuItem(
                        value: 'Resolved', child: Text('Resolved')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedStatus = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: departments.contains(selectedDepartment)
                      ? selectedDepartment
                      : departments.first,
                  decoration: fieldDecoration(
                      'Assign department', Icons.account_tree_outlined),
                  items: departments
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedDepartment = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: fieldDecoration(
                      'Admin remarks', Icons.chat_bubble_outline_rounded)
                      .copyWith(hintText: 'Describe the action taken...'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: navy),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('reports')
                      .doc(reportId)
                      .update({
                    'status': selectedStatus,
                    'assignedDepartment': selectedDepartment,
                    'adminNote': noteController.text.trim(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Report updated successfully.')),
                    );
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Could not update report: $error')),
                    );
                  }
                }
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── AUTH ─────────────────────────
enum AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  final AuthMode initialMode;
  const AuthScreen({super.key, this.initialMode = AuthMode.login});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late AuthMode _mode;
  bool _loading = false;
  bool _obscurePassword = true;

  bool get _isSignup => _mode == AuthMode.signup;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final auth = FirebaseAuth.instance;
      if (_isSignup) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final name = _nameController.text.trim();
        if (name.isNotEmpty) await credential.user?.updateDisplayName(name);
        if (credential.user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(credential.user!.uid)
              .set({
            'displayName': name,
            'email': _emailController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = e.message ?? 'Authentication failed. Please try again.';
      if (e.code == 'email-already-in-use') {
        message = 'This email already has an account. Please log in.';
      }
      if (e.code == 'weak-password') {
        message = 'Choose a password with at least 6 characters.';
      }
      if (e.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      }
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        message = 'Email or password is incorrect.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0E1D3A), Color(0xFF1F4A93)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 24, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.location_city_rounded,
                                  color: navy, size: 32),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _isSignup ? 'Create your account' : 'Welcome back',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isSignup
                                  ? 'Join your community and help improve your city.'
                                  : 'Log in to view and manage your civic reports.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isSignup) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                        fieldDecoration('Full name', Icons.person_outline),
                        validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration:
                      fieldDecoration('Email address', Icons.email_outlined),
                      validator: (value) => value == null || !value.contains('@')
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: [
                        _isSignup
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                      decoration: fieldDecoration(
                        'Password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 6
                          ? 'Password must be at least 6 characters.'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: navy,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _loading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                            : Text(
                          _isSignup ? 'Create account' : 'Login',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _mode =
                      _isSignup ? AuthMode.login : AuthMode.signup),
                      child: Text(_isSignup
                          ? 'Already have an account? Login'
                          : 'New to CivicFix Bharat? Create an account'),
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
}