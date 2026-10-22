/// palt_page.dart — page chrome and grouped lists, in each theme's own hand.
///
/// PaltPage gives a secondary screen its header: Material's large
/// collapsing app bar, Paper's masthead, Pop's sticker, Aurora's centred
/// glass title, Beacon's plain bar. PaltSection groups rows the way the
/// theme groups them: Android-settings blocks, ruled columns, ink boxes,
/// frosted panels.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class PaltPage extends StatelessWidget {
  final String title;

  /// A line under the title (Paper and Pop show it; Material folds it away).
  final String? kicker;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? floating;

  const PaltPage({
    super.key,
    required this.title,
    this.kicker,
    this.actions = const [],
    required this.slivers,
    this.floating,
  });

  @override
  Widget build(BuildContext context) {
    final back = Navigator.of(context).canPop();
    final Widget header = switch (palt.style) {
      PaltStyle.material => SliverAppBar.large(
          title: Text(title),
          actions: actions,
        ),
      PaltStyle.paper => SliverToBoxAdapter(child: _PaperHead(title: title, kicker: kicker, actions: actions, back: back)),
      PaltStyle.pop => SliverToBoxAdapter(child: _PopHead(title: title, kicker: kicker, actions: actions, back: back)),
      PaltStyle.aurora => SliverAppBar(
          pinned: true,
          centerTitle: true,
          backgroundColor: kBg.withValues(alpha: 0.55),
          title: Text(title, style: display(fontSize: 18, fontWeight: FontWeight.w600)),
          actions: actions,
        ),
      PaltStyle.beacon => SliverAppBar(
          pinned: true,
          title: Text(title, style: display(fontSize: 19)),
          actions: actions,
        ),
    };
    return Scaffold(
      floatingActionButton: floating,
      body: PaltBackdrop(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            if (palt.style == PaltStyle.paper || palt.style == PaltStyle.pop)
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top)),
            header,
            ...slivers,
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _PaperHead extends StatelessWidget {
  final String title;
  final String? kicker;
  final List<Widget> actions;
  final bool back;
  const _PaperHead({required this.title, this.kicker, required this.actions, required this.back});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (back)
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: kText),
                icon: const Icon(Icons.west_rounded, size: 18),
                label: const Text('Back'),
              ),
            const Spacer(),
            ...actions,
          ]),
          const SizedBox(height: 6),
          if (kicker != null) Text(kicker!.toUpperCase(), style: mono(fontSize: 10, color: kAccent).copyWith(letterSpacing: 2)),
          Text(title, style: display(fontSize: 46)),
          const SizedBox(height: 10),
          Container(height: 3, color: kText),
          const SizedBox(height: 2),
          Container(height: 1, color: kText),
        ]),
      );
}

class _PopHead extends StatelessWidget {
  final String title;
  final String? kicker;
  final List<Widget> actions;
  final bool back;
  const _PopHead({required this.title, this.kicker, required this.actions, required this.back});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (back) PopIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
            const Spacer(),
            ...actions,
          ]),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: -0.03,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              decoration: paltDeco(radius: 8, color: popColor(0, kAccent), hero: true),
              child: Text(title.toUpperCase(), style: display(fontSize: 30)),
            ),
          ),
          if (kicker != null) ...[
            const SizedBox(height: 12),
            Text(kicker!, style: body(fontSize: 14, fontWeight: FontWeight.w500, color: kTextSecondary)),
          ],
        ]),
      );
}

/// Pop's square ink button.
class PopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  const PopIconButton({super.key, required this.icon, this.onTap, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: PressDown(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: paltDeco(radius: 10, color: color ?? kSurface),
            child: Icon(icon, color: kText, size: 22),
          ),
        ),
      );
}

/// Pop: a press sinks the block into its shadow. Elsewhere a plain tap.
class PressDown extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const PressDown({super.key, required this.child, this.onTap, this.onLongPress});

  @override
  State<PressDown> createState() => _PressDownState();
}

