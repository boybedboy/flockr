import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Change at build time: flutter run --dart-define=API=https://api.flockr.app
const apiBase = String.fromEnvironment('API', defaultValue: 'http://10.0.2.2:3100');

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

/// Session: either a guide (kind=staff) or a tourist (kind=member), plus the current trip.
class Session {
  String? token, kind, tripId, memberId;

  static final instance = Session();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    kind = p.getString('kind');
    tripId = p.getString('tripId');
    memberId = p.getString('memberId');
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    for (final e in {'token': token, 'kind': kind, 'tripId': tripId, 'memberId': memberId}.entries) {
      e.value == null ? await p.remove(e.key) : await p.setString(e.key, e.value!);
    }
  }

  Future<void> clear() async {
    token = kind = tripId = memberId = null;
    await save();
  }

  bool get isGuide => kind == 'staff';
}

class Api {
  static final _s = Session.instance;

  static Future<dynamic> call(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$apiBase$path'))
      ..headers['content-type'] = 'application/json';
    if (_s.token != null) req.headers['authorization'] = 'Bearer ${_s.token}';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 15)));
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) throw ApiError(res.statusCode, data?['error'] ?? 'เกิดข้อผิดพลาด');
    return data;
  }

  static Future<void> login(String email, String password) async {
    final r = await call('POST', '/api/auth/login', {'email': email, 'password': password});
    _s
      ..token = r['token']
      ..kind = 'staff';
    await _s.save();
  }

  static Future<void> join(Map<String, dynamic> body) async {
    final r = await call('POST', '/api/join', body);
    _s
      ..token = r['token']
      ..kind = 'member'
      ..tripId = r['trip']['id']
      ..memberId = r['member']['id'];
    await _s.save();
  }

  static Future<List> trips() async => await call('GET', '/api/trips') as List;
  static Future<Map> trip(String id) async => await call('GET', '/api/trips/$id') as Map;
  static Future<List> messages(String id) async => await call('GET', '/api/trips/$id/messages') as List;
  static Future send(String id, String body) => call('POST', '/api/trips/$id/messages', {'body': body});
  static Future setRadius(String id, int m) => call('PATCH', '/api/trips/$id', {'baseRadiusM': m});

  static Future sendPosition(double lat, double lng, double acc) {
    final s = _s;
    return s.isGuide
        ? call('POST', '/api/trips/${s.tripId}/guide-position', {'lat': lat, 'lng': lng})
        : call('POST', '/api/me/position', {'lat': lat, 'lng': lng, 'accuracy': acc});
  }

  static Future sos(double? lat, double? lng) => call('POST', '/api/me/sos', lat == null ? {} : {'lat': lat, 'lng': lng});
  static Future<Map> addMember(String tripId, Map body) async => await call('POST', '/api/trips/$tripId/members', body) as Map;
  static Future bindCard(String uid, String memberId) => call('POST', '/api/cards/bind', {'uid': uid, 'memberId': memberId});
  static Future<Map> scanCard(String uid, {bool checkIn = true}) async =>
      await call('POST', '/api/cards/scan', {'uid': uid, 'checkIn': checkIn}) as Map;

  /// Live events for the trip: message, position, alert, member, checkin, trip.
  static Stream<Map<String, dynamic>> events(String tripId) {
    final uri = Uri.parse('${apiBase.replaceFirst('http', 'ws')}/ws?token=${_s.token}&trip=$tripId');
    final ch = WebSocketChannel.connect(uri);
    return ch.stream.map((m) => jsonDecode(m as String) as Map<String, dynamic>);
  }
}
