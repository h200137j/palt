/// app_theme.dart — PALT's themes: tokens, type, surfaces and ThemeData.
///
/// Five looks, picked in Settings → Appearance:
///   - Beacon:    true black, signal amber, instrument mono (the original; see /design.md)
///   - Material:  Material 3 Expressive, wallpaper colours, light or dark
///   - Aurora:    frosted glass over a drifting violet/teal mesh
///   - Paper:     warm newsprint, serif headlines, ink and vermilion
///   - Pop:       neo-brutalist: thick ink outlines, hard shadows, loud colour
///
/// Widgets read the live theme through the k* getters and the helpers below
/// (display/mono/overline, paltDeco, rad). Switching rebuilds the whole tree
/// (see PaltApp), so nothing caches a colour.
library;

import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PaltStyle { beacon, material, aurora, paper, pop }

class PaltTheme {
  final PaltStyle style;
  final String name;
  final String tagline;
  final Brightness brightness;

  final Color bg, surface, surfaceRaised, hairline;
  final Color text, textSecondary, textFaint;
  final Color accent, accentPressed, onAccent;

  /// A quiet accent fill (tonal containers) and the text on it.
  final Color accentSoft, onAccentSoft;
  final Color ok, danger, relay;

  /// Action tiles, received bubbles; sent bubbles and their text and meta.
  final Color tile, sent, onSent, sentMeta;

  /// The computer's commands (Lock, Suspend…), apart from the accent.
  final Color command;

  final Gradient cardGradient, tileGradient, accentGradient;
  final Gradient? pageGlow;

  final String displayFamily, bodyFamily, monoFamily;

  /// Serif display faces run small; single-weight faces ignore weights.
  final double displayScale;
  final FontWeight? displayWeight;

  /// Multiplies every corner radius.
  final double radiusScale;

  /// Pop: tile colours, used in turn.
  final List<Color> pops;

  /// Material: the full scheme.
  final ColorScheme? scheme;

  const PaltTheme({
    required this.style,
    required this.name,
    required this.tagline,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.text,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.ok,
    required this.danger,
    required this.relay,
    required this.tile,
    required this.sent,
    required this.onSent,
    required this.sentMeta,
    required this.command,
    required this.cardGradient,
    required this.tileGradient,
    required this.accentGradient,
    this.pageGlow,
    required this.displayFamily,
    required this.bodyFamily,
    required this.monoFamily,
    this.displayScale = 1,
    this.displayWeight,
    this.radiusScale = 1,
    this.pops = const [],
    this.scheme,
  });

  bool get dark => brightness == Brightness.dark;
}

LinearGradient _solid(Color c) => LinearGradient(colors: [c, c]);

// ── Beacon ───────────────────────────────────────────────────────────────────

const beaconTheme = PaltTheme(
  style: PaltStyle.beacon,
  name: 'Beacon',
  tagline: 'Black glass, signal amber',
  brightness: Brightness.dark,
  bg: Color(0xFF000000),
  surface: Color(0xFF111216),
  surfaceRaised: Color(0xFF1B1D23),
  hairline: Color(0xFF26282F),
  text: Color(0xFFF2F3F6),
  textSecondary: Color(0xFF9A9EA9),
  textFaint: Color(0xFF5C606B),
  accent: Color(0xFFFFB454),
  accentPressed: Color(0xFFE69A38),
  onAccent: Color(0xFF201503),
  accentSoft: Color(0xFF2A2116),
  onAccentSoft: Color(0xFFFFD9A6),
  ok: Color(0xFF53D993),
  danger: Color(0xFFFF7B72),
  relay: Color(0xFF7AA2FF),
  tile: Color(0xFF14151A),
  sent: Color(0xFF3A2B12),
  onSent: Color(0xFFFFE6C2),
  sentMeta: Color(0xFFC9A46A),
  command: Color(0xFF6EA8FF),
  cardGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A2116), Color(0xFF15161A), Color(0xFF0B0B0D)],
    stops: [0, 0.45, 1],
  ),
  tileGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C1E24), Color(0xFF111216)],
  ),
  accentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFCB7A), Color(0xFFFFA63D)],
  ),
  pageGlow: RadialGradient(
    center: Alignment(0, -1.15),
    radius: 1.1,
    colors: [Color(0x26FFB454), Color(0x00FFB454)],
  ),
  displayFamily: 'Bricolage Grotesque',
  bodyFamily: 'Inter',
  monoFamily: 'JetBrains Mono',
);

