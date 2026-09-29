import 'package:flutter/material.dart';
import '../api.dart';
import '../languages.dart';
import '../theme.dart';
import 'home.dart';

class ChatTab extends StatefulWidget {
  final TripState state;
  const ChatTab(this.state, {super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final input = TextEditingController();
  // language the next message is sent in; starts as the reader's own language
  String sendLang = Session.instance.lang;
  final showOriginal = <dynamic>{};

  bool mine(Map m) {
    final s = Session.instance;
    return s.isGuide ? m['sender_kind'] == 'staff' : m['sender_id'] == s.memberId;
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    try {
      await Api.send(widget.state.id, t, sendLang);
    } catch (_) {
      input.text = t;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งไม่สำเร็จ ลองอีกครั้ง')));
    }
  }

  /// Text to show this reader, and the source language when it is a translation.
  (String, String?) textFor(Map m) {
    final read = Session.instance.lang;
    final tr = (m['translations'] as Map?)?[read];
    if (m['lang'] == read || tr == null || showOriginal.contains(m['id'])) return (m['body'], null);
    return (tr as String, m['lang'] as String?);
  }

  Widget translatedNote(Map m, String from, Color? color) => GestureDetector(
        onTap: () => setState(() => showOriginal.contains(m['id']) ? showOriginal.remove(m['id']) : showOriginal.add(m['id'])),
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('แปลจาก ${Lang.of(from).name} · ดูต้นฉบับ', style: TextStyle(fontSize: 11, color: color, decoration: TextDecoration.underline)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final msgs = widget.state.messages.reversed.toList();
    final sl = Lang.of(sendLang);
    return Column(children: [
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            if (m['sender_kind'] == 'system') return _SystemNote(m, textFor(m).$1);
            final me = mine(m);
            final (text, from) = textFor(m);
            final fg = me ? Colors.white : null;
            return Align(
              alignment: me ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 280),
                decoration: BoxDecoration(
                  color: me ? Brand.red : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!me) Text(m['sender_name'] ?? '', style: Theme.of(context).textTheme.labelSmall),
                  Text(text, style: TextStyle(color: fg)),
                  if (from != null) translatedNote(m, from, me ? Colors.white70 : null),
                  if (from == null && showOriginal.contains(m['id']))
                    GestureDetector(
                      onTap: () => setState(() => showOriginal.remove(m['id'])),
                      child: Text('ดูคำแปล', style: TextStyle(fontSize: 11, color: me ? Colors.white70 : null, decoration: TextDecoration.underline)),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(children: [
            PopupMenuButton<String>(
              tooltip: 'ภาษาที่ส่ง',
              initialValue: sendLang,
              onSelected: (v) => setState(() => sendLang = v),
              itemBuilder: (_) => [for (final l in Lang.all) PopupMenuItem(value: l.code, child: Text('${l.flag}  ${l.name}'))],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: Brand.red), borderRadius: BorderRadius.circular(18)),
                child: Text('${sl.flag} ${sl.code.toUpperCase()} ▾', style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: 'พิมพ์ข้อความ (${sl.name})…'))),
            IconButton(onPressed: send, icon: const Icon(Icons.send, color: Brand.red)),
          ]),
        ),
      ),
    ]);
  }
}

class _SystemNote extends StatelessWidget {
  final Map m;
  final String text;
  const _SystemNote(this.m, this.text);
  @override
  Widget build(BuildContext context) {
    final kind = (m['meta'] ?? {})['alert'];
    final good = kind == 'back' || kind == null;
    final c = good ? Brand.ok : Brand.alert;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: .1), border: Border.all(color: c), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
