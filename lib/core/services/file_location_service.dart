import 'dart:io';

import 'package:flutter/services.dart';

class FileLocationService {
  static const _channel = MethodChannel('abooks_maker/files');

  static Future<void> openDirectory(String path) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openDirectory', {'path': path});
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path], runInShell: false);
    }
  }
}
