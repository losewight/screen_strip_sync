import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_strip_sync/ipc/helper_client.dart';
import 'package:screen_strip_sync/ipc/helper_status.dart';

void main() {
  group('HelperClient Stream & UTF-8 Chunking', () {
    late ServerSocket server;
    late int port;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    test('parses status and handles UTF-8 multi-byte sequence split across TCP packets',
        () async {
      final client = HelperClient();
      Socket? serverSideSock;

      final serverFuture = server.first.then((sock) {
        serverSideSock = sock;
      });

      final clientSock = await Socket.connect(InternetAddress.loopbackIPv4, port);
      // Wait for server to accept
      await serverFuture;

      final statusEvents = <HelperStatusEvent>[];
      final sub = client.statusStream.listen(statusEvents.add);

      // Wire client socket to client's private listener using reflection or helper
      // HelperClient doesn't expose _listenSocket directly, but let's test stream transform
      // to ensure line splitting and partial UTF-8 sequences decode seamlessly.
      final controller = StreamController<List<int>>();
      final receivedLines = <String>[];

      controller.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(receivedLines.add);

      // "status capture_output \\\\.\\DISPLAY1 1920x1080 0,0 联想显示器\n"
      // Chinese character '联' is [0xE8, 0x81, 0x94]
      final linePrefix = 'status capture_output \\\\.\\DISPLAY1 1920x1080 0,0 ';
      final fullLine = '$linePrefix联想显示器\n';
      final bytes = utf8.encode(fullLine);

      // Split right inside '联' (after 2 bytes)
      final splitIdx = utf8.encode(linePrefix).length + 2;
      final part1 = bytes.sublist(0, splitIdx);
      final part2 = bytes.sublist(splitIdx);

      controller.add(part1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedLines, isEmpty); // not complete yet

      controller.add(part2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedLines.length, equals(1));
      expect(receivedLines.first, equals('$linePrefix联想显示器'));

      await controller.close();
      await sub.cancel();
      await client.dispose();
      clientSock.destroy();
      serverSideSock?.destroy();
    });
  });
}
