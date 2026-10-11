import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tunas/tunas.dart';

/// Cover colours for lists. Each pairs a soft ground with an ink that keeps
/// 4.5:1 contrast for the list's own text on that ground.
class ListTint {
  const ListTint(this.key, this.label, this.ground, this.ink, this.accent);
  final String key;
  final String label;
  final Color ground;
  final Color ink;
  final Color accent;

  static const all = [
    ListTint(
      'sage',
      'Daun',
      Color(0xFFE3EEE2),
      Color(0xFF234B38),
      Color(0xFF5E9E6E),
    ),
    ListTint(
      'apricot',
      'Aprikot',
      Color(0xFFFFE6D5),
      Color(0xFF8A3D21),
      Color(0xFFE8875E),
    ),
    ListTint(
      'sky',
      'Langit',
      Color(0xFFDDEBF4),
      Color(0xFF254A66),
      Color(0xFF5B8DB3),
    ),
    ListTint(
      'lilac',
      'Ungu muda',
      Color(0xFFEAE3F3),
      Color(0xFF4A3A66),
      Color(0xFF8B74B5),
    ),
    ListTint(
      'sun',
      'Kunyit',
      Color(0xFFFBEFC9),
      Color(0xFF6B4E0E),
      Color(0xFFD9A62B),
    ),
    ListTint(
      'clay',
      'Bata',
      Color(0xFFF3D8CA),
      Color(0xFF7A3018),
      Color(0xFFB85A35),
    ),
  ];

  static ListTint of(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => all.first);
}

class ListIcon {
  const ListIcon(this.key, this.label);
  final String key;
  final String label;

  static const all = [
    ListIcon('basket', 'Bakul'),
    ListIcon('market', 'Pasar'),
    ListIcon('cart', 'Troli'),
    ListIcon('kitchen', 'Dapur'),
    ListIcon('home', 'Rumah'),
    ListIcon('baby', 'Anak'),
    ListIcon('pill', 'Obat'),
    ListIcon('gift', 'Hadiah'),
    ListIcon('note', 'Catatan'),
  ];
}