// ── Material 3 Expressive ────────────────────────────────────────────────────

PaltTheme materialTheme(ColorScheme cs) {
  final dark = cs.brightness == Brightness.dark;
  return PaltTheme(
    style: PaltStyle.material,
    name: 'Material',
    tagline: 'Material 3, in your wallpaper\'s colours',
    brightness: cs.brightness,
    bg: cs.surface,
    surface: cs.surfaceContainer,
    surfaceRaised: cs.surfaceContainerHigh,
    hairline: cs.outlineVariant,
    text: cs.onSurface,
    textSecondary: cs.onSurfaceVariant,
    textFaint: cs.outline,
    accent: cs.primary,
    accentPressed: Color.lerp(cs.primary, cs.onSurface, 0.15)!,
    onAccent: cs.onPrimary,
    accentSoft: cs.primaryContainer,
    onAccentSoft: cs.onPrimaryContainer,
    ok: dark ? const Color(0xFF6DD58C) : const Color(0xFF146C2E),
    danger: cs.error,
    relay: cs.tertiary,
    tile: cs.surfaceContainerHigh,
    sent: cs.primaryContainer,
    onSent: cs.onPrimaryContainer,
    sentMeta: cs.onPrimaryContainer.withValues(alpha: 0.7),
    command: cs.tertiary,
    cardGradient: _solid(cs.surfaceContainerHigh),
    tileGradient: _solid(cs.surfaceContainerHigh),
    accentGradient: _solid(cs.primary),
    displayFamily: 'Outfit',
    bodyFamily: 'Roboto',
    monoFamily: 'Roboto Mono',
    radiusScale: 1.3,
    scheme: cs,
  );
}

// ── Aurora ───────────────────────────────────────────────────────────────────

const auroraTheme = PaltTheme(
  style: PaltStyle.aurora,
  name: 'Aurora',
  tagline: 'Frosted glass over northern lights',
  brightness: Brightness.dark,
  bg: Color(0xFF080A1C),
  surface: Color(0x14FFFFFF),
  surfaceRaised: Color(0xFF181A35),
  hairline: Color(0x26FFFFFF),
  text: Color(0xFFF5F3FF),
  textSecondary: Color(0xFFB9B5DA),
  textFaint: Color(0xFF77739E),
  accent: Color(0xFFB79CFF),
  accentPressed: Color(0xFF9A7BFA),
  onAccent: Color(0xFF160A33),
  accentSoft: Color(0x33B79CFF),
  onAccentSoft: Color(0xFFE9E1FF),
  ok: Color(0xFF5EEAD4),
  danger: Color(0xFFFB7185),
  relay: Color(0xFF7DD3FC),
  tile: Color(0x17FFFFFF),
  sent: Color(0x4D8B5CF6),
  onSent: Color(0xFFF5F3FF),
  sentMeta: Color(0xFFCFC2FF),
  command: Color(0xFF7DD3FC),
  cardGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2EFFFFFF), Color(0x0DFFFFFF)],
  ),
  tileGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x21FFFFFF), Color(0x0AFFFFFF)],
  ),
  accentGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC4B5FD), Color(0xFFF0ABFC), Color(0xFF99F6E4)],
  ),
  displayFamily: 'Sora',
  bodyFamily: 'Manrope',
  monoFamily: 'JetBrains Mono',
  radiusScale: 1.15,
);

// ── Paper ────────────────────────────────────────────────────────────────────

