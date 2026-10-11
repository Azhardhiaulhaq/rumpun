import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tunas, Rumpun's sprout. It grows out of the brand's branch-and-leaf mark:
/// a stem with two leaf arms, a round seed head, and a face.
///
/// Drawn in code so it stays crisp at any size and can move with the app's
/// own state instead of looping a canned clip.
enum TunasMood {
  /// Gentle sway and occasional blink. Default for empty states.
  idle,

  /// A single hop, played when something is added.
  hop,

  /// Leaf arms wave, played when something is ticked off.
  wave,

  /// The head opens into a blossom with falling leaves. A finished list.
  bloom,

  /// Head tilted, eyes looking sideways. Something went wrong.
  puzzled,

  /// Eyes closed, slow breathing. Loading.
  sleepy,
}

class TunasColors {
  static const stem = Color(0xFF3D7A55);
  static const leaf = Color(0xFF5E9E6E);
  static const leafDark = Color(0xFF234B38);
  static const head = Color(0xFF8CC08F);
  static const cheek = Color(0xFFF2A68A);
  static const face = Color(0xFF20251F);
  static const petal = Color(0xFFFFC9A8);
  static const petalCore = Color(0xFFE8875E);
  static const basket = Color(0xFFC98E5A);
  static const basketDark = Color(0xFF9C6638);
}

/// Set by tests so the idle loop does not keep `pumpAndSettle` waiting.
/// Reactions still play; only the endless sway and blink are paused.
bool tunasIdleMotion = true;

class Tunas extends StatefulWidget {
  const Tunas({
    super.key,
    this.size = 120,
    this.mood = TunasMood.idle,
    this.inBasket = false,
    this.semanticLabel,
  });

  final double size;
  final TunasMood mood;

  /// Peeks out of a woven bakul, used on the lists screens.
  final bool inBasket;
  final String? semanticLabel;

  @override
  State<Tunas> createState() => TunasState();
}

class TunasState extends State<Tunas> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final AnimationController _action = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  TunasMood _playing = TunasMood.idle;
  bool _reduced = false;
  final _random = math.Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced || !tunasIdleMotion) {
      _idle.stop();
      _blinkTimer?.cancel();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
      _scheduleBlink();
    }
  }

  @override
  void initState() {
    super.initState();
    _playing = widget.mood;
    if (_isAction(widget.mood)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => play(widget.mood));
    }
  }

  @override
  void didUpdateWidget(Tunas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      if (_isAction(widget.mood)) {
        play(widget.mood);
      } else {
        setState(() => _playing = widget.mood);
      }
    }
  }

  bool _isAction(TunasMood mood) =>
      mood == TunasMood.hop ||
      mood == TunasMood.wave ||
      mood == TunasMood.bloom;

  /// Plays a one-off reaction. Bloom holds its final frame.
  void play(TunasMood mood) {
    if (!mounted) return;
    setState(() => _playing = mood);
    if (_reduced) {
      _action.value = mood == TunasMood.bloom ? 1 : 0;
      return;
    }
    _action.duration = mood == TunasMood.bloom
        ? const Duration(milliseconds: 1600)
        : const Duration(milliseconds: 900);
    _action.forward(from: 0);
  }

  Timer? _blinkTimer;

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    if (!mounted || _reduced) return;
    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + _random.nextInt(2600)),
      () async {
        if (!mounted || _reduced) return;
        await _blink.forward(from: 0);
        if (!mounted) return;
        await _blink.reverse();
        _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _idle.dispose();
    _action.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _action, _blink]),
          builder: (context, _) => CustomPaint(
            painter: _TunasPainter(
              mood: _playing,
              idle: _idle.value,
              action: _action.value,
              blink: _blink.value,
              inBasket: widget.inBasket,
            ),
          ),
        ),
      ),
    );
  }
}

class _TunasPainter extends CustomPainter {
  _TunasPainter({
    required this.mood,
    required this.idle,
    required this.action,
    required this.blink,
    required this.inBasket,
  });

  final TunasMood mood;
  final double idle;
  final double action;
  final double blink;
  final bool inBasket;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw on a 100x100 grid and scale, so proportions stay deliberate.
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final wave = math.sin(idle * 2 * math.pi);
    var sway = wave * 0.035;
    var lift = 0.0;
    var squash = 1.0;
    var armLeft = 0.0;
    var armRight = 0.0;
    var tilt = 0.0;
    var bloom = 0.0;
    var eyeShift = 0.0;
    var eyesClosed = blink;
    var smile = 1.0;