/// A list's cover glyph, drawn in the same flat, rounded hand as Tunas.
class ListCoverIcon extends StatelessWidget {
  const ListCoverIcon({
    super.key,
    required this.icon,
    required this.tint,
    this.size = 52,
  });
  final String icon;
  final ListTint tint;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint.ground,
      borderRadius: BorderRadius.circular(size * .32),
    ),
    padding: EdgeInsets.all(size * .16),
    child: CustomPaint(painter: _GlyphPainter(icon, tint)),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.icon, this.tint);
  final String icon;
  final ListTint tint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = tint.accent;
    final ink = Paint()
      ..color = tint.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final leaf = Paint()..color = TunasColors.leaf;
    switch (icon) {
      case 'market':
        // Awning stall with a striped canopy.
        canvas.drawRRect(
          RRect.fromLTRBR(4, 11, 20, 21, const Radius.circular(1.5)),
          Paint()..color = tint.accent.withValues(alpha: .35),
        );
        for (var i = 0; i < 4; i++) {
          final path = Path()
            ..moveTo(2 + i * 5.0, 6)
            ..lineTo(7 + i * 5.0, 6)
            ..lineTo(7 + i * 5.0, 10)
            ..arcToPoint(
              Offset(2 + i * 5.0, 10),
              radius: const Radius.circular(2.5),
            )
            ..close();
          canvas.drawPath(
            path,
            i.isEven ? fill : (Paint()..color = Colors.white),
          );
        }
        canvas.drawLine(const Offset(2, 6), const Offset(22, 6), ink);
        canvas.drawCircle(const Offset(9, 16.5), 2, leaf);
        canvas.drawCircle(
          const Offset(14.5, 16.5),
          2,
          Paint()..color = TunasColors.petalCore,
        );
      case 'cart':
        final cart = Path()
          ..moveTo(2, 4)
          ..lineTo(5, 4)
          ..lineTo(7.5, 15)
          ..lineTo(18.5, 15)
          ..lineTo(20.5, 7.5)
          ..lineTo(6, 7.5);
        canvas.drawPath(cart, ink);
        canvas.drawCircle(const Offset(9, 19), 1.8, Paint()..color = tint.ink);
        canvas.drawCircle(const Offset(17, 19), 1.8, Paint()..color = tint.ink);
        canvas.drawCircle(const Offset(11, 10.5), 2.2, fill);
        canvas.drawCircle(const Offset(15.5, 11), 2, leaf);
      case 'kitchen':
        // A pot with steam.
        canvas.drawRRect(
          RRect.fromLTRBR(4, 10, 20, 20, const Radius.circular(3)),
          fill,
        );
        canvas.drawLine(const Offset(2, 12), const Offset(4, 12), ink);
        canvas.drawLine(const Offset(20, 12), const Offset(22, 12), ink);
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), ink);
        for (final x in [9.0, 15.0]) {
          final steam = Path()
            ..moveTo(x, 7)
            ..quadraticBezierTo(x - 1.5, 5, x, 3.5)
            ..quadraticBezierTo(x + 1.5, 2, x, 1);
          canvas.drawPath(steam, ink..strokeWidth = 1.4);
        }
      case 'home':
        final roof = Path()
          ..moveTo(3, 11)
          ..lineTo(12, 3.5)
          ..lineTo(21, 11);
        canvas.drawRRect(
          RRect.fromLTRBR(5.5, 10, 18.5, 21, const Radius.circular(1.5)),
          fill,
        );
        canvas.drawPath(roof, ink..strokeWidth = 2);
        canvas.drawRRect(
          RRect.fromLTRBR(10, 14, 14, 21, const Radius.circular(1)),
          Paint()..color = Colors.white,
        );
      case 'baby':
        // A bottle.
        canvas.drawRRect(
          RRect.fromLTRBR(7, 9, 17, 22, const Radius.circular(3)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(8, 6.5, 16, 9.5, const Radius.circular(1)),
          Paint()..color = tint.ink,
        );
        final teat = Path()
          ..moveTo(9.5, 6.5)
          ..quadraticBezierTo(12, 0, 14.5, 6.5)
          ..close();
        canvas.drawPath(teat, Paint()..color = TunasColors.petal);
        for (final y in [13.0, 16.5]) {
          canvas.drawLine(
            Offset(7, y),
            Offset(10, y),
            Paint()
              ..color = Colors.white
              ..strokeWidth = 1.4,
          );
        }
      case 'pill':
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromLTRBR(-9, -4, 0, 4, const Radius.circular(4)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(0, -4, 9, 4, const Radius.circular(4)),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(-9, -4, 9, 4, const Radius.circular(4)),
          ink,
        );
        canvas.restore();
      case 'gift':
        canvas.drawRRect(
          RRect.fromLTRBR(4, 10, 20, 21, const Radius.circular(2)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(3, 7, 21, 11, const Radius.circular(1.5)),
          Paint()..color = tint.ink,
        );
        canvas.drawRect(
          const Rect.fromLTRB(11, 7, 13, 21),
          Paint()..color = Colors.white,
        );
        final bow = Path()
          ..moveTo(12, 7)
          ..quadraticBezierTo(6, 1, 7.5, 6)
          ..moveTo(12, 7)
          ..quadraticBezierTo(18, 1, 16.5, 6);
        canvas.drawPath(bow, ink);
      case 'note':
        canvas.drawRRect(
          RRect.fromLTRBR(5, 3, 19, 21, const Radius.circular(2.5)),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(5, 3, 19, 21, const Radius.circular(2.5)),
          ink,
        );
        for (final y in [8.0, 12.0, 16.0]) {
          canvas.drawLine(
            Offset(8.5, y),
            Offset(y == 16 ? 12.5 : 15.5, y),
            ink..strokeWidth = 1.5,
          );
        }
        final sprout = Path()
          ..moveTo(17, 17)
          ..quadraticBezierTo(18, 13, 21.5, 13)
          ..quadraticBezierTo(21, 17, 17, 17)
          ..close();
        canvas.drawPath(sprout, leaf);
      default:
        // basket: the bakul Tunas lives in, with greens poking out.
        final greens = Path()
          ..moveTo(8, 10)
          ..quadraticBezierTo(6, 3, 10.5, 2.5)
          ..quadraticBezierTo(11, 7, 8, 10)
          ..moveTo(13, 10)
          ..quadraticBezierTo(15, 3.5, 19, 4.5)
          ..quadraticBezierTo(17.5, 9, 13, 10);
        canvas.drawPath(greens, leaf);
        canvas.drawCircle(
          const Offset(12, 9),
          2.4,
          Paint()..color = TunasColors.petalCore,
        );
        final body = Path()
          ..moveTo(2.5, 10)
          ..lineTo(21.5, 10)
          ..lineTo(19, 21)
          ..quadraticBezierTo(12, 22.5, 5, 21)
          ..close();
        canvas.drawPath(body, fill);
        final weave = Paint()
          ..color = tint.ink.withValues(alpha: .55)
          ..strokeWidth = 1.1;
        canvas.drawLine(const Offset(4, 14), const Offset(20, 14), weave);
        canvas.drawLine(const Offset(5, 17.5), const Offset(19, 17.5), weave);
        canvas.drawRRect(
          RRect.fromLTRBR(1.5, 9, 22.5, 11.5, const Radius.circular(1.2)),
          Paint()..color = tint.ink,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.icon != icon || old.tint != tint;
}

/// The circular "x of y bought" ring on list cards.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.done,
    required this.total,
    required this.tint,
    this.size = 46,
  });
  final int done;
  final int total;
  final ListTint tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 0.0 : done / total;
    return Semantics(
      label: '$done dari $total sudah dibeli',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(animated, tint),
            child: Center(
              child: ExcludeSemantics(
                child: total > 0 && done == total
                    ? Icon(
                        Icons.check_rounded,
                        color: tint.ink,
                        size: size * .45,
                      )
                    : Text(
                        '$done/$total',
                        style: TextStyle(
                          color: tint.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: size * .26,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.tint);
  final double value;
  final ListTint tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3.5);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        Paint()
          ..color = tint.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.tint != tint;
}
