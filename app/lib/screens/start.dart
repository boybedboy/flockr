import 'package:flutter/material.dart';
import '../api.dart';
import '../languages.dart';
import '../theme.dart';
import 'home.dart';

/// First screen: tourists join with a code, guides log in.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool guide = false, busy = false, consent = false;
  String? error;
  String careGroup = 'adult';
  String lang = 'th';
  final code = TextEditingController(), name = TextEditingController(), phone = TextEditingController();
  final email = TextEditingController(), password = TextEditingController();

  Future<void> run(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } on ApiError catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void goHome() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));

  Future<void> joinTrip() => run(() async {
        if (!consent) throw ApiError(400, 'ต้องยินยอมให้แชร์ตำแหน่งก่อนเข้าร่วม');
        await Api.join({
          'code': code.text.trim(),
          'name': name.text.trim(),
          'careGroup': careGroup,
          'language': lang,
          'emergencyPhone': phone.text.trim(),
          'consent': true,
        });
        goHome();
      });

  Future<void> guideLogin() => run(() async {
        await Api.login(email.text.trim(), password.text);
        final trips = await Api.trips();
        if (trips.isEmpty) throw ApiError(404, 'ยังไม่มีทริป สร้างทริปจากเว็บหลังบ้านก่อน');
        if (!mounted) return;
        final picked = await showModalBottomSheet<Map>(
          context: context,
          builder: (_) => ListView(children: [
            for (final t in trips)
              ListTile(
                title: Text(t['name']),
                subtitle: Text('รหัสเข้าร่วม ${t['join_code']} · ${t['members']} คน'),
                onTap: () => Navigator.pop(context, t),
              ),
          ]),
        );
        if (picked == null) return;
        Session.instance.tripId = picked['id'];
        await Session.instance.save();
        goHome();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(16)),
              child: const FlockrMark(size: 36),
            ),
            const SizedBox(width: 12),
            Text('Flockr', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Brand.redDark)),
          ]),
          const SizedBox(height: 4),
          const Text('ไปเป็นฝูง กลับครบฝูง'),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('ลูกทัวร์')), ButtonSegment(value: true, label: Text('ไกด์'))],
            selected: {guide},
            onSelectionChanged: (v) => setState(() => guide = v.first),
          ),
          const SizedBox(height: 20),
          if (!guide) ...[
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'รหัสเข้าร่วมทริป (6 ตัว)')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อ')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: lang,
              decoration: const InputDecoration(labelText: 'ภาษาที่อ่านแชท / Chat language'),
              items: [for (final l in Lang.all) DropdownMenuItem(value: l.code, child: Text('${l.flag}  ${l.name}'))],
              onChanged: (v) => setState(() => lang = v ?? 'th'),
            ),
            const SizedBox(height: 12),
            const Text('กลุ่มการดูแล'),
            Wrap(spacing: 6, children: [
              for (final g in CareGroup.all)
                ChoiceChip(
                  label: Text(g.label),
                  selected: careGroup == g.key,
                  selectedColor: g.color.withValues(alpha: .2),
                  onSelected: (_) => setState(() => careGroup = g.key),
                ),
            ]),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'เบอร์ติดต่อฉุกเฉิน')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              title: const Text('ยินยอมให้แชร์ตำแหน่งกับไกด์ระหว่างทริป ข้อมูลจะถูกลบภายใน 30 วันหลังจบทริป'),
            ),
            FilledButton(onPressed: busy ? null : joinTrip, child: const Text('เข้าร่วมทริป')),
          ] else ...[
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'อีเมล')),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่าน')),
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : guideLogin, child: const Text('เข้าสู่ระบบ')),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Brand.alert))),
        ]),
      ),
    );
  }
}