    switch (mood) {
      case TunasMood.hop:
        final t = action;
        // Crouch, jump, land with a little squash.
        if (t < .18) {
          squash = 1 - .14 * (t / .18);
        } else if (t < .7) {
          final p = (t - .18) / .52;
          lift = math.sin(p * math.pi) * 16;
          squash = 1.06;
          armLeft = armRight = .6 * math.sin(p * math.pi);
        } else {
          final p = (t - .7) / .3;
          squash = 1 - .1 * math.sin(p * math.pi);
        }
        smile = 1.3;
      case TunasMood.wave:
        final t = action;
        armRight =
            1.1 * math.sin(t * math.pi) +
            0.4 * math.sin(t * 6 * math.pi) * math.sin(t * math.pi);
        armLeft = 0.15 * math.sin(t * math.pi);
        tilt = 0.06 * math.sin(t * math.pi);
        smile = 1.3;
      case TunasMood.bloom:
        bloom = Curves.easeOutBack.transform(action.clamp(0, 1)).toDouble();
        armLeft = armRight = 0.9 * Curves.easeOut.transform(action);
        lift = 4 * math.sin(math.min(action * 2, 1) * math.pi);
        smile = 1.5;
        eyesClosed = action > .25 ? 1 : blink;
      case TunasMood.puzzled:
        tilt = -0.16;
        eyeShift = 2.2;
        smile = -0.4;
        sway *= .4;
      case TunasMood.sleepy:
        eyesClosed = 1;
        sway = wave * 0.015;
        squash = 1 + 0.025 * wave;
        smile = 0.4;
      case TunasMood.idle:
        break;
    }

    final groundY = inBasket ? 80.0 : 92.0;

    if (inBasket) _basketBack(canvas);