const paperTheme = PaltTheme(
  style: PaltStyle.paper,
  name: 'Paper',
  tagline: 'Newsprint, serif and red ink',
  brightness: Brightness.light,
  bg: Color(0xFFF3EEE3),
  surface: Color(0xFFFBF8F1),
  surfaceRaised: Color(0xFFFFFDF8),
  hairline: Color(0xFFD9D0BF),
  text: Color(0xFF1D1B17),
  textSecondary: Color(0xFF5F584D),
  textFaint: Color(0xFF948C7E),
  accent: Color(0xFFC8442A),
  accentPressed: Color(0xFFA9361F),
  onAccent: Color(0xFFFFF8EE),
  accentSoft: Color(0xFFF6DCD2),
  onAccentSoft: Color(0xFF5E1A0B),
  ok: Color(0xFF2E7D4F),
  danger: Color(0xFFB3261E),
  relay: Color(0xFF2F5BB7),
  tile: Color(0xFFEDE6D7),
  sent: Color(0xFF1D1B17),
  onSent: Color(0xFFF3EEE3),
  sentMeta: Color(0xFFA9A08F),
  command: Color(0xFF1D1B17),
  cardGradient: LinearGradient(colors: [Color(0xFFFBF8F1), Color(0xFFFBF8F1)]),
  tileGradient: LinearGradient(colors: [Color(0xFFFBF8F1), Color(0xFFFBF8F1)]),
  accentGradient: LinearGradient(colors: [Color(0xFFC8442A), Color(0xFFC8442A)]),
  displayFamily: 'Instrument Serif',
  bodyFamily: 'DM Sans',
  monoFamily: 'IBM Plex Mono',
  displayScale: 1.22,
  displayWeight: FontWeight.w400,
  radiusScale: 0.3,
);

// ── Pop ──────────────────────────────────────────────────────────────────────

const popTheme = PaltTheme(
  style: PaltStyle.pop,
  name: 'Pop',
  tagline: 'Loud colour, thick lines, no apologies',
  brightness: Brightness.light,
  bg: Color(0xFFFFF1D0),
  surface: Color(0xFFFFFFFF),
  surfaceRaised: Color(0xFFFFFFFF),
  hairline: Color(0xFF111111),
  text: Color(0xFF111111),
  textSecondary: Color(0xFF3B3B3B),
  textFaint: Color(0xFF7A7568),
  accent: Color(0xFF2B50FF),
  accentPressed: Color(0xFF1C3BD6),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFFFD23F),
  onAccentSoft: Color(0xFF111111),
  ok: Color(0xFF0E9F4E),
  danger: Color(0xFFE5372E),
  relay: Color(0xFF7B4DFF),
  tile: Color(0xFFFFFFFF),
  sent: Color(0xFFFFD23F),
  onSent: Color(0xFF111111),
  sentMeta: Color(0xFF5A4A00),
  command: Color(0xFF111111),
  cardGradient: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)]),
  tileGradient: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)]),
  accentGradient: LinearGradient(colors: [Color(0xFF2B50FF), Color(0xFF2B50FF)]),
  displayFamily: 'Archivo Black',
  bodyFamily: 'Space Grotesk',
  monoFamily: 'Space Mono',
  displayScale: 0.92,
  displayWeight: FontWeight.w400,
  radiusScale: 0.55,
  pops: [Color(0xFFFFD23F), Color(0xFFFF8FB8), Color(0xFF7CE0B5), Color(0xFF8EC5FF), Color(0xFFC9A7FF)],
);

// ── The live theme ───────────────────────────────────────────────────────────

/// The theme in use. Set through [themeController], never directly.
PaltTheme palt = beaconTheme;

Color get kBg => palt.bg;
Color get kSurface => palt.surface;
Color get kSurfaceRaised => palt.surfaceRaised;
Color get kHairline => palt.hairline;
Color get kText => palt.text;
Color get kTextSecondary => palt.textSecondary;
Color get kTextFaint => palt.textFaint;
Color get kAccent => palt.accent;
Color get kAccentPressed => palt.accentPressed;
Color get kOnAccent => palt.onAccent;
Color get kAccentSoft => palt.accentSoft;
Color get kOnAccentSoft => palt.onAccentSoft;
Color get kOk => palt.ok;
Color get kDanger => palt.danger;

/// Route tag for peers/transfers going through the relay server.
Color get kRelay => palt.relay;

/// Action tiles and received bubbles.
Color get kTile => palt.tile;

/// Sent bubbles, with their text and meta.
Color get kSent => palt.sent;
Color get kOnSent => palt.onSent;
Color get kSentMeta => palt.sentMeta;

/// Hero cards.
Gradient get kCardGradient => palt.cardGradient;

