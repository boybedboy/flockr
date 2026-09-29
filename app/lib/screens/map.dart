import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../theme.dart';
import 'home.dart';

// Same fractions as the server (src/geo.js).
const _factor = {'toddler': .2, 'child': .4, 'teen': .8, 'adult': 1.0, 'senior': .5, 'special': .2};

class MapTab extends StatefulWidget {
  final TripState state;
  const MapTab(this.state, {super.key});
  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  double? draftRadius;

  LatLng? get center {
    final t = widget.state.trip;
    if (t['center_mode'] == 'fixed' && t['fixed_lat'] != null) return LatLng((t['fixed_lat'] as num).toDouble(), (t['fixed_lng'] as num).toDouble());
    final g = widget.state.members.where((m) => m['care_group'] == 'guide' && m['lat'] != null).firstOrNull;
    return g == null ? null : LatLng((g['lat'] as num).toDouble(), (g['lng'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = center;
    final r = draftRadius ?? s.radius.toDouble();
    final located = s.members.where((m) => m['lat'] != null).toList();
    return Column(children: [
      Expanded(
        child: FlutterMap(
          options: MapOptions(initialCenter: c ?? const LatLng(13.7563, 100.5018), initialZoom: c == null ? 6 : 16),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'app.flockr'),
            if (c != null)
              CircleLayer(circles: [
                CircleMarker(point: c, radius: r, useRadiusInMeter: true, color: Brand.red.withOpacity(.10), borderColor: Brand.red, borderStrokeWidth: 2),
              ]),
            MarkerLayer(markers: [
              for (final m in located)
                Marker(
                  point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
                  width: 90,
                  height: 46,
                  child: _Pin(m),
                ),
            ]),
          ],
        ),
      ),
      if (Session.instance.isGuide)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('รัศมีผู้ใหญ่ ${r.round()} ม. · กลุ่มอื่นคิดตามสัดส่วน', style: Theme.of(context).textTheme.labelLarge),
            Slider(
              min: 50,
              max: 1000,
              divisions: 19,
              value: r.clamp(50, 1000),
              onChanged: (v) => setState(() => draftRadius = v),
              onChangeEnd: (v) async {
                await Api.setRadius(s.id, v.round()).catchError((_) {});
                setState(() => draftRadius = null);
              },
            ),
            Wrap(spacing: 10, children: [
              for (final g in CareGroup.all)
                Text('● ${g.label} ${(r * _factor[g.key]! / 10).round() * 10}ม.', style: TextStyle(color: g.color, fontSize: 12)),
            ]),
          ]),
        ),
    ]);
  }
}

class _Pin extends StatelessWidget {
  final Map m;
  const _Pin(this.m);
  @override
  Widget build(BuildContext context) {
    final g = CareGroup.of(m['care_group']);
    final out = m['fence_state'] != 'in' && m['care_group'] != 'guide';
    final col = out ? Brand.alert : g.color;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Text(m['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w600)),
      ),
      Container(
        width: out ? 18 : 14,
        height: out ? 18 : 14,
        decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      ),
    ]);
  }
}
