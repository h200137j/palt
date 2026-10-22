/// link.dart — one long-lived, encrypted channel to each paired device.
///
/// Live features talk over it as small JSON packets; bulk data still goes
/// over separate transfer connections. Must stay identical to
/// desktop/internal/link/link.go:
///
///   u32 big-endian length | JSON {"t": type, "id": optional, "body": {...}}
///
/// The first packet each way is "identity". When two links to the same
/// device end up open, both sides keep the same one: direct beats relay,
/// otherwise the one dialed by the lower device ID wins.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../palt_conn.dart';
import '../secure/pipe.dart';

const _maxPacket = 1 << 20;
const _pingInterval = Duration(seconds: 20);
const _deadAfter = Duration(seconds: 60);
const _identityWait = Duration(seconds: 15);

class LinkPacket {
  final String t;
  final String? id;
  final Map<String, dynamic>? body;
  const LinkPacket(this.t, {this.id, this.body});

  factory LinkPacket.fromJson(Map<String, dynamic> j) => LinkPacket(
        j['t'] as String? ?? '',
        id: j['id'] as String?,
        body: j['body'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        't': t,
        if (id != null && id!.isNotEmpty) 'id': id,
        if (body != null) 'body': body,
      };
}

@immutable
class LinkIdentity {
  final String id;
  final String name;
  final String os;
  final String version;

  /// Packet types this device understands.
  final List<String> handles;

  /// The dialer's preference for this link over others to the same device
  /// (0 = none); computers dial a faster path (USB cable, Wi-Fi) with a
  /// higher one.
  final int prio;

  const LinkIdentity({
    required this.id,
    required this.name,
    required this.os,
    this.version = '',
    this.handles = const [],
    this.prio = 0,
  });

  factory LinkIdentity.fromJson(Map<String, dynamic> j) => LinkIdentity(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        os: j['os'] as String? ?? '',
        version: j['version'] as String? ?? '',
        handles: ((j['handles'] as List?) ?? const []).whereType<String>().toList(),
        prio: (j['prio'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'os': os, 'version': version, 'handles': handles};

  LinkIdentity withHandles(List<String> h) =>
      LinkIdentity(id: id, name: name, os: os, version: version, handles: h);
}

/// An open channel to one paired device.
class Link {
  final PaltConn _conn;
  final ByteReader _reader;
  final String route;
  final DateTime since = DateTime.now();
  late final LinkIdentity peer;
  late final String _initiator;
  late final int _prio; // the dialer's LinkIdentity.prio
  DateTime _lastRecv = DateTime.now();

  Future<void> _writeChain = Future.value();
  final _done = Completer<void>();
  bool _closed = false;

  Link._(this._conn, this._reader, this.route);

  bool get isClosed => _closed;
  Future<void> get done => _done.future;

  /// The peer's LAN address for direct links, null for relay links.
  String? get remoteIp {
    if (route != Route.direct) return null;
    final c = _conn;
    if (c is SecureConn) return c.remoteAddress;
    if (c is SocketConn) return c.socket.remoteAddress.address;
    return null;
  }

  bool supports(String t) => peer.handles.contains(t);

  final _waiting = <String, Completer<LinkPacket>>{};
  int _nextId = 0;

  /// Sends a packet and waits for the reply carrying the same id (the peer
  /// answers "<t>.reply").
  Future<LinkPacket> request(String t,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 20)}) async {
    final id = 'p${++_nextId}';
    final c = Completer<LinkPacket>();
    _waiting[id] = c;
    try {
      await send(t, body: body, id: id);
      return await Future.any([
        c.future,
        done.then<LinkPacket>((_) => throw const SocketException('link closed')),
      ]).timeout(timeout, onTimeout: () => throw TimeoutException('${peer.name} didn\'t answer'));
    } finally {
      _waiting.remove(id);
    }
  }

