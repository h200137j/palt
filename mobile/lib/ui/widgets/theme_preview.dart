/// theme_preview.dart — a theme as a tiny phone, for the picker.
///
/// Drawn from the theme's own tokens (never the live one), and each in its
/// own layout: Material's FAB and nav bar, Paper's masthead, Pop's sticker,
/// Aurora's glowing orb, Beacon's amber lamp.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ThemePreview extends StatelessWidget {
  final PaltTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const ThemePreview({super.key, required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final live = palt;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 128,
          height: 228,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(rad(26, live) + 3),
            border: Border.all(
              color: selected ? live.accent : live.hairline.withValues(alpha: isPop ? 1 : 0.6),
              width: selected ? 3 : (isPop ? 2 : 1),
            ),
            boxShadow: selected && live.style != PaltStyle.paper
                ? [BoxShadow(color: live.accent.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rad(26, live) - 1),
            child: _Screen(t: t),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[
            Icon(Icons.check_circle_rounded, size: 16, color: live.accent),
            const SizedBox(width: 5),
          ],
          Text(t.name,
              style: TextStyle(
                color: live.text,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              )),
        ]),
      ]),
    );
  }
}

class _Screen extends StatelessWidget {
  final PaltTheme t;
  const _Screen({required this.t});

  Widget _bar(double w, Color c, [double h = 5]) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(h)),
      );

  @override
  Widget build(BuildContext context) {
    final Widget? back = switch (t.style) {
      PaltStyle.beacon => DecoratedBox(decoration: BoxDecoration(color: t.bg, gradient: t.pageGlow)),
      PaltStyle.aurora => const CustomPaint(painter: AuroraPainter()),
      PaltStyle.pop => CustomPaint(painter: DotGridPainter(color: t.text.withValues(alpha: 0.15))),
      _ => null,
    };
    return Container(
      color: t.bg,
      child: Stack(children: [
        if (back != null) Positioned.fill(child: back),
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: SizedBox(height: 222, child: _content()),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _content() {
    final heroDeco = paltDeco(theme: t, radius: 14, gradient: t.cardGradient, outline: true, hero: true);
    final tile = paltDeco(theme: t, radius: 10, outline: true);
    final accentTile = paltDeco(theme: t, radius: 10, gradient: t.accentGradient);
    switch (t.style) {
      case PaltStyle.material:
        final cs = t.scheme!;
        return Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PALT', style: display(theme: t, fontSize: 22, fontWeight: FontWeight.w400)),
              const SizedBox(height: 8),
              Container(
                height: 22,
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: _bar(50, cs.onSurfaceVariant.withValues(alpha: 0.5), 4),
              ),
              const SizedBox(height: 8),
              Container(
                height: 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: ShapeDecoration(shape: const CookieBorder(), color: cs.primaryContainer),
                    ),
                    const SizedBox(width: 6),
                    _bar(44, cs.onSurface.withValues(alpha: 0.7)),
                  ]),
                  const Spacer(),
                  Row(children: [
                    Container(
                        width: 34,
                        height: 16,
                        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(16))),
                    const SizedBox(width: 4),
                    Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle)),
                  ]),
                ]),
              ),
            ]),
          ),
          Positioned(
            right: 10,
            bottom: 40,
            child: Container(
              width: 50,
              height: 26,
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.qr_code_scanner_rounded, size: 13, color: cs.onPrimaryContainer),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 30,
              color: cs.surfaceContainer,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Container(
                    width: 26,
                    height: 13,
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(8))),
                _bar(10, cs.onSurfaceVariant, 10),
                _bar(10, cs.onSurfaceVariant, 10),
              ]),
            ),
          ),
        ]);
      case PaltStyle.paper:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VOL. 2 · THURSDAY', style: TextStyle(fontSize: 5.5, letterSpacing: 1, color: t.accent)),
            Text('The Palt', style: display(theme: t, fontSize: 26)),
            Container(height: 2, color: t.text),
            const SizedBox(height: 1.5),
            Container(height: 0.6, color: t.text),
            const SizedBox(height: 8),
            Text('uriel-thinkpad', style: display(theme: t, fontSize: 14)),
            const SizedBox(height: 4),
            for (final w in [100.0, 90.0, 96.0, 60.0])
              Padding(padding: const EdgeInsets.only(bottom: 3), child: _bar(w, t.textFaint, 2.5)),
            const SizedBox(height: 6),
            Container(height: 0.6, color: t.hairline),
            const SizedBox(height: 6),
            Row(children: [
              Text('Send ', style: TextStyle(fontSize: 8, color: t.accent, fontWeight: FontWeight.w600)),
              Icon(Icons.east_rounded, size: 8, color: t.accent),
            ]),
            const SizedBox(height: 6),
            Container(height: 0.6, color: t.hairline),
            const SizedBox(height: 8),
            Text('Galaxy Tab', style: display(theme: t, fontSize: 12)),
            const SizedBox(height: 4),
            _bar(80, t.textFaint, 2.5),
          ]),
        );
      case PaltStyle.pop:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Transform.rotate(
              angle: -0.05,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: paltDeco(theme: t, radius: 4, color: t.pops[0]),
                child: Text('PALT!', style: display(theme: t, fontSize: 17)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 64,
              padding: const EdgeInsets.all(7),
              decoration: paltDeco(theme: t, radius: 10, color: t.surface, hero: true),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 18, height: 18, decoration: paltDeco(theme: t, radius: 4, color: t.pops[3], flat: true)),
                  const SizedBox(width: 5),
                  _bar(40, t.text, 4),
                ]),
                const Spacer(),
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 3),
                      width: 22,
                      height: 14,
                      decoration: paltDeco(theme: t, radius: 3, color: t.pops[i + 1], flat: true),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: Container(height: 40, decoration: paltDeco(theme: t, radius: 8, color: t.pops[1]))),
              const SizedBox(width: 6),
              Expanded(
                  child: Container(height: 40, decoration: paltDeco(theme: t, radius: 8, color: t.pops[2]))),
            ]),
            const SizedBox(height: 10),
            Container(height: 22, decoration: paltDeco(theme: t, radius: 6, color: t.accent)),
          ]),
        );
      case PaltStyle.aurora:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
          child: Column(children: [
            Text('palt', style: display(theme: t, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: t.accentGradient,
                boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.6), blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 10),
            Container(height: 46, decoration: heroDeco),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Container(height: 30, decoration: tile)),
              const SizedBox(width: 6),
              Expanded(child: Container(height: 30, decoration: tile)),
            ]),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 22,
              width: 80,
              decoration: paltDeco(theme: t, radius: 999),
            ),
          ]),
        );
      case PaltStyle.beacon:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('PALT', style: display(theme: t, fontSize: 14, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            Container(
              height: 72,
              padding: const EdgeInsets.all(8),
              decoration: heroDeco,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                      width: 20,
                      height: 20,
                      decoration:
                          BoxDecoration(color: t.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6))),
                  const SizedBox(width: 6),
                  _bar(44, t.text),
                ]),
                const Spacer(),
                Row(children: [
                  Expanded(child: Container(height: 18, decoration: accentTile)),
                  const SizedBox(width: 4),
                  Expanded(child: Container(height: 18, decoration: tile)),
                  const SizedBox(width: 4),
                  Expanded(child: Container(height: 18, decoration: tile)),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            Container(height: 34, decoration: tile),
          ]),
        );
    }
  }
}
