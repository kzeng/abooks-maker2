import 'dart:io';

import 'package:edge_tts/edge_tts.dart';

Future<void> main() async {
  final output = File('/tmp/abooks-edge-tts-test.mp3');
  final bytes = await Communicate(
    text: '这是 Edge TTS 转换测试，当前声音和网络连接正常。',
    voice: 'zh-CN-YunjianNeural',
    rate: '+5%',
    pitch: '+1Hz',
  ).toBytes();
  await output.writeAsBytes(bytes, flush: true);
  stdout.writeln('audio=${output.path} bytes=${bytes.length}');
}