  /// Pings the peer and reports whether anything came back within
  /// [timeout]. Used after a network change to drop a dead link in seconds.
  Future<bool> probe([Duration timeout = const Duration(seconds: 3)]) async {
    final start = DateTime.now();
    try {
      await send('ping');
    } catch (_) {
      return false;
    }
    final end = start.add(timeout);
    while (!_closed && DateTime.now().isBefore(end)) {
      if (!_lastRecv.isBefore(start)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  /// Writes one packet. Writes are queued, so calls may overlap.
  Future<void> send(String t, {Map<String, dynamic>? body, String? id}) {
    final bytes = utf8.encode(jsonEncode(LinkPacket(t, id: id, body: body).toJson()));
    if (bytes.length > _maxPacket) {
      return Future.error(ArgumentError('packet $t too large'));
    }
    final frame = Uint8List(4 + bytes.length);
    ByteData.sublistView(frame).setUint32(0, bytes.length);
    frame.setRange(4, frame.length, bytes);
    final next = _writeChain.then((_) async {
      if (_closed) throw const SocketException('link closed');
      _conn.add(frame);
      await _conn.flush();
    });
    _writeChain = next.catchError((Object _) => close());
    return next;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _conn.destroy();
    if (!_done.isCompleted) _done.complete();
  }

  Future<LinkPacket?> _read({Duration timeout = _deadAfter}) async {
    final hdr = await _reader.read(4).timeout(timeout);
    if (hdr == null) return null;
    final n = ByteData.sublistView(hdr).getUint32(0);
    if (n == 0 || n > _maxPacket) throw FormatException('bad packet size $n');
    final body = await _reader.read(n).timeout(timeout);
    if (body == null) return null;
    return LinkPacket.fromJson(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
  }
}

typedef LinkHandler = FutureOr<void> Function(Link link, LinkPacket packet);

/// Owns the links of this device.
class LinkManager {
  final LinkIdentity Function() self;

  final _links = <String, Link>{};
  final _handlers = <String, LinkHandler>{};
  final _changes = StreamController<List<Link>>.broadcast();

  /// Called once a link is established.
  void Function(Link link)? onUp;

  LinkManager(this.self);

  Stream<List<Link>> get changes => _changes.stream;
  List<Link> get links => List.unmodifiable(_links.values);

  /// Registers the handler for packet type [t].
  void handle(String t, LinkHandler h) => _handlers[t] = h;

  List<String> get handledTypes => ['ping', 'pong', ..._handlers.keys];

  Link? get(String id) => _links[id];

  Link? byName(String name) {
    for (final l in _links.values) {
      if (l.peer.name == name) return l;
    }
    return null;
  }

  void closeAll() {
    for (final l in _links.values.toList()) {
      l.close();
    }
  }

  /// Broadcasts a packet to every linked device that handles its type.
  void broadcast(String t, {Map<String, dynamic>? body, bool Function(Link l)? only}) {
    for (final l in links) {
      if (l.supports(t) && (only == null || only(l))) l.send(t, body: body).catchError((Object _) {});
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(links);
  }

  /// Takes over [conn] (an accepted link connection whose bytes are read
  /// through [reader]), exchanges identities and serves packets in the
  /// background. Throws when the link can't be established or loses to an
  /// existing one.
  Future<Link> run(PaltConn conn, ByteReader reader, String route, {required bool initiator}) async {
    final me = self().withHandles(handledTypes);
    final l = Link._(conn, reader, route);
    try {
      await l.send('identity', body: me.toJson());
      final first = await l._read(timeout: _identityWait);
      if (first == null || first.t != 'identity' || first.body == null) {
        throw const FormatException('no identity from peer');
      }
      l.peer = LinkIdentity.fromJson(first.body!);
      if (l.peer.id.isEmpty || l.peer.id == me.id) throw const FormatException('bad identity');
    } catch (e) {
      l.close();
      rethrow;
    }
    l._initiator = initiator ? me.id : l.peer.id;
    l._prio = initiator ? 0 : l.peer.prio;

    final old = _links[l.peer.id];
    if (old != null && !old.isClosed && !_better(l, old, me.id)) {
      // The peer only dials again when it lost the old link (its network
      // changed), so check that the old one still works before refusing.
      if (await old.probe(const Duration(seconds: 2)) || _links[l.peer.id] != old) {
        l.close();
        throw StateError('already linked');
      }
      _log('${l.peer.name}: old link stopped answering, taking the new one');
    }
    _links[l.peer.id] = l;
    old?.close();
    _log('Up: ${l.peer.name} (${l.peer.id}, $route)');
    _emit();
    onUp?.call(l);
    unawaited(_serve(l));
    return l;
  }

  static bool _better(Link a, Link b, String selfId) {
    if (a.route != b.route) return a.route == Route.direct;
    if (a._prio != b._prio) return a._prio > b._prio;
    final low = selfId.compareTo(a.peer.id) < 0 ? selfId : a.peer.id;
    if ((a._initiator == low) != (b._initiator == low)) return a._initiator == low;
    return false;
  }

  Future<void> _serve(Link l) async {
    final ping = Timer.periodic(_pingInterval, (_) {
      l.send('ping').catchError((Object _) {});
    });
    try {
      while (!l.isClosed) {
        final p = await l._read();
        if (p == null) break;
        l._lastRecv = DateTime.now();
        switch (p.t) {
          case 'ping':
            l.send('pong').catchError((Object _) {});
          case 'pong' || 'identity':
            break;
          default:
            final waiter = p.id == null ? null : l._waiting[p.id];
            if (waiter != null) {
              if (!waiter.isCompleted) waiter.complete(p);
              continue;
            }
            final h = _handlers[p.t];
            if (h != null) {
              try {
                await h(l, p);
              } catch (e) {
                _log('Handler ${p.t} failed: $e');
              }
            }
        }
      }
    } catch (_) {
      // read timeout or broken connection: the link is dead
    } finally {
      ping.cancel();
      l.close();
      if (identical(_links[l.peer.id], l)) {
        _links.remove(l.peer.id);
        _log('Down: ${l.peer.name}');
        _emit();
      }
    }
  }

  void _log(String msg) => debugPrint('[link] $msg');
}