class _PressDownState extends State<PressDown> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          transform: Matrix4.translationValues(_down ? 3 : 0, _down ? 3 : 0, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: widget.onTap == null && widget.onLongPress == null ? 0.5 : 1,
            child: widget.child,
          ),
        ),
      );
}

/// A titled group of rows.
class PaltSection extends StatelessWidget {
  final String title;
  final String? note;
  final List<Widget> children;
  const PaltSection({super.key, required this.title, this.note, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = children;
    final heading = Padding(
      padding: EdgeInsets.fromLTRB(isMaterial ? 16 : 4, 0, 4, isPaper ? 2 : 8),
      child: Text(caps(title.toUpperCase()), style: overline()),
    );
    final Widget box = switch (palt.style) {
      // Android settings: each row its own block, the group rounded big.
      PaltStyle.material => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 2),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(i == 0 ? 24 : 4),
                  bottom: Radius.circular(i == rows.length - 1 ? 24 : 4),
                ),
              ),
              child: Material(type: MaterialType.transparency, child: rows[i]),
            ),
        ]),
      PaltStyle.paper => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++) ...[
            Material(type: MaterialType.transparency, child: rows[i]),
            if (i < rows.length - 1) Divider(height: 1, color: kHairline),
          ],
          Divider(height: 1, color: kText),
        ]),
      _ => Container(
          clipBehavior: Clip.antiAlias,
          decoration: isBeacon
              ? BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18))
              : paltDeco(radius: 20, color: isPop ? kSurface : null),
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(height: 1, indent: 16, endIndent: 16, color: isPop ? kText.withValues(alpha: 0.15) : kHairline),
              ],
            ]),
          ),
        ),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(isMaterial ? 12 : 18, 18, isMaterial ? 12 : 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        heading,
        if (note != null)
          Padding(
            padding: EdgeInsets.fromLTRB(isMaterial ? 16 : 4, 0, 4, 8),
            child: Text(note!, style: TextStyle(color: kTextFaint, fontSize: 12)),
          ),
        box,
      ]),
    );
  }
}

/// A settings row: icon, title, subtitle, and a switch or a chevron.
class PaltTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  const PaltTile({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.onChanged,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final lead = icon == null
        ? null
        : switch (palt.style) {
            PaltStyle.material => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: kAccentSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: iconColor ?? kOnAccentSoft),
              ),
            PaltStyle.pop => Container(
                width: 38,
                height: 38,
                decoration: paltDeco(radius: 8, color: popColor(title.length, kAccent), flat: true),
                child: Icon(icon, size: 20, color: kText),
              ),
            PaltStyle.aurora => Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (iconColor ?? kAccent).withValues(alpha: 0.16),
                ),
                child: Icon(icon, size: 19, color: iconColor ?? kAccent),
              ),
            _ => Icon(icon, color: iconColor ?? kTextSecondary),
          };
    final titleStyle = isPaper
        ? display(fontSize: dense ? 17 : 19, fontWeight: FontWeight.w400)
        : TextStyle(
            color: kText,
            fontSize: dense ? 14 : 15.5,
            fontWeight: isPop ? FontWeight.w700 : (isMaterial ? FontWeight.w400 : FontWeight.w500),
          );
    final sub = subtitle == null
        ? null
        : Text(subtitle!, style: TextStyle(color: kTextSecondary, fontSize: 12.5, height: 1.35));
    final pad = EdgeInsets.symmetric(horizontal: isPaper ? 4 : 16, vertical: dense ? 0 : 4);
    if (value != null) {
      return SwitchListTile(
        contentPadding: pad,
        secondary: lead,
        dense: dense,
        title: Text(title, style: titleStyle),
        subtitle: sub,
        value: value!,
        onChanged: onChanged,
      );
    }
    return ListTile(
      contentPadding: pad,
      leading: lead,
      dense: dense,
      title: Text(title, style: titleStyle),
      subtitle: sub,
      trailing: trailing ?? (onTap == null ? null : Icon(Icons.chevron_right_rounded, color: kTextFaint)),
      onTap: onTap,
    );
  }
}
