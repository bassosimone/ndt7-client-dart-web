import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:math';
import 'dart:typed_data';

void _updateUI(String subtest, String content) {
  querySelector('#ndt7_' + subtest).text = content;
}

String _fmtspeed(double speed) {
  const base = 1000.0;
  if (speed < base) {
    return speed.toStringAsFixed(0) + ' b/s';
  }
  speed /= base;
  if (speed < base) {
    return speed.toStringAsFixed(2) + ' kb/s';
  }
  speed /= base;
  if (speed < base) {
    return speed.toStringAsFixed(2) + ' Mb/s';
  }
  speed /= base;
  return speed.toStringAsFixed(2) + ' Gb/s';
}

WebSocket _makeWebSocket(String fqdn, String subtest) {
  return WebSocket('wss://' + fqdn + '/ndt/v7/' + subtest, [
    'net.measurementlab.ndt.v7',
  ]);
}

void _download(String fqdn) async {
  const timeo = Duration(seconds: 4);
  final wss = _makeWebSocket(fqdn, 'download');
  await wss.onOpen.first.timeout(timeo);
  var nbytes = 0;
  final begin = DateTime.now();
  var prev = begin;
  while (DateTime.now().difference(begin) < const Duration(seconds: 10)) {
    final message = await wss.onMessage.first.timeout(timeo);
    if (message.data.runtimeType == String) {
      nbytes += message.data.length;
    } else {
      nbytes += message.data.size;
    }
    final now = DateTime.now();
    if (now.difference(prev) < const Duration(milliseconds: 250)) {
      continue;
    }
    prev = now;
    final elapsed = now.difference(begin).inMicroseconds;
    final speed = nbytes / elapsed * Duration.microsecondsPerSecond * 8;
    _updateUI('download', _fmtspeed(speed));
  }
}

void _uploop(WebSocket wss, Completer<void> done, Uint8List message,
    DateTime begin, DateTime prev, int nbytes) {
  if (DateTime.now().difference(begin) >= const Duration(seconds: 10)) {
    wss.close();
    done.complete();
    return;
  }
  final objective = 1 << 20;
  while (wss.bufferedAmount < objective) {
    wss.sendByteBuffer(message.buffer);
    nbytes += message.buffer.lengthInBytes;
  }
  final now = DateTime.now();
  if (now.difference(prev) >= const Duration(milliseconds: 250)) {
    prev = now;
    final elapsed = now.difference(begin).inMicroseconds;
    final realBytes = (nbytes - wss.bufferedAmount);
    final speed = realBytes / elapsed * Duration.microsecondsPerSecond * 8;
    _updateUI('upload', _fmtspeed(speed));
  }
  Timer.run(() => _uploop(wss, done, message, begin, prev, nbytes));
}

Future<void> _upload(String fqdn) async {
  var rng = Random();
  const timeo = Duration(seconds: 4);
  final wss = _makeWebSocket(fqdn, 'upload');
  final message = Uint8List.fromList(
      List.generate(1 << 13, (_) => rng.nextInt(256)));
  await wss.onOpen.first.timeout(timeo);
  final done = Completer<void>();
  final begin = DateTime.now();
  Timer.run(() => _uploop(wss, done, message, begin, begin, 0));
  return done.future;
}

Future<String> _locateServer() async {
  final locateURL = 'https://locate.measurementlab.net/ndt7';
  final data = await HttpRequest.getString(locateURL);
  final server = json.decode(data)['fqdn'];
  return server;
}

void main() async {
  _updateUI('download', 'download');
  _updateUI('upload', 'upload');
  final server = await _locateServer();
  await _download(server);
  await _upload(server);
}