    if (!inBasket) {
      final shadow = Paint()..color = const Color(0x1A234B38);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(50, groundY + 2),
          width: 34 - lift * .8,
          height: 6,
        ),
        shadow,
      );
    }

    canvas.save();
    canvas.translate(50, groundY - lift);
    canvas.rotate(sway + tilt);
    canvas.scale(1 / squash.clamp(.85, 1.15), squash);

    _stem(canvas);
    _arm(canvas, left: true, raise: armLeft);
    _arm(canvas, left: false, raise: armRight);
    _head(canvas, bloom: bloom);
    _face(
      canvas,
      closed: eyesClosed,
      shift: eyeShift,
      smile: smile,
      sleepy: mood == TunasMood.sleepy,
    );
    if (mood == TunasMood.puzzled) _questionMark(canvas);
    if (mood == TunasMood.sleepy) _zz(canvas, wave);

    canvas.restore();

    if (inBasket) _basketFront(canvas);
    if (mood == TunasMood.bloom && action > .2) _fallingLeaves(canvas, action);

    canvas.restore();
  }

  // Coordinates below are relative to the stem base at (0, 0), y grows down.

  void _stem(Canvas canvas) {
    final paint = Paint()
      ..color = TunasColors.stem
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(-2, -12, 2, -22, 0, -34);
    canvas.drawPath(path, paint);
  }

  void _arm(Canvas canvas, {required bool left, required double raise}) {
    final side = left ? -1.0 : 1.0;
    canvas.save();
    canvas.translate(0, -17);
    canvas.rotate(-side * (-0.2 + raise + 0.05 * math.sin(idle * 2 * math.pi)));
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(side * 9, -9, side * 19, -3)
      ..quadraticBezierTo(side * 10, 5, 0, 0)
      ..close();
    canvas.drawPath(leaf, Paint()..color = TunasColors.leaf);
    canvas.drawLine(
      Offset.zero,
      Offset(side * 14, -3),
      Paint()
        ..color = TunasColors.leafDark.withValues(alpha: .35)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _head(Canvas canvas, {required double bloom}) {
    const center = Offset(0, -50);
    if (bloom > 0) {
      final petal = Paint()..color = TunasColors.petal;
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3 + .3;
        final distance = 20 * bloom;
        canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * distance,
          10 * bloom,
          petal,
        );
      }
    }
    // The seed head: a soft rounded shape, slightly wider than tall.
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 46, height: 40),
      Paint()..color = TunasColors.head,
    );
    // The sprout tip: one curled leaf on top, the brand's leaf node.
    final tip = Path()
      ..moveTo(0, -69)
      ..quadraticBezierTo(4, -82, 15, -81)
      ..quadraticBezierTo(12, -70, 0, -69)
      ..close();
    canvas.drawPath(tip, Paint()..color = TunasColors.leaf);
    canvas.drawLine(
      const Offset(0, -69),
      const Offset(0, -74),
      Paint()
        ..color = TunasColors.stem
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    if (bloom > .6) {
      canvas.drawCircle(
        center + const Offset(0, -27),
        4 * bloom,
        Paint()..color = TunasColors.petalCore,
      );
    }
  }

  void _face(
    Canvas canvas, {
    required double closed,
    required double shift,
    required double smile,
    required bool sleepy,
  }) {
    final ink = Paint()
      ..color = TunasColors.face
      ..strokeCap = StrokeCap.round;
    for (final x in [-8.0, 8.0]) {
      final eye = Offset(x + shift, -52);
      if (closed > .5) {
        final arc = Path()
          ..moveTo(eye.dx - 3, eye.dy)
          ..quadraticBezierTo(
            eye.dx,
            eye.dy + (sleepy ? 1.5 : 2.5),
            eye.dx + 3,
            eye.dy,
          );
        canvas.drawPath(
          arc,
          Paint()
            ..color = TunasColors.face
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: eye, width: 5, height: 6.5 * (1 - closed)),
          ink,
        );
        canvas.drawCircle(
          eye + const Offset(-1, -1.5),
          1,
          Paint()..color = Colors.white,
        );
      }
    }
    final cheek = Paint()..color = TunasColors.cheek.withValues(alpha: .75);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-14, -45), width: 7, height: 4),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(14, -45), width: 7, height: 4),
      cheek,
    );
    final mouth = Path()
      ..moveTo(-3.5, -44.5)
      ..quadraticBezierTo(0, -44.5 + 3.2 * smile, 3.5, -44.5);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = TunasColors.face
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _questionMark(Canvas canvas) {
    final paint = Paint()
      ..color = TunasColors.leafDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(18, -76)
      ..quadraticBezierTo(18, -84, 25, -84)
      ..quadraticBezierTo(32, -84, 31, -77)
      ..quadraticBezierTo(30, -72, 25, -70);
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      const Offset(25, -64),
      1.6,
      Paint()..color = TunasColors.leafDark,
    );
  }

  void _zz(Canvas canvas, double wave) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: TunasColors.leafDark.withValues(alpha: .7),
          fontSize: 11 + wave * 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(20, -80 - wave * 3));
  }

  void _basketBack(Canvas canvas) {
    final back = Path()
      ..moveTo(18, 70)
      ..lineTo(82, 70)
      ..lineTo(82, 74)
      ..lineTo(18, 74)
      ..close();
    canvas.drawPath(back, Paint()..color = TunasColors.basketDark);
  }

  void _basketFront(Canvas canvas) {
    final body = Path()
      ..moveTo(14, 72)
      ..lineTo(86, 72)
      ..lineTo(78, 97)
      ..quadraticBezierTo(50, 101, 22, 97)
      ..close();
    canvas.drawPath(body, Paint()..color = TunasColors.basket);
    // Woven bands, the bakul's texture.
    final weave = Paint()
      ..color = TunasColors.basketDark
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final y in [80.0, 88.0]) {
      canvas.drawLine(
        Offset(17 + (y - 72) * .3, y),
        Offset(83 - (y - 72) * .3, y),
        weave,
      );
    }
    for (var x = 24.0; x <= 76; x += 8) {
      canvas.drawLine(
        Offset(x, 73),
        Offset(x + (x - 50) * -.08, 97),
        weave..strokeWidth = 1,
      );
    }
    final rim = RRect.fromRectAndRadius(
      const Rect.fromLTWH(11, 68, 78, 7),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(rim, Paint()..color = TunasColors.basketDark);
  }

  void _fallingLeaves(Canvas canvas, double t) {
    final p = ((t - .2) / .8).clamp(0.0, 1.0);
    const seeds = [
      (12.0, .0, .7),
      (30.0, .15, -.5),
      (70.0, .05, .9),
      (88.0, .25, -.8),
      (52.0, .35, .4),
    ];
    for (final (x, delay, spin) in seeds) {
      final local = ((p - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final opacity = (1 - local).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x + math.sin(local * 3 * math.pi) * 5, 8 + local * 70);
      canvas.rotate(spin * local * 4);
      final leaf = Path()
        ..moveTo(-5, 0)
        ..quadraticBezierTo(0, -5, 5, 0)
        ..quadraticBezierTo(0, 5, -5, 0)
        ..close();
      canvas.drawPath(
        leaf,
        Paint()
          ..color = (x > 50 ? TunasColors.petal : TunasColors.leaf).withValues(
            alpha: opacity,
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TunasPainter old) =>
      old.mood != mood ||
      old.idle != idle ||
      old.action != action ||
      old.blink != blink ||
      old.inBasket != inBasket;
}
