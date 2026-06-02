import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:utp/src/utp_data.dart';
import 'package:utp/utp.dart';
import 'package:test/test.dart';

void main() {
  group('UTPPacket header serialization', () {
    test('header-only round-trip (no extension) is 20 bytes', () {
      var time = DateTime.now().microsecondsSinceEpoch;
      var p = UTPPacket(ST_RESET, 1, time, 2, 3, 4, 5);
      var data = p.getBytes();
      expect(data, isNotNull);
      expect(data!.length, equals(20));

      var header = parseData(data)!;
      expect(header.type, equals(ST_RESET));
      expect(header.version, equals(VERSION));
      // sendTime is written/read as uint32.
      expect(header.sendTime, equals(time & MAX_UINT32));
      expect(header.timestampDifference, equals(2));
      expect(header.wnd_size, equals(3));
      expect(header.seq_nr, equals(4));
      expect(header.ack_nr, equals(5));
      // No extension => payload offset sits right after the 20 byte header.
      expect(header.offset, equals(20));
    });

    test('every packet type round-trips its type field', () {
      for (var type in [ST_DATA, ST_FIN, ST_STATE, ST_RESET, ST_SYN]) {
        var p = UTPPacket(type, 7, 100, 0, 1000, 10, 20);
        var parsed = parseData(p.getBytes())!;
        expect(parsed.type, equals(type), reason: 'type $type');
        expect(parsed.connectionId, equals(7));
        expect(parsed.seq_nr, equals(10));
        expect(parsed.ack_nr, equals(20));
      }
    });

    test('constructor masks oversized fields to their uint width', () {
      // connection id / seq / ack are uint16, wnd_size is uint32.
      var p = UTPPacket(ST_DATA, MAX_UINT16 + 5, 0, 0, MAX_UINT32 + 9,
          MAX_UINT16 + 1, MAX_UINT16 + 2);
      expect(p.connectionId, equals((MAX_UINT16 + 5) & MAX_UINT16));
      expect(p.wnd_size, equals((MAX_UINT32 + 9) & MAX_UINT32));
      expect(p.seq_nr, equals((MAX_UINT16 + 1) & MAX_UINT16));
      expect(p.ack_nr, equals((MAX_UINT16 + 2) & MAX_UINT16));
    });

    test('payload round-trips through serialize/parse', () {
      var payload = Uint8List.fromList(List<int>.generate(64, (i) => i & 0xff));
      var p = UTPPacket(ST_DATA, 1, 0, 0, 0, 1, 2, payload: payload);
      var parsed = parseData(p.getBytes())!;
      // parsed.payload holds the full datagram; data begins at offset.
      var got = parsed.payload!.sublist(parsed.offset);
      expect(got, equals(payload));
    });
  });

  group('parseData edge cases', () {
    test('null input returns null', () {
      expect(parseData(null), isNull);
    });

    test('empty input returns null', () {
      expect(parseData(<int>[]), isNull);
    });

    test('truncated packet (<20 bytes) returns null', () {
      expect(parseData(List<int>.filled(19, 0)), isNull);
    });

    test('exactly 20 bytes parses', () {
      expect(parseData(List<int>.filled(20, 0)), isNotNull);
    });
  });

  group('SelectiveACK extension', () {
    test('set/get acked sequence numbers', () {
      var ack = 2;
      var ext = SelectiveACK(ack, 4, Uint8List(4));
      expect(ext.getAckeds(), isEmpty);

      // base+0 (== ack+1) is implicitly acked, never encoded.
      ext.setAcked(2);
      expect(ext.getAckeds(), isEmpty);

      ext.setAcked(12);
      ext.setAcked(7);
      var ackeds = ext.getAckeds();
      expect(ackeds, isNotEmpty);
      expect(ackeds, containsAll(<int>[7, 12]));
    });

    test('extension id is 1 and is a known extension', () {
      var ext = SelectiveACK(0, 4, Uint8List(4));
      expect(ext.id, equals(1));
      expect(ext.isUnKnownExtension, isFalse);
    });

    test('round-trips through a packet', () {
      var ext = SelectiveACK(2, 4, Uint8List(4));
      ext.setAcked(12);
      ext.setAcked(7);
      var ackeds = ext.getAckeds();

      var packet = UTPPacket(ST_STATE, 1, 0, 0, 0, 1, 2);
      packet.addExtension(ext);
      var parsed = parseData(packet.getBytes())!;

      expect(parsed.type, equals(packet.type));
      expect(parsed.seq_nr, equals(packet.seq_nr));
      expect(parsed.ack_nr, equals(packet.ack_nr));
      expect(parsed.extensionList, isNotEmpty);

      var ext1 = parsed.extensionList[0] as SelectiveACK;
      expect(ext1.id, equals(ext.id));
      expect(ext1.length, equals(ext.length));
      expect(ext1.getAckeds(), equals(ackeds));
    });

    test('builds a selective ack covering a buffer of seqs', () {
      var buffer = <int>[];
      var lastRemoteSeq = 10;
      var random = Random();
      for (var i = 0; i < 32; i++) {
        var r = random.nextInt(100);
        if (r > 11 && !buffer.contains(r)) buffer.add(r);
      }
      buffer.sort();
      var len = buffer.last - lastRemoteSeq;
      var c = len ~/ 32;
      var r = len.remainder(32);
      if (r != 0) c++;
      var payload = List<int>.filled(c * 32, 0);
      var selectiveAck = SelectiveACK(lastRemoteSeq, payload.length, payload);
      for (var seq in buffer) {
        selectiveAck.setAcked(seq);
      }
      expect(selectiveAck.getAckeds(), equals(buffer));
    });

    test('unknown extension is preserved and flagged unknown', () {
      var unknown = Extension(2, 4, Uint8List(4));
      expect(unknown.isUnKnownExtension, isTrue);
      var packet = UTPPacket(ST_STATE, 1, 0, 0, 0, 1, 2);
      packet.addExtension(unknown);
      var parsed = parseData(packet.getBytes())!;
      expect(parsed.extensionList.length, equals(1));
      expect(parsed.extensionList[0].id, equals(2));
      expect(parsed.extensionList[0].isUnKnownExtension, isTrue);
    });
  });

  group('compareSeqLess (uint16 wrap-around)', () {
    test('plain ordering without wrap', () {
      expect(compareSeqLess(1, 2), isTrue);
      expect(compareSeqLess(2, 1), isFalse);
      expect(compareSeqLess(5, 5), isFalse);
    });

    test('wraps near the uint16 boundary', () {
      // 0 is "after" 65535 by a distance of 1.
      expect(compareSeqLess(MAX_UINT16, 0), isTrue);
      expect(compareSeqLess(0, MAX_UINT16), isFalse);
    });

    test('antisymmetric for distinct values', () {
      var rnd = Random(42);
      for (var i = 0; i < 200; i++) {
        var a = rnd.nextInt(MAX_UINT16 + 1);
        var b = rnd.nextInt(MAX_UINT16 + 1);
        if (a == b) continue;
        expect(compareSeqLess(a, b), isNot(equals(compareSeqLess(b, a))),
            reason: 'a=$a b=$b');
      }
    });
  });

  group('UTPPacket comparison operators', () {
    test('equality is by sequence number', () {
      var a = UTPPacket(ST_DATA, 1, 0, 0, 0, 5, 0);
      var b = UTPPacket(ST_DATA, 2, 0, 0, 0, 5, 0);
      var c = UTPPacket(ST_DATA, 1, 0, 0, 0, 6, 0);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('ordering follows compareSeqLess', () {
      var a = UTPPacket(ST_DATA, 1, 0, 0, 0, 5, 0);
      var b = UTPPacket(ST_DATA, 1, 0, 0, 0, 6, 0);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= b, isTrue);
      expect(b >= a, isTrue);
    });
  });

  group('loopback integration', () {
    late ServerUTPSocket server;
    late UTPSocketClient client;

    setUp(() async {
      server = await ServerUTPSocket.bind(InternetAddress.loopbackIPv4, 0);
      client = UTPSocketClient();
    });

    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('client connects and server receives sent bytes', () async {
      final received = <int>[];
      final gotData = Completer<void>();
      final message = utf8.encode('hello uTP loopback');

      server.listen((socket) {
        socket.listen((data) {
          received.addAll(data);
          if (received.length >= message.length && !gotData.isCompleted) {
            gotData.complete();
          }
        });
      });

      var socket = await client
          .connect(InternetAddress.loopbackIPv4, server.port)
          .timeout(Duration(seconds: 5));
      expect(socket, isNotNull);
      expect(socket!.isConnected, isTrue);

      socket.add(message);

      await gotData.future.timeout(Duration(seconds: 5));
      expect(received, equals(message));
    });
  });
}