/// Tiles and secondary surfaces.
Gradient get kTileGradient => palt.tileGradient;

/// Primary actions.
Gradient get kAccentGradient => palt.accentGradient;

/// A soft glow at the top of a page (Beacon only).
Gradient? get kPageGlow => palt.pageGlow;

bool get isMaterial => palt.style == PaltStyle.material;
bool get isAurora => palt.style == PaltStyle.aurora;
bool get isPaper => palt.style == PaltStyle.paper;
bool get isPop => palt.style == PaltStyle.pop;
bool get isBeacon => palt.style == PaltStyle.beacon;

/// A corner radius in the theme's shape language.
double rad(double r, [PaltTheme? t]) => r >= 999 ? r : r * (t ?? palt).radiusScale;

/// Pop: the n-th loud tile colour; other themes: [fallback].
Color popColor(int n, Color fallback) => isPop ? palt.pops[n % palt.pops.length] : fallback;

// ── Type helpers ─────────────────────────────────────────────────────────────

/// Display voice — device names, screen titles, the wordmark.
TextStyle display({
  double fontSize = 24,
  FontWeight fontWeight = FontWeight.w700,
  Color? color,
  double letterSpacing = -0.5,
  PaltTheme? theme,
}) {
  final t = theme ?? palt;
  final weight = t.displayWeight ??
      (t.style == PaltStyle.material
          ? (fontWeight.index >= FontWeight.w700.index ? FontWeight.w500 : FontWeight.w400)
          : fontWeight);
  return GoogleFonts.getFont(
    t.displayFamily,
    fontSize: fontSize * t.displayScale,
    fontWeight: weight,
    color: color ?? t.text,
    letterSpacing: switch (t.style) {
      PaltStyle.material => 0,
      PaltStyle.paper => -0.2,
      PaltStyle.pop => -0.3,
      _ => letterSpacing,
    },
    height: t.style == PaltStyle.paper ? 1.05 : null,
  );
}

/// Body voice, for the rare place that sets a family by hand.
TextStyle body({double fontSize = 14, FontWeight fontWeight = FontWeight.w400, Color? color, PaltTheme? theme}) {
  final t = theme ?? palt;
  return GoogleFonts.getFont(t.bodyFamily, fontSize: fontSize, fontWeight: fontWeight, color: color ?? t.text);
}

/// Data voice — anything that came off the wire.
TextStyle mono({
  double fontSize = 12,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) =>
    GoogleFonts.getFont(
      palt.monoFamily,
      fontSize: isPop ? fontSize * 0.95 : fontSize,
      fontWeight: fontWeight,
      color: color ?? kTextSecondary,
    );

/// Overline voice — small section labels. Material and Paper set them in
/// sentence case (see [caps]) and in their own colour.
TextStyle overline({Color? color}) => switch (palt.style) {
      PaltStyle.material =>
        GoogleFonts.getFont(palt.bodyFamily, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: kAccent),
      PaltStyle.paper => GoogleFonts.getFont(palt.displayFamily,
          fontSize: 17, fontStyle: FontStyle.italic, fontWeight: FontWeight.w400, color: kAccent),
      PaltStyle.pop =>
        GoogleFonts.getFont(palt.bodyFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: kText),
      PaltStyle.aurora => GoogleFonts.getFont(palt.bodyFamily,
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: color ?? kTextSecondary),
      PaltStyle.beacon =>
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: color ?? kTextFaint),
    };

const _keepCaps = {'USB', 'PALT', 'SMS', 'IP', 'QR', 'OK'};

/// An all-caps label as the theme wants it: unchanged, or in sentence case.
String caps(String s) {
  if (!isMaterial && !isPaper) return s;
  final words = s.split(' ');
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    String x;
    if (_keepCaps.contains(w.replaceAll(RegExp(r'[^A-Z]'), ''))) {
      x = w;
    } else if (w == 'WI-FI') {
      x = 'Wi-Fi';
    } else {
      x = w.toLowerCase();
      if (i == 0 && x.isNotEmpty) x = x[0].toUpperCase() + x.substring(1);
    }
    out.add(x);
  }
  return out.join(' ');
}

