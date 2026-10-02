import 'dart:io';
import 'dart:typed_data';

import 'package:edge_tts/edge_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_document.dart';

class TtsSettings {
  const TtsSettings({
    this.voice = 'zh-CN-YunjianNeural',
    this.rate = '+5%',
    this.pitch = '+1Hz',
  });

  final String voice;
  final String rate;
  final String pitch;
}

class ConversionCancelled implements Exception {
  const ConversionCancelled();
}

class ConversionResult {
  const ConversionResult({required this.chapters, required this.mergedFile});

  final List<File> chapters;
  final File mergedFile;
}

class ConversionProgress {
  const ConversionProgress({
    required this.chapter,
    required this.totalChapters,
    required this.message,
    this.chapterFraction = 0,
    this.overallFraction,
  });

  final int chapter;
  final int totalChapters;
  final String message;
  final double chapterFraction;
  final double? overallFraction;

  double get fraction => totalChapters == 0
      ? 0
      : overallFraction ??
            ((chapter + chapterFraction).clamp(0.0, totalChapters.toDouble()) /
                totalChapters);
}

class EdgeTtsService {
  static const maxConcurrentConversions = 2;

  Future<File> preview({TtsSettings settings = const TtsSettings()}) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'Abooks Maker'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'tts-preview.mp3'));
    final audio = await Communicate(
      text: '这是当前 Edge TTS 设置的试听效果。声音、语速和音调可以在设置中调整。',
      voice: settings.voice,
      rate: settings.rate,
      pitch: settings.pitch,
    ).toBytes();
    await file.writeAsBytes(audio, flush: true);
    return file;
  }

  Future<ConversionResult> convert(
    BookDocument book, {
    TtsSettings settings = const TtsSettings(),
    String? outputDirectory,
    int maxConcurrent = EdgeTtsService.maxConcurrentConversions,
    void Function(ConversionProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      outputDirectory ??
          p.join(root.path, 'Abooks Maker', _safeName(book.title)),
    );
    await directory.create(recursive: true);

    final outputFiles = List<File?>.filled(book.chapters.length, null);
    final chapterFractions = List<double>.filled(book.chapters.length, 0);
    var adaptiveConcurrency = maxConcurrent.clamp(1, 10).toInt();
    var activeConversions = 0;
    var nextIndex = 0;
    void reportProgress(int index, double fraction, String message) {
      chapterFractions[index] = fraction;
      final overall =
          chapterFractions.fold<double>(0, (sum, value) => sum + value) /
          book.chapters.length;
      onProgress?.call(
        ConversionProgress(
          chapter: index,
          totalChapters: book.chapters.length,
          chapterFraction: fraction,
          overallFraction: overall,
          message: message,
        ),
      );
    }

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) throw const ConversionCancelled();
        final index = nextIndex++;
        if (index >= book.chapters.length) return;
        final chapter = book.chapters[index];
        reportProgress(index, 0, '正在生成：${chapter.title}');
        Uint8List audio;
        var attempt = 0;
        while (true) {
          while (activeConversions >= adaptiveConcurrency) {
            if (isCancelled?.call() == true) {
              throw const ConversionCancelled();
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          activeConversions++;
          try {
            audio = await _synthesizeChapter(
              chapter,
              settings: settings,
              isCancelled: isCancelled,
              onFraction: (fraction) =>
                  reportProgress(index, fraction, '正在生成：${chapter.title}'),
            );
            break;
          } catch (error) {
            if (!_isRateLimited(error) || attempt >= 2) rethrow;
            attempt++;
            if (adaptiveConcurrency > 1) {
              adaptiveConcurrency = (adaptiveConcurrency / 2).ceil();
            }
            reportProgress(index, chapterFractions[index], '请求受限，降低并发后重试');
            await Future<void>.delayed(Duration(seconds: attempt * 2));
          } finally {
            activeConversions--;
          }
        }
        final file = File(
          p.join(
            directory.path,
            '${(index + 1).toString().padLeft(3, '0')}-${_safeName(chapter.title)}.mp3',
          ),
        );
        await file.writeAsBytes(audio, flush: true);
        outputFiles[index] = file;
        reportProgress(index, 1, '已完成：${chapter.title}');
      }
    }

    final safeConcurrency = maxConcurrent.clamp(1, 10).toInt();
    final workerCount = book.chapters.length < safeConcurrency
        ? book.chapters.length
        : safeConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    final orderedFiles = outputFiles.whereType<File>().toList();
    if (orderedFiles.isEmpty) throw const ConversionCancelled();
    final mergedFile = File(
      p.join(directory.path, '${_safeName(book.title)}.mp3'),
    );
    final mergedBytes = BytesBuilder(copy: false);
    for (final file in orderedFiles) {
      mergedBytes.add(await file.readAsBytes());
    }
    await mergedFile.writeAsBytes(mergedBytes.takeBytes(), flush: true);
    return ConversionResult(chapters: orderedFiles, mergedFile: mergedFile);
  }

  Future<Uint8List> _synthesizeChapter(
    BookChapter chapter, {
    required TtsSettings settings,
    required bool Function()? isCancelled,
    required void Function(double fraction) onFraction,
  }) async {
    final communicator = Communicate(
      text: chapter.text,
      voice: settings.voice,
      rate: settings.rate,
      pitch: settings.pitch,
      sentenceBoundary: true,
    );
    final audioBuilder = BytesBuilder(copy: false);
    var audioBytes = 0;
    var reportedTextCharacters = 0;
    await for (final event in communicator.stream()) {
      if (isCancelled?.call() == true) throw const ConversionCancelled();
      if (event is AudioDataEvent) {
        audioBuilder.add(event.data);
        audioBytes += event.data.length;
      } else if (event is SentenceBoundaryEvent) {
        reportedTextCharacters += event.text.length;
      }
      final textFraction = chapter.text.isEmpty
          ? 0.0
          : reportedTextCharacters / chapter.text.length;
      final byteFraction =
          audioBytes / (chapter.text.length * 30).clamp(1, double.infinity);
      onFraction(
        (reportedTextCharacters > 0 ? textFraction : byteFraction).clamp(
          0.0,
          0.98,
        ),
      );
    }
    return audioBuilder.takeBytes();
  }

  bool _isRateLimited(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('429') ||
        message.contains('too many requests') ||
        message.contains('rate limit') ||
        message.contains('throttl') ||
        message.contains('quota') ||
        message.contains('service unavailable') ||
        message.contains('503');
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();
    return cleaned.isEmpty ? '未命名' : cleaned;
  }
}
