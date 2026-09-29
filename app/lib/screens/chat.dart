import 'package:flutter/material.dart';
import '../api.dart';
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

  bool mine(Map m) {
    final s = Session.instance;
    return s.isGuide ? m['sender_kind'] == 'staff' : m['sender_id'] == s.memberId;
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    try {
      await Api.send(widget.state.id, t);
    } catch (_) {
      input.text = t;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งไม่สำเร็จ ลองอีกครั้ง')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.state.messages.reversed.toList();
    return Column(children: [
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            if (m['sender_kind'] == 'system') return _SystemNote(m);
            final me = mine(m);
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
                  Text(m['body'], style: TextStyle(color: me ? Colors.white : null)),
                ]),
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(children: [
            Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'พิมพ์ข้อความ…'))),
            IconButton(onPressed: send, icon: const Icon(Icons.send, color: Brand.red)),
          ]),
        ),
      ),
    ]);
  }
}

class _SystemNote extends StatelessWidget {
  final Map m;
  const _SystemNote(this.m);
  @override
  Widget build(BuildContext context) {
    final kind = (m['meta'] ?? {})['alert'];
    final good = kind == 'back' || kind == null;
    final c = good ? Brand.ok : Brand.alert;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: .1), border: Border.all(color: c), borderRadius: BorderRadius.circular(12)),
      child: Text(m['body'], style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
