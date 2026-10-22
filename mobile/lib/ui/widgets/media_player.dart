/// media_player.dart — the now-playing card for a computer's media (Beacon).
///
/// Blurred cover art under a gradient tinted with the art's own colour, a
/// slow drifting glow while playing, and a wavy seek line (One UI style) in
/// that colour running into the app's amber. The wave moves while playing
/// and settles flat when paused; the play button morphs, the art cross-fades
/// between tracks and eases back a little when paused.
///
/// Lives in the device screen's Control tab.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../features/media.dart';
import '../../theme/app_theme.dart';

// ── Art and its colour ──────────────────────────────────────────────────────

final _artBytes = <String, Future<Uint8List?>>{};
final _tints = <String, Future<Color?>>{};

/// The bytes of a data: or web URL, fetched once.
Future<Uint8List?> _bytes(String url) => _artBytes.putIfAbsent(url, () async {
      try {
        if (url.startsWith('data:')) return base64Decode(url.substring(url.indexOf(',') + 1));
        if (!url.startsWith('http')) return null;
        final req = await HttpClient().getUrl(Uri.parse(url)).timeout(const Duration(seconds: 6));
        final res = await req.close();
        final b = BytesBuilder(copy: false);
        await for (final chunk in res) {
          b.add(chunk);
        }
        return b.takeBytes();
      } catch (_) {
        return null;
      }
    });

/// The art's most vivid colour, tamed to sit on the app's dark surfaces.
Future<Color?> artTint(String url) => _tints.putIfAbsent(url, () async {
      final bytes = await _bytes(url);
      if (bytes == null) return null;
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32, targetHeight: 32);
        final img = (await codec.getNextFrame()).image;
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        double r = 0, g = 0, b = 0, total = 0;
        for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
          final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
          final hsv = HSVColor.fromColor(c);
          // Vivid, not too dark or washed out, counts most.
          final w = math.pow(hsv.saturation, 2) * hsv.value * (hsv.value > 0.15 ? 1 : 0) + 0.002;
          r += c.r * w;
          g += c.g * w;
          b += c.b * w;
          total += w;
        }
        final avg = Color.from(alpha: 1, red: r / total, green: g / total, blue: b / total);
        final hsv = HSVColor.fromColor(avg);
        return hsv.withSaturation(hsv.saturation.clamp(0.35, 0.8)).withValue(0.85).toColor();
      } catch (_) {
        return null;
      }
    });

/// Cover art from a web URL or a data: URL, or a placeholder.
class MediaArt extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  const MediaArt({super.key, required this.url, this.size = 72, this.radius = 14});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: FutureBuilder<Uint8List?>(
            future: _bytes(url),
            builder: (_, snap) => snap.data == null
                ? Container(
                    color: kSurfaceRaised,
                    child: Icon(Icons.music_note_rounded, color: kTextFaint, size: size * 0.4),
                  )
                : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      );
}

// ── The card ────────────────────────────────────────────────────────────────

class NowPlayingCard extends StatefulWidget {
  final String device;
  final MediaPlayer player;
  final MediaState state;
  final void Function(String player, String action, [double value]) act;

  /// Volume row at the bottom.
  final Widget? footer;

  const NowPlayingCard({
    super.key,
    required this.device,
    required this.player,
    required this.state,
    required this.act,
    this.footer,
  });

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> with TickerProviderStateMixin {
  /// Drives the wave and the glow, and repaints the moving position.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 8))
    ..repeat();
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: widget.player.playing ? 1 : 0,
  );
  Color _tint = kAccent;
  String _tintFor = '';
  double? _seekDrag;

  @override
  void initState() {
    super.initState();
    _loadTint();
  }

  @override
  void didUpdateWidget(NowPlayingCard old) {
    super.didUpdateWidget(old);
    widget.player.playing ? _play.forward() : _play.reverse();
    _loadTint();
  }

