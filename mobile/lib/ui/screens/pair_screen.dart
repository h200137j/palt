/// pair_screen.dart — pair with your computer and set up the relay (Beacon).
///
/// All your devices share one pairing code. Scan the QR code your computer
/// shows (PALT → link icon) or paste the code. Paired devices encrypt every
/// connection, accept each other's files without asking and stay connected
/// in the background. The optional relay reaches them on other networks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../providers/link_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/relay_provider.dart';
import '../../services/relay/relay_client.dart';
import '../../theme/app_theme.dart';
import '../widgets/route_badge.dart';

Color relayStateColor(RelayStatus? s) => switch (s?.state) {
      RelayState.online => kRelay,
      RelayState.error => kDanger,
      RelayState.connecting => kTextSecondary,
      _ => kTextFaint,
    };

/// App-bar button: green dot while a paired device is linked; opens [PairScreen].
class PairButton extends ConsumerWidget {
  const PairButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = (ref.watch(linksProvider).valueOrNull ?? []).isNotEmpty;
    return IconButton(
      tooltip: 'Pair devices',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PairScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.link_rounded, color: linked ? kOk : kTextSecondary),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: linked ? kOk : kTextFaint,
                shape: BoxShape.circle,
                border: Border.all(color: kBg, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  final _codeCtl = TextEditingController();
  final _relayCtl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _relayCtl.text = ref.read(pairingProvider).relay;
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    _relayCtl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _error = null);
    try {
      await fn();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _join(String code) => _run(() async {
        await ref.read(pairingProvider.notifier).join(code);
        _codeCtl.clear();
        _relayCtl.text = ref.read(pairingProvider).relay;
        ref.read(connectorProvider).kick();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paired — connecting to your devices…')),
          );
        }
      });

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanPage()),
    );
    if (code != null) await _join(code);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) setState(() => _codeCtl.text = text);
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unpair all devices?', style: display(fontSize: 19)),
        content: Text(
          'This phone gets a new code. Every other device is unpaired until it '
          'scans the new one.',
          style: TextStyle(color: kTextSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kDanger),
            child: const Text('Unpair all'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(pairingProvider.notifier).reset());
  }

  String _relayText(String relay, RelayStatus? s) {
    if (relay.isEmpty) return 'Off — paired devices are reached on the same network only';
    switch (s?.state) {
      case RelayState.online:
        final n = s!.peers;
        return 'Online · $n other device${n == 1 ? '' : 's'} connected';
      case RelayState.connecting:
        return 'Connecting…';
      case RelayState.error:
        return s!.detail.isEmpty ? 'Cannot reach relay' : s.detail;
      default:
        return 'Starting…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingProvider);
    final links = ref.watch(linksProvider).valueOrNull ?? [];
    final status = ref.watch(relayStatusProvider).valueOrNull;
    final dot = pairing.relay.isEmpty ? kTextFaint : relayStateColor(status);

    return Scaffold(
      appBar: AppBar(title: Text('Pair devices', style: display(fontSize: 19))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Paired devices encrypt everything they send each other, accept each '
            'other\'s files without asking, and stay connected in the background.',
            style: TextStyle(fontSize: 13, color: kTextSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),

          Text('CONNECTED', style: overline()),
          const SizedBox(height: 8),
          if (links.isEmpty)
            Text('No paired device connected right now.',
                style: TextStyle(fontSize: 13.5, color: kTextFaint))
          else
            for (final l in links)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: kOk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.peer.name,
                          style: TextStyle(fontSize: 14, color: kText),
                          overflow: TextOverflow.ellipsis),
                    ),
                    RouteBadge(route: l.route, ip: l.remoteIp),
                  ],
                ),
              ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan code from computer'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'On the computer: PALT → link icon at the top.',
            style: TextStyle(fontSize: 12, color: kTextFaint),
          ),
          const SizedBox(height: 22),

          Text('OR PASTE A CODE', style: overline()),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtl,
            style: mono(fontSize: 12.5, color: kText),
            decoration: InputDecoration(
              hintText: 'palt2:…',
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _join(_codeCtl.text),
              child: const Text('Join'),
            ),
          ),
          const SizedBox(height: 28),

          Text('RELAY SERVER (OPTIONAL)', style: overline()),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: dot.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dot.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_relayText(pairing.relay, status),
                      style: TextStyle(fontSize: 13.5, color: kText)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _relayCtl,
            keyboardType: TextInputType.url,
            style: mono(fontSize: 12.5, color: kText),
            decoration: const InputDecoration(hintText: 'relay address, e.g. 203.0.113.7'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _run(() => ref.read(pairingProvider.notifier).setRelay(_relayCtl.text)),
              child: Text(_relayCtl.text.trim().isEmpty ? 'Turn relay off' : 'Save relay'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Usually comes with the code from your computer.',
            style: TextStyle(fontSize: 12, color: kTextFaint),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, style: TextStyle(color: kDanger, fontSize: 13)),
            ),
          const SizedBox(height: 28),

          Row(
            children: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: pairing.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('This phone\'s pairing code copied')),
                  );
                },
                child: const Text('Copy this phone\'s code'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _confirmReset,
                style: TextButton.styleFrom(foregroundColor: kDanger),
                child: const Text('New code'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen camera that returns the first PALT pairing code it sees.
class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.startsWith('palt2:') || v.startsWith('palt1:')) {
        _done = true;
        Navigator.pop(context, v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scan pairing code', style: display(fontSize: 19))),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kAccent, width: 2),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              'Point at the QR code in PALT on your computer',
              textAlign: TextAlign.center,
              style: TextStyle(color: kText, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
