import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../api.dart';
import '../theme.dart';
import 'chat.dart';
import 'map.dart';
import 'members.dart';
import 'cards.dart';
import 'start.dart';

/// Everything the tabs share: trip, members, chat, live events, own position.
class TripState extends ChangeNotifier {
  Map trip = {};
  List<Map> members = [];
  List<Map> messages = [];
  Position? me;
  StreamSubscription? _ws, _gps;
  Timer? _reconnect;

  String get id => Session.instance.tripId!;
  int get radius => (trip['base_radius_m'] ?? 300) as int;
  List<Map> get outside => members.where((m) => m['care_group'] != 'guide' && m['fence_state'] != 'in').toList();

  Future<void> start() async {
    await refresh();
    _connect();
    _startGps();
  }

  Future<void> refresh() async {
    trip = await Api.trip(id);
    members = List<Map>.from(trip['members']);
    messages = List<Map>.from(await Api.messages(id));
    notifyListeners();
  }

  void _connect() {
    _ws = Api.events(id).listen(_onEvent, onDone: _retry, onError: (_) => _retry());
  }

  void _retry() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), () async {
      await refresh().catchError((_) {});
      _connect();
    });
  }

  void _onEvent(Map<String, dynamic> e) {
    final d = e['data'] as Map;
    switch (e['type']) {
      case 'message':
        messages.add(d);
      case 'translation':
        final m = messages.where((m) => m['id'] == d['messageId']).firstOrNull;
        if (m != null) m['translations'] = {...(m['translations'] as Map? ?? {}), d['lang']: d['body']};
      case 'position':
        final m = members.where((m) => m['id'] == d['memberId']).firstOrNull;
        if (m != null) {
          m['lat'] = d['lat'];
          m['lng'] = d['lng'];
        }
      case 'alert':
        final m = members.where((m) => m['id'] == d['memberId']).firstOrNull;
        if (m != null) m['fence_state'] = {'out': 'out', 'lost': 'lost'}[d['kind']] ?? 'in';
      case 'member':
        members.removeWhere((m) => m['id'] == d['id']);
        members.add(d);
      case 'trip':
        trip = {...trip, ...d};
      case 'checkin':
        members.where((m) => m['id'] == d['memberId']).firstOrNull?['checked_in_at'] = DateTime.now().toIso8601String();
    }
    notifyListeners();
  }

  Future<void> _startGps() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((p) {
      me = p;
      Api.sendPosition(p.latitude, p.longitude, p.accuracy).catchError((_) {});
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ws?.cancel();
    _gps?.cancel();
    _reconnect?.cancel();
    super.dispose();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final state = TripState();
  int tab = 0;

  @override
  void initState() {
    super.initState();
    state.start().catchError((_) {});
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  Future<void> logout() async {
    await Session.instance.clear();
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final guide = Session.instance.isGuide;
    final pages = [ChatTab(state), MapTab(state), MembersTab(state), if (guide) CardsTab(state)];
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.all(10),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(10)),
              child: const Padding(padding: EdgeInsets.all(4), child: FlockrMark(size: 24)),
            ),
          ),
          title: Text(state.trip['name'] ?? 'Flockr'),
          actions: [
            if (!guide)
              IconButton(
                tooltip: 'ขอความช่วยเหลือ',
                icon: const Icon(Icons.sos, color: Brand.alert),
                onPressed: () => Api.sos(state.me?.latitude, state.me?.longitude),
              ),
            IconButton(tooltip: 'ออกจากระบบ', icon: const Icon(Icons.logout), onPressed: logout),
          ],
        ),
        body: Column(children: [
          if (state.outside.isNotEmpty)
            MaterialBanner(
              backgroundColor: Brand.alert,
              content: Text('⚠ ${state.outside.map((m) => m['name']).join(', ')} อยู่นอกระยะหรือสัญญาณหาย',
                  style: const TextStyle(color: Colors.white)),
              actions: [TextButton(onPressed: () => setState(() => tab = 1), child: const Text('ดูแผนที่', style: TextStyle(color: Colors.white)))],
            ),
          Expanded(child: pages[tab.clamp(0, pages.length - 1)]),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab.clamp(0, pages.length - 1),
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'แชท'),
            const NavigationDestination(icon: Icon(Icons.map_outlined), label: 'แผนที่'),
            NavigationDestination(
              icon: Badge(isLabelVisible: state.outside.isNotEmpty, label: Text('${state.outside.length}'), child: const Icon(Icons.groups_outlined)),
              label: 'สมาชิก',
            ),
            if (guide) const NavigationDestination(icon: Icon(Icons.contactless_outlined), label: 'การ์ด'),
          ],
        ),
      ),
    );
  }
}
