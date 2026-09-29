import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Flockr brand: "Tuk-Tuk" palette.
class Brand {
  static const red = Color(0xFFDC2626);
  static const redDark = Color(0xFFB91C1C);
  static const yellow = Color(0xFFFDE047);
  static const night = Color(0xFF2A0808);
  // semantic colours, deliberately not the brand red
  static const ok = Color(0xFF16A34A);
  static const alert = Color(0xFFEA580C);
}

/// Care groups — keys match the server (src/geo.js).
class CareGroup {
  final String key, label;
  final Color color;
  const CareGroup(this.key, this.label, this.color);

  static const all = [
    CareGroup('toddler', 'เด็กเล็ก', Color(0xFFE0679A)),
    CareGroup('child', 'เด็กโต', Color(0xFFD98E1F)),
    CareGroup('teen', 'วัยรุ่น', Color(0xFF3E7FD6)),
    CareGroup('adult', 'ผู้ใหญ่', Color(0xFF0B8577)),
    CareGroup('senior', 'ผู้สูงวัย', Color(0xFF8A63C9)),
    CareGroup('special', 'ดูแลพิเศษ', Color(0xFFC4412F)),
  ];
  static CareGroup of(String key) =>
      all.firstWhere((g) => g.key == key, orElse: () => const CareGroup('guide', 'ไกด์', Color(0xFF12282E)));
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: Brand.red, brightness: b, primary: Brand.red);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  return base.copyWith(
    textTheme: GoogleFonts.ibmPlexSansThaiTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(titleTextStyle: GoogleFonts.prompt(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface)),
  );
}

/// The flock-of-birds mark, drawn in code so it stays crisp at any size.
class FlockrMark extends StatelessWidget {
  final double size;
  final Color bird, accent;
  const FlockrMark({super.key, this.size = 28, this.bird = Colors.white, this.accent = Brand.yellow});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter(bird, accent));
}

class _MarkPainter extends CustomPainter {
  final Color bird, accent;
  _MarkPainter(this.bird, this.accent);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 100;
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void v(double x, double y, Paint paint) => c.drawPath(
        Path()
          ..moveTo(x * k, y * k)
          ..lineTo((x + 16) * k, (y + 12) * k)
          ..lineTo((x + 32) * k, y * k),
        paint);
    v(10, 40, p(bird));
    v(42, 26, p(bird));
    v(26, 70, p(bird.withOpacity(.6)));
    v(58, 60, p(accent));
  }

  @override
  bool shouldRepaint(covariant _MarkPainter o) => o.bird != bird || o.accent != accent;
}