// ── Surfaces ─────────────────────────────────────────────────────────────────

/// A card, tile or button face in the theme's language.
///
/// [color]/[gradient] fill it (tiles by default). [outline] asks for the
/// structural hairline where the theme draws one; [stroke] is a state colour
/// (live, failed, selected) every theme shows. Pop adds a hard ink shadow
/// unless [flat]; [hero] makes it bigger.
BoxDecoration paltDeco({
  double radius = 20,
  Color? color,
  Gradient? gradient,
  bool outline = false,
  Color? stroke,
  bool hero = false,
  bool flat = false,
  BoxShape shape = BoxShape.rectangle,
  PaltTheme? theme,
}) {
  final t = theme ?? palt;
  final br = shape == BoxShape.circle ? null : BorderRadius.circular(rad(radius, t));
  final fill = color ?? (gradient == null ? null : null);
  final grad = color != null ? null : (gradient ?? t.tileGradient);
  switch (t.style) {
    case PaltStyle.pop:
      return BoxDecoration(
        color: fill,
        gradient: grad,
        shape: shape,
        borderRadius: br,
        border: Border.all(color: stroke ?? t.text, width: hero ? 2.5 : 2),
        boxShadow: flat ? null : [BoxShadow(color: t.text, offset: hero ? const Offset(5, 5) : const Offset(3, 3))],
      );
    case PaltStyle.paper:
      return BoxDecoration(
        color: fill,
        gradient: grad,
        shape: shape,
        borderRadius: br,
        border: Border.all(color: stroke ?? t.hairline, width: stroke != null ? 1.4 : 1),
      );
    case PaltStyle.aurora:
      return BoxDecoration(
        color: fill,
        gradient: grad,
        shape: shape,
        borderRadius: br,
        border: Border.all(color: stroke ?? const Color(0x24FFFFFF)),
        boxShadow: hero
            ? const [BoxShadow(color: Color(0x55000000), blurRadius: 32, offset: Offset(0, 14), spreadRadius: -6)]
            : null,
      );
    case PaltStyle.material:
      return BoxDecoration(
        color: fill,
        gradient: grad,
        shape: shape,
        borderRadius: br,
        border: stroke != null ? Border.all(color: stroke, width: 1.5) : null,
      );
    case PaltStyle.beacon:
      return BoxDecoration(
        color: fill,
        gradient: grad,
        shape: shape,
        borderRadius: br,
        border: stroke != null || outline ? Border.all(color: stroke ?? t.hairline) : null,
      );
  }
}

/// The page behind a screen: Beacon's amber glow, Aurora's lights, Pop's
/// dot grid; plain for Material and Paper.
class PaltBackdrop extends StatelessWidget {
  final Widget child;
  const PaltBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final Widget? back = switch (palt.style) {
      PaltStyle.beacon => DecoratedBox(decoration: BoxDecoration(gradient: kPageGlow)),
      PaltStyle.aurora => const CustomPaint(painter: AuroraPainter()),
      PaltStyle.pop => CustomPaint(painter: DotGridPainter(color: kText.withValues(alpha: 0.13))),
      PaltStyle.paper => CustomPaint(painter: PaperPainter(color: kHairline.withValues(alpha: 0.5))),
      PaltStyle.material => null,
    };
    if (back == null) return child;
    return Stack(children: [
      Positioned.fill(child: RepaintBoundary(child: back)),
      child,
    ]);
  }
}

/// Soft blobs of violet, magenta and teal light on deep navy.
class AuroraPainter extends CustomPainter {
  const AuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(rect),
      );
    }

    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = auroraTheme.bg);
    blob(Offset(w * 0.05, h * 0.02), w * 0.95, const Color(0x997C3AED));
    blob(Offset(w * 1.05, h * 0.22), w * 0.75, const Color(0x66DB2777));
    blob(Offset(w * 0.2, h * 0.62), w * 0.7, const Color(0x400EA5E9));
    blob(Offset(w * 0.95, h * 0.98), w * 0.9, const Color(0x5514B8A6));
  }

  @override
  bool shouldRepaint(AuroraPainter old) => false;
}

/// Pop's dot grid.
class DotGridPainter extends CustomPainter {
  final Color color;
  const DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 18.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter old) => old.color != color;
}

