import 'package:flutter/material.dart';
import '../theme.dart';
import 'home.dart';

const _factor = {'toddler': .2, 'child': .4, 'teen': .8, 'adult': 1.0, 'senior': .5, 'special': .2};

class MembersTab extends StatefulWidget {
  final TripState state;
  const MembersTab(this.state, {super.key});
  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final people = s.members.where((m) => m['care_group'] != 'guide').toList();
    final shown = people.where((m) => filter == 'all' || m['care_group'] == filter).toList()
      ..sort((a, b) {
        int rank(Map m) => m['fence_state'] == 'in' ? 1 : 0;
        return rank(a).compareTo(rank(b));
      });
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          _chip('all', 'ทั้งหมด ${people.length}', Brand.red),
          for (final g in CareGroup.all) _chip(g.key, '${g.label} ${people.where((m) => m['care_group'] == g.key).length}', g.color),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? const Center(child: Text('ไม่มีสมาชิกในกลุ่มนี้'))
            : ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = shown[i];
                  final g = CareGroup.of(m['care_group']);
                  final limit = ((s.radius * (_factor[g.key] ?? 1)) / 10).round() * 10;
                  final state = m['fence_state'];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: g.color.withOpacity(.15), child: Text(m['name'][0], style: TextStyle(color: g.color))),
                    title: Row(children: [
                      Flexible(child: Text(m['name'], overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(border: Border.all(color: g.color), borderRadius: BorderRadius.circular(8)),
                        child: Text(g.label, style: TextStyle(fontSize: 11, color: g.color)),
                      ),
                    ]),
                    subtitle: Text('${m['device'] == 'tag' ? 'Tag Card' : 'มือถือ'} · ขีดจำกัด $limit ม.'
                        '${m['checked_in_at'] != null ? ' · ✓ ขึ้นรถแล้ว' : ''}'),
                    trailing: Chip(
                      label: Text({'out': 'ออกนอก', 'lost': 'สัญญาณหาย'}[state] ?? 'ในพื้นที่'),
                      backgroundColor: state == 'in' ? Brand.ok.withOpacity(.12) : Brand.alert.withOpacity(.15),
                      labelStyle: TextStyle(color: state == 'in' ? Brand.ok : Brand.alert, fontSize: 12),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _chip(String key, String label, Color c) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: filter == key, selectedColor: c.withOpacity(.2), onSelected: (_) => setState(() => filter = key)),
      );
}
