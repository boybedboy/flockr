import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../api.dart';
import '../theme.dart';
import 'home.dart';

/// Guide-only tab: register someone to a card, or tap a card to check them in.
class CardsTab extends StatefulWidget {
  final TripState state;
  const CardsTab(this.state, {super.key});
  @override
  State<CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<CardsTab> {
  bool registerMode = false, waiting = false, consent = false;
  String careGroup = 'child';
  String? status;
  Map? lastScan;
  final name = TextEditingController(), phone = TextEditingController(), medical = TextEditingController();

  @override
  void dispose() {
    NfcManager.instance.stopSession().catchError((_) {});
    super.dispose();
  }

  /// Chip UID as hex, e.g. 04A1B2C3D4E5F6.
  String? _uid(NfcTag tag) {
    final d = tag.data;
    for (final k in ['nfca', 'mifareultralight', 'mifare', 'iso7816', 'isodep']) {
      final id = (d[k] as Map?)?['identifier'];
      if (id is List) return id.map((b) => (b as int).toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    }
    return null;
  }

  Future<void> tap(Future<String> Function(String uid) onUid) async {
    if (!await NfcManager.instance.isAvailable()) {
      setState(() => status = 'เครื่องนี้ไม่มี NFC หรือยังไม่ได้เปิด NFC');
      return;
    }
    setState(() {
      waiting = true;
      status = 'แตะการ์ดที่ด้านหลังมือถือ…';
    });
    NfcManager.instance.startSession(onDiscovered: (tag) async {
      final uid = _uid(tag);
      await NfcManager.instance.stopSession();
      String msg;
      try {
        msg = uid == null ? 'อ่านการ์ดไม่ได้ ลองแตะอีกครั้ง' : await onUid(uid);
      } on ApiError catch (e) {
        msg = e.message;
      } catch (_) {
        msg = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้';
      }
      if (mounted) {
        setState(() {
          waiting = false;
          status = msg;
        });
      }
    });
  }

  Future<void> register() {
    if (name.text.trim().isEmpty || !consent) {
      setState(() => status = 'กรอกชื่อ และติ๊กว่าผู้ปกครองยินยอมก่อน');
      return Future.value();
    }
    return tap((uid) async {
      final m = await Api.addMember(widget.state.id, {
        'name': name.text.trim(),
        'careGroup': careGroup,
        'emergencyPhone': phone.text.trim(),
        'medicalNote': medical.text.trim(),
        'consent': true,
      });
      await Api.bindCard(uid, m['id']);
      name.clear();
      phone.clear();
      medical.clear();
      return '✓ ผูกการ์ด $uid กับ ${m['name']} แล้ว';
    });
  }

  Future<void> scan() => tap((uid) async {
        final r = await Api.scanCard(uid);
        setState(() => lastScan = r);
        return '✓ ${r['name']} ขึ้นรถแล้ว';
      });

  @override
  Widget build(BuildContext context) {
    final people = widget.state.members.where((m) => m['care_group'] != 'guide');
    final inBus = people.where((m) => m['checked_in_at'] != null).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('สแกน / เช็กชื่อ')), ButtonSegment(value: true, label: Text('ลงทะเบียนการ์ด'))],
        selected: {registerMode},
        onSelectionChanged: (v) => setState(() {
          registerMode = v.first;
          status = null;
        }),
      ),
      const SizedBox(height: 16),
      if (!registerMode) ...[
        Card(
          color: Brand.red,
          child: ListTile(
            title: Text('ขึ้นรถแล้ว $inBus/${people.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: FilledButton.tonal(onPressed: waiting ? null : scan, child: const Text('สแกนการ์ด')),
          ),
        ),
        if (lastScan != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lastScan!['name'], style: Theme.of(context).textTheme.titleMedium),
                Text('กลุ่ม: ${CareGroup.of(lastScan!['care_group']).label}'),
                if (lastScan!['emergency_phone'] != null) Text('ผู้ติดต่อ: ${lastScan!['emergency_phone']}'),
                if ((lastScan!['medical_note'] ?? '').isNotEmpty) Text('หมายเหตุสุขภาพ: ${lastScan!['medical_note']}', style: const TextStyle(color: Brand.alert)),
              ]),
            ),
          ),
      ] else ...[
        TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล')),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final g in CareGroup.all)
            ChoiceChip(label: Text(g.label), selected: careGroup == g.key, selectedColor: g.color.withValues(alpha: .2), onSelected: (_) => setState(() => careGroup = g.key)),
        ]),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'เบอร์ผู้ปกครอง / ผู้ติดต่อฉุกเฉิน')),
        TextField(controller: medical, decoration: const InputDecoration(labelText: 'แพ้ยา / โรคประจำตัว')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: (v) => setState(() => consent = v ?? false),
          title: const Text('ผู้ปกครองยินยอมให้เก็บตำแหน่งและข้อมูลสุขภาพ (PDPA)'),
        ),
        FilledButton.icon(onPressed: waiting ? null : register, icon: const Icon(Icons.contactless), label: const Text('แตะการ์ดเพื่อผูก')),
      ],
      if (status != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(status!, textAlign: TextAlign.center)),
    ]);
  }
}