/// Paper: a faint column rule down the margin, like a broadsheet.
class PaperPainter extends CustomPainter {
  final Color color;
  const PaperPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(10, 0), Offset(10, size.height), p);
    canvas.drawLine(Offset(size.width - 10, 0), Offset(size.width - 10, size.height), p);
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.color != color;
}

/// Material 3 Expressive's "cookie": a soft scalloped circle, for avatars.
class CookieBorder extends OutlinedBorder {
  final int lobes;
  final double depth;
  const CookieBorder({this.lobes = 9, this.depth = 0.06, super.side});

  Path _path(Rect r) {
    final c = r.center;
    final base = r.shortestSide / 2;
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final rr = base * (1 - depth) + base * depth * math.cos(a * lobes);
      final p = c + Offset(math.cos(a - math.pi / 2) * rr, math.sin(a - math.pi / 2) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) => CookieBorder(lobes: lobes, depth: depth, side: side ?? this.side);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => CookieBorder(lobes: lobes, depth: depth, side: side.scale(t));
}

/// A device's icon in its badge: Material's cookie, Pop's ink square,
/// everyone else's rounded square.
class DeviceBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool lit;
  final int index;
  const DeviceBadge({super.key, required this.icon, this.size = 56, this.lit = true, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final fg = lit ? (isMaterial ? kOnAccentSoft : kAccent) : kTextSecondary;
    return switch (palt.style) {
      PaltStyle.material => Container(
          width: size,
          height: size,
          decoration: ShapeDecoration(
            shape: const CookieBorder(),
            color: lit ? kAccentSoft : kSurfaceRaised,
          ),
          child: Icon(icon, color: fg, size: size * 0.48),
        ),
      PaltStyle.pop => Container(
          width: size,
          height: size,
          decoration: paltDeco(radius: size * 0.3, color: lit ? popColor(index, kAccent) : kSurface, flat: true),
          child: Icon(icon, color: kText, size: size * 0.48),
        ),
      PaltStyle.paper => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: lit ? kText : kHairline, width: 1.2)),
          child: Icon(icon, color: lit ? kText : kTextSecondary, size: size * 0.46),
        ),
      PaltStyle.aurora => Container(
          width: size,
          height: size,
          decoration: lit
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: kAccentGradient,
                  boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: -4)],
                )
              : paltDeco(shape: BoxShape.circle),
          child: Icon(icon, color: lit ? kOnAccent : kTextSecondary, size: size * 0.46),
        ),
      PaltStyle.beacon => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: lit ? kAccent.withValues(alpha: 0.12) : kSurfaceRaised,
            borderRadius: BorderRadius.circular(size * 0.32),
          ),
          child: Icon(icon, color: fg, size: size * 0.5),
        ),
    };
  }
}

// ── ThemeData ────────────────────────────────────────────────────────────────

SystemUiOverlayStyle _overlay(PaltTheme t) => (t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: t.style == PaltStyle.material ? t.bg : t.bg.withValues(alpha: 1),
      systemNavigationBarIconBrightness: t.dark ? Brightness.light : Brightness.dark,
    );

ThemeData buildAppTheme() => palt.style == PaltStyle.material ? _materialData(palt) : _customData(palt);

/// Material: the real thing, with Outfit headlines over Roboto.
ThemeData _materialData(PaltTheme t) {
  final cs = t.scheme!;
  final base = ThemeData(colorScheme: cs, useMaterial3: true);
  final bodyText = GoogleFonts.robotoTextTheme(base.textTheme);
  TextStyle? head(TextStyle? s) => s == null ? null : GoogleFonts.outfit(textStyle: s);
  final text = bodyText.copyWith(
    displayLarge: head(bodyText.displayLarge),
    displayMedium: head(bodyText.displayMedium),
    displaySmall: head(bodyText.displaySmall),
    headlineLarge: head(bodyText.headlineLarge),
    headlineMedium: head(bodyText.headlineMedium),
    headlineSmall: head(bodyText.headlineSmall),
    titleLarge: head(bodyText.titleLarge),
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      foregroundColor: cs.onSurface,
      centerTitle: false,
      systemOverlayStyle: _overlay(t),
      titleTextStyle: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w400, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      extendedTextStyle: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      modalBackgroundColor: cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: cs.surfaceContainerHigh),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Icon(Icons.check_rounded) : null,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: cs.onSurfaceVariant),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}

