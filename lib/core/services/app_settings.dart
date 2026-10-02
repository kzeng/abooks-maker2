import 'package:shared_preferences/shared_preferences.dart';

import 'edge_tts_service.dart';

class AppSettings {
  const AppSettings({
    this.voice = 'zh-CN-YunjianNeural',
    this.ratePercent = 5,
    this.pitchHz = 1,
    this.concurrentTasks = 2,
    this.outputDirectory,
  });

  final String voice;
  final int ratePercent;
  final int pitchHz;
  final int concurrentTasks;
  final String? outputDirectory;

  TtsSettings get tts => TtsSettings(
    voice: voice,
    rate: _signed(ratePercent, '%'),
    pitch: _signed(pitchHz, 'Hz'),
  );

  AppSettings copyWith({
    String? voice,
    int? ratePercent,
    int? pitchHz,
    int? concurrentTasks,
    String? outputDirectory,
    bool clearOutputDirectory = false,
  }) => AppSettings(
    voice: voice ?? this.voice,
    ratePercent: ratePercent ?? this.ratePercent,
    pitchHz: pitchHz ?? this.pitchHz,
    concurrentTasks: concurrentTasks ?? this.concurrentTasks,
    outputDirectory: clearOutputDirectory
        ? null
        : outputDirectory ?? this.outputDirectory,
  );

  static String _signed(int value, String suffix) =>
      '${value >= 0 ? '+' : ''}$value$suffix';
}

class SettingsRepository {
  static const _voiceKey = 'tts.voice';
  static const _rateKey = 'tts.ratePercent';
  static const _pitchKey = 'tts.pitchHz';
  static const _outputKey = 'output.directory';
  static const _concurrentTasksKey = 'tts.concurrentTasks';

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      voice: preferences.getString(_voiceKey) ?? const AppSettings().voice,
      ratePercent:
          preferences.getInt(_rateKey) ?? const AppSettings().ratePercent,
      pitchHz: preferences.getInt(_pitchKey) ?? const AppSettings().pitchHz,
      concurrentTasks:
          preferences.getInt(_concurrentTasksKey) ??
          const AppSettings().concurrentTasks,
      outputDirectory: preferences.getString(_outputKey),
    );
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_voiceKey, settings.voice);
    await preferences.setInt(_rateKey, settings.ratePercent);
    await preferences.setInt(_pitchKey, settings.pitchHz);
    await preferences.setInt(_concurrentTasksKey, settings.concurrentTasks);
    if (settings.outputDirectory == null) {
      await preferences.remove(_outputKey);
    } else {
      await preferences.setString(_outputKey, settings.outputDirectory!);
    }
  }
}