  void _loadTint() {
    final url = widget.player.art;
    if (url == _tintFor) return;
    _tintFor = url;
    artTint(url).then((c) {
      if (mounted && _tintFor == url) setState(() => _tint = c ?? kAccent);
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;

    final art = AnimatedScale(
      scale: p.playing ? 1 : 0.92,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Container(
          key: ValueKey(p.art),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: _tint.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: MediaArt(url: p.art, size: 76, radius: 16),
        ),
      ),
    );

    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Bars(playing: p.playing, color: _tint, loop: _loop),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${p.name.toUpperCase()} · ${widget.device.toUpperCase()}',
                  style: mono(fontSize: 10, color: kText.withValues(alpha: 0.7)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Text(
            p.title.isEmpty ? 'Unknown' : p.title,
            key: ValueKey(p.title),
            style: display(fontSize: 19, fontWeight: FontWeight.w800),
            maxLines: 1,
            textAlign: TextAlign.start,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (p.artist.isNotEmpty)
          Text(p.artist,
              style: TextStyle(fontSize: 13, color: kText.withValues(alpha: 0.72)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      ],
    );

    final head = Row(children: [art, const SizedBox(width: 16), Expanded(child: titles)]);

    final seek = p.length > 0
        ? AnimatedBuilder(
            animation: _loop,
            builder: (_, __) {
              final pos = _seekDrag ?? widget.state.positionOf(p).toDouble();
              final frac = (pos / p.length).clamp(0.0, 1.0);
              return Column(children: [
                WavySeekBar(
                  progress: frac,
                  phase: _loop.value * 2 * math.pi * 8,
                  amplitude: _play.value,
                  color: _tint,
                  enabled: p.canSeek,
                  onDrag: (f) => setState(() => _seekDrag = f * p.length),
                  onSeek: (f) {
                    widget.act(p.id, 'seek', (f * p.length).roundToDouble());
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) setState(() => _seekDrag = null);
                    });
                  },
                ),
                Row(children: [
                  Text(_clock(pos.toInt()), style: mono(fontSize: 10.5, color: kText.withValues(alpha: 0.6))),
                  const Spacer(),
                  Text(_clock(p.length), style: mono(fontSize: 10.5, color: kText.withValues(alpha: 0.6))),
                ]),
              ]);
            },
          )
        : const SizedBox(height: 8);

    final transport = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.skip_previous_rounded,
          size: 48,
          onTap: p.canPrev ? () => widget.act(p.id, 'previous') : null,
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => widget.act(p.id, 'playpause'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(_tint, kAccent, 0.35)!, kAccent],
              ),
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: p.playing ? 0.45 : 0.15),
                  blurRadius: p.playing ? 26 : 10,
                  spreadRadius: p.playing ? 1 : 0,
                ),
              ],
            ),
            child: Center(
              child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _play, size: 32, color: kOnAccent),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _RoundButton(
          icon: Icons.skip_next_rounded,
          size: 48,
          onTap: p.canNext ? () => widget.act(p.id, 'next') : null,
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          // Blurred art, then the tint gradient, then a drifting glow.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              child: ImageFiltered(
                key: ValueKey(p.art),
                imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                child: Opacity(opacity: 0.55, child: MediaArt(url: p.art, size: 600, radius: 0)),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(kBg, _tint, 0.42)!.withValues(alpha: 0.82),
                    Color.lerp(kBg, _tint, 0.12)!.withValues(alpha: 0.9),
                    kBg.withValues(alpha: 0.95),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _loop,
              builder: (_, __) {
                final t = _loop.value * 2 * math.pi;
                return AnimatedOpacity(
                  opacity: p.playing ? 1 : 0.35,
                  duration: const Duration(milliseconds: 600),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(math.cos(t) * 0.7, math.sin(t) * 0.5 - 0.2),
                        radius: 0.9,
                        colors: [_tint.withValues(alpha: 0.28), _tint.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                const SizedBox(height: 14),
                seek,
                const SizedBox(height: 6),
                transport,
                if (widget.footer != null) ...[const SizedBox(height: 4), widget.footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, required this.size, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.white.withValues(alpha: onTap == null ? 0.03 : 0.08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: size * 0.55, color: onTap == null ? kTextFaint : kText),
          ),
        ),
      );
}

/// Three little equalizer bars that dance while playing.
class _Bars extends StatelessWidget {
  final bool playing;
  final Color color;
  final Animation<double> loop;
  const _Bars({required this.playing, required this.color, required this.loop});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: loop,
        builder: (_, __) {
          final t = loop.value * 2 * math.pi * 6;
          return SizedBox(
            width: 14,
            height: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 3,
                    height: playing ? 4 + 8 * (0.5 + 0.5 * math.sin(t + i * 2.1)).abs() : 4,
                    decoration: BoxDecoration(
                      color: Color.lerp(color, kAccent, 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

// ── Wavy seek bar ───────────────────────────────────────────────────────────

/// One UI–style seek line: the played part is a sine wave, the rest a thin
/// straight track. [amplitude] 0..1 (flat when paused); tap or drag to seek.
class WavySeekBar extends StatelessWidget {
  final double progress;
  final double phase;
  final double amplitude;
  final Color color;
  final bool enabled;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onSeek;

  const WavySeekBar({
    super.key,
    required this.progress,
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.enabled,
    required this.onDrag,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        double frac(Offset local) => (local.dx / box.maxWidth).clamp(0.0, 1.0);
        double last = progress;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled ? (d) => onSeek(frac(d.localPosition)) : null,
          onHorizontalDragUpdate: enabled
              ? (d) {
                  last = frac(d.localPosition);
                  onDrag(last);
                }
              : null,
          onHorizontalDragEnd: enabled ? (_) => onSeek(last) : null,
          child: SizedBox(
            height: 30,
            width: double.infinity,
            child: CustomPaint(
              painter: _WavePainter(progress: progress, phase: phase, amplitude: amplitude, color: color),
            ),
          ),
        );
      });
}

class _WavePainter extends CustomPainter {
  final double progress, phase, amplitude;
  final Color color;
  _WavePainter({required this.progress, required this.phase, required this.amplitude, required this.color});

  static const _wavelength = 26.0;
  static const _maxAmp = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final x = size.width * progress;

    // Track still to play.
    if (x + 8 < size.width) {
      canvas.drawLine(
        Offset(x + 8, mid),
        Offset(size.width, mid),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Played part: the wave, easing in from the left edge and into the thumb.
    if (x > 1) {
      final path = Path()..moveTo(0, mid);
      for (double px = 0; px <= x; px += 1.5) {
        final taper = math.min(1.0, math.min(px, x - px) / 14);
        final y = mid + math.sin(px / _wavelength * 2 * math.pi - phase) * _maxAmp * amplitude * taper;
        path.lineTo(px, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..shader =
              LinearGradient(colors: [color, kAccent]).createShader(Offset.zero & Size(math.max(x, 1), size.height))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Thumb: a short upright pill with a glow.
    final thumb = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, mid), width: 6, height: 20), const Radius.circular(3));
    canvas.drawRRect(thumb.inflate(4), Paint()..color = kAccent.withValues(alpha: 0.22));
    canvas.drawRRect(thumb, Paint()..color = kAccent);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.phase != phase || old.amplitude != amplitude || old.color != color;
}
