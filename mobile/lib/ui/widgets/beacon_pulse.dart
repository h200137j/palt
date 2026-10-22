/// beacon_pulse.dart — the Beacon signature element.
///
/// Concentric rings emanating from a child, like an mDNS beacon announcing
/// itself. Rings animate only while [active]; when the platform requests
/// reduced motion they freeze into a static halo.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class BeaconPulse extends StatefulWidget {
  final bool active;
  final double size;
  final Color? color;
  final Widget child;

  const BeaconPulse({
    super.key,
    required this.active,
    required this.size,
    this.color,
    required this.child,
  });

  @override
  State<BeaconPulse> createState() => _BeaconPulseState();
}

class _BeaconPulseState extends State<BeaconPulse>
    with SingleTickerProviderStateMixin {
  static const _ringCount = 3;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(BeaconPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.active && !reduceMotion)
            ...List.generate(_ringCount, (i) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Stagger each ring a third of a cycle apart.
                  final t = (_controller.value + i / _ringCount) % 1.0;
                  final eased = Curves.easeOut.transform(t);
                  return Container(
                    width: widget.size * (1 + eased * 1.1),
                    height: widget.size * (1 + eased * 1.1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (widget.color ?? kAccent).withValues(alpha: 0.45 * (1 - eased)),
                        width: 1.5,
                      ),
                    ),
                  );
                },
              );
            }),
          // Static halo grounds the rings even when idle / reduced motion.
          Container(
            width: widget.size + 12,
            height: widget.size + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: (widget.color ?? kAccent).withValues(alpha: widget.active ? 0.3 : 0.12),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
