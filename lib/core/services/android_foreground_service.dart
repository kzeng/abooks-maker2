import 'dart:io';

import 'package:flutter/services.dart';

class AndroidForegroundService {
  static const _channel = MethodChannel('abooks_maker/foreground_service');

  static Future<void> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    }
  }

  static Future<void> start({required String title, required int total}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('start', {
      'title': title,
      'total': total,
    });
  }

  static Future<void> update({
    required int completed,
    required int total,
    required String message,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('update', {
      'completed': completed,
      'total': total,
      'message': message,
    });
  }

  static Future<void> pause() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('pause');
  }

  static Future<void> resume() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('resume');
  }

  static Future<void> cancel() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('cancel');
  }

  static Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
  }

  static Future<String?> command() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('command');
  }

  static Future<void> clearCommand() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('clearCommand');
  }
}