/// Beacon, Aurora, Paper and Pop: the same skeleton, each in its own hand.
ThemeData _customData(PaltTheme t) {
  final base = ThemeData(brightness: t.brightness, useMaterial3: true);
  final pop = t.style == PaltStyle.pop;
  final paper = t.style == PaltStyle.paper;
  final ink = BorderSide(color: t.text, width: 2);
  final btnRadius = BorderRadius.circular(rad(t.style == PaltStyle.aurora ? 999 : 10, t));
  final body = GoogleFonts.getFont(t.bodyFamily);
  final opaque = t.style == PaltStyle.aurora ? t.surfaceRaised : t.surface;

  return base.copyWith(
    colorScheme: ColorScheme(
      brightness: t.brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.onAccentSoft,
      secondary: t.textSecondary,
      onSecondary: t.bg,
      secondaryContainer: t.accentSoft,
      onSecondaryContainer: t.onAccentSoft,
      tertiary: t.ok,
      onTertiary: t.bg,
      surface: opaque,
      onSurface: t.text,
      onSurfaceVariant: t.textSecondary,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: opaque,
      surfaceContainer: opaque,
      surfaceContainerHigh: t.surfaceRaised,
      surfaceContainerHighest: t.surfaceRaised,
      outline: t.hairline,
      outlineVariant: t.hairline,
      error: t.danger,
      onError: t.bg,
    ),
    textTheme: GoogleFonts.getTextTheme(t.bodyFamily, base.textTheme).apply(
      bodyColor: t.text,
      displayColor: t.text,
    ),
    scaffoldBackgroundColor: t.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: t.style == PaltStyle.aurora ? Colors.transparent : t.bg,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: _overlay(t),
      titleTextStyle: display(fontSize: 22, fontWeight: FontWeight.w800, theme: t),
      shape: pop ? Border(bottom: ink) : (paper ? Border(bottom: BorderSide(color: t.text, width: 1)) : null),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(14, t))),
        side: pop ? ink : BorderSide(color: t.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: btnRadius, side: pop ? ink : BorderSide.none),
        textStyle: body.copyWith(fontWeight: pop ? FontWeight.w700 : FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        backgroundColor: pop ? t.surface : null,
        side: pop ? ink : BorderSide(color: paper ? t.text : t.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: btnRadius),
        textStyle: body.copyWith(fontWeight: pop ? FontWeight.w700 : FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: paper || pop ? t.accent : t.textSecondary,
        textStyle: body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: t.onAccent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(14, t))),
        side: pop ? ink : BorderSide.none,
      ),
      extendedTextStyle: body.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(18, t))),
        side: pop ? BorderSide(color: t.text, width: 2.5) : BorderSide(color: t.hairline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surfaceRaised,
      modalBackgroundColor: t.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(rad(22, t))),
        side: pop ? BorderSide(color: t.text, width: 2.5) : BorderSide.none,
      ),
    ),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: pop ? 2 : 1),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: t.textFaint, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(t.onAccent),
    ),
    switchTheme: pop
        ? SwitchThemeData(
            trackOutlineColor: WidgetStatePropertyAll(t.text),
            trackOutlineWidth: const WidgetStatePropertyAll(2),
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? t.surface : t.text,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? t.accent : t.surface,
            ),
          )
        : null,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.hairline,
      circularTrackColor: t.hairline,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: paper || pop ? t.text : t.surfaceRaised,
      contentTextStyle: body.copyWith(color: paper || pop ? t.bg : t.text, fontSize: 13),
      actionTextColor: paper || pop ? t.sent : t.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(10, t))),
        side: paper || pop ? BorderSide.none : BorderSide(color: t.hairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pop ? t.surface : t.bg,
      hintStyle: body.copyWith(color: t.textFaint),
      helperStyle: body.copyWith(color: t.textFaint, fontSize: 11),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(10, t))),
        borderSide: pop ? ink : BorderSide(color: t.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(rad(10, t))),
        borderSide: BorderSide(color: t.accent, width: pop ? 2.5 : 1),
      ),
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android: switch (t.style) {
        PaltStyle.aurora => const FadeForwardsPageTransitionsBuilder(),
        PaltStyle.paper => const CupertinoPageTransitionsBuilder(),
        PaltStyle.pop => const OpenUpwardsPageTransitionsBuilder(),
        _ => const ZoomPageTransitionsBuilder(),
      },
    }),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.text, borderRadius: BorderRadius.circular(rad(6, t))),
      textStyle: body.copyWith(color: t.bg, fontSize: 12),
    ),
  );
}

// ── Choosing a theme ─────────────────────────────────────────────────────────

/// The themes, in the order the picker shows them.
const themeIds = ['beacon', 'material', 'aurora', 'paper', 'pop'];

/// Material's own colours when the wallpaper's aren't used (or available).
const materialSeeds = <Color>[
  Color(0xFF1A73E8), // Google blue
  Color(0xFF188038), // green
  Color(0xFFE37400), // orange
  Color(0xFFD93025), // red
  Color(0xFF9334E6), // purple
  Color(0xFF00897B), // teal
];

/// Which theme, and Material's options. Persists itself; [palt] follows it.
class PaltThemeController extends ChangeNotifier {
  static const _kId = 'palt_theme';
  static const _kMode = 'palt_theme_mode';
  static const _kWallpaper = 'palt_theme_wallpaper';
  static const _kSeed = 'palt_theme_seed';

  SharedPreferences? _prefs;
  String id = 'beacon';

  /// Material's light/dark: system, light or dark.
  ThemeMode mode = ThemeMode.system;

  /// Material: take colours from the wallpaper (Android 12+).
  bool wallpaper = true;
  Color seed = materialSeeds.first;

  /// The wallpaper's colour, when the system offers one.
  Color? wallpaperSeed;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    final saved = prefs.getString(_kId);
    if (saved != null && themeIds.contains(saved)) id = saved;
    mode = ThemeMode.values.elementAtOrNull(prefs.getInt(_kMode) ?? 0) ?? ThemeMode.system;
    wallpaper = prefs.getBool(_kWallpaper) ?? true;
    final s = prefs.getInt(_kSeed);
    if (s != null) seed = Color(s);
    try {
      final core = await DynamicColorPlugin.getCorePalette();
      if (core != null) wallpaperSeed = Color(core.primary.get(40));
    } catch (_) {}
    _apply();
  }

  Brightness get _platform => WidgetsBinding.instance.platformDispatcher.platformBrightness;

  Brightness get materialBrightness => switch (mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => _platform,
      };

  /// Any theme, as it would look now.
  PaltTheme resolve(String themeId) => switch (themeId) {
        'material' => materialTheme(ColorScheme.fromSeed(
            seedColor: (wallpaper ? wallpaperSeed : null) ?? seed,
            brightness: materialBrightness,
          )),
        'aurora' => auroraTheme,
        'paper' => paperTheme,
        'pop' => popTheme,
        _ => beaconTheme,
      };

  void _apply() {
    palt = resolve(id);
    SystemChrome.setSystemUIOverlayStyle(_overlay(palt));
  }

  /// Called just before the theme changes, while the old one still shows.
  VoidCallback? beforeChange;

  void _changed() {
    beforeChange?.call();
    _apply();
    notifyListeners();
  }

  void select(String themeId) {
    if (themeId == id) return;
    id = themeId;
    _prefs?.setString(_kId, themeId);
    _changed();
  }

  void setMode(ThemeMode m) {
    mode = m;
    _prefs?.setInt(_kMode, m.index);
    _changed();
  }

  void setWallpaper(bool on) {
    wallpaper = on;
    _prefs?.setBool(_kWallpaper, on);
    _changed();
  }

  void setSeed(Color c) {
    seed = c;
    wallpaper = false;
    _prefs?.setInt(_kSeed, c.toARGB32());
    _prefs?.setBool(_kWallpaper, false);
    _changed();
  }

  /// The system went light or dark.
  void platformBrightnessChanged() {
    if (id == 'material' && mode == ThemeMode.system) _changed();
  }
}

final themeController = PaltThemeController();
