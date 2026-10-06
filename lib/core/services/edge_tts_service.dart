import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:edge_tts/edge_tts.dart';
import 'package:flutter/services.dart';
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
    this.completedFile,
  });

  final int chapter;
  final int totalChapters;
  final String message;
  final double chapterFraction;
  final double? overallFraction;
  final File? completedFile;

  double get fraction => totalChapters == 0
      ? 0
      : overallFraction ??
            ((chapter + chapterFraction).clamp(0.0, totalChapters.toDouble()) /
                totalChapters);
}

class EdgeTtsService {
  static const maxConcurrentConversions = 2;
  static const _storageChannel = MethodChannel('abooks_maker/storage');

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
    bool Function()? isPaused,
    bool resumeExisting = true,
  }) async {
    final root = await _downloadsDirectory();
    var directory = Directory(
      outputDirectory ?? p.join(root.path, 'abooks', _safeName(book.title)),
    );
    try {
      await directory.create(recursive: true);
    } on FileSystemException {
      final fallback = await getApplicationDocumentsDirectory();
      directory = Directory(
        p.join(fallback.path, 'Abooks Maker', _safeName(book.title)),
      );
      await directory.create(recursive: true);
    }

    final outputFiles = List<File?>.filled(book.chapters.length, null);
    final chapterFractions = List<double>.filled(book.chapters.length, 0);
    if (resumeExisting) {
      for (var index = 0; index < book.chapters.length; index++) {
        final file = File(
          p.join(
            directory.path,
            '${(index + 1).toString().padLeft(3, '0')}-${_safeName(book.chapters[index].title)}.mp3',
          ),
        );
        if (await file.exists() && await file.length() > 0) {
          outputFiles[index] = file;
          chapterFractions[index] = 1;
        }
      }
    }
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
        var index = nextIndex++;
        while (index < book.chapters.length && outputFiles[index] != null) {
          index = nextIndex++;
        }
        if (index >= book.chapters.length) return;
        final chapter = book.chapters[index];
        reportProgress(index, 0, '正在生成：${chapter.title}');
        Uint8List audio;
        var attempt = 0;
        var lastProgressReport = DateTime.fromMillisecondsSinceEpoch(0);
        void reportChapterProgress(double fraction) {
          final now = DateTime.now();
          if (fraction < 0.98 &&
              now.difference(lastProgressReport) <
                  const Duration(milliseconds: 250)) {
            return;
          }
          lastProgressReport = now;
          reportProgress(index, fraction, '正在生成：${chapter.title}');
        }

        while (true) {
          while (activeConversions >= adaptiveConcurrency) {
            if (isCancelled?.call() == true) {
              throw const ConversionCancelled();
            }
            while (isPaused?.call() == true) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          while (isPaused?.call() == true) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          activeConversions++;
          try {
            audio = await _synthesizeChapter(
              chapter,
              settings: settings,
              isCancelled: isCancelled,
              isPaused: isPaused,
              onFraction: reportChapterProgress,
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
        chapterFractions[index] = 1;
        onProgress?.call(
          ConversionProgress(
            chapter: index,
            totalChapters: book.chapters.length,
            chapterFraction: 1,
            overallFraction:
                chapterFractions.fold<double>(0, (sum, value) => sum + value) /
                book.chapters.length,
            message: '已完成：${chapter.title}',
            completedFile: file,
          ),
        );
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
    var totalBytes = 0;
    for (final file in orderedFiles) {
      totalBytes += await file.length();
    }
    var copiedBytes = 0;
    var lastMergeReport = DateTime.fromMillisecondsSinceEpoch(0);
    onProgress?.call(
      ConversionProgress(
        chapter: book.chapters.length,
        totalChapters: book.chapters.length,
        overallFraction: 0.99,
        message: '正在合并音频… 0%',
      ),
    );
    final sink = mergedFile.openWrite();
    try {
      for (final file in orderedFiles) {
        await for (final chunk in file.openRead()) {
          sink.add(chunk);
          copiedBytes += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastMergeReport) >=
              const Duration(milliseconds: 250)) {
            lastMergeReport = now;
            final mergeFraction = totalBytes == 0
                ? 1.0
                : (copiedBytes / totalBytes).clamp(0.0, 1.0);
            onProgress?.call(
              ConversionProgress(
                chapter: book.chapters.length,
                totalChapters: book.chapters.length,
                overallFraction: 0.99 + mergeFraction * 0.01,
                message: '正在合并音频… ${(mergeFraction * 100).floor()}%',
              ),
            );
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return ConversionResult(chapters: orderedFiles, mergedFile: mergedFile);
  }

  Future<Directory> _downloadsDirectory() async {
    if (Platform.isAndroid) {
      final publicPath = await _storageChannel.invokeMethod<String>(
        'publicDownloadsDirectory',
      );
      if (publicPath != null && publicPath.isNotEmpty) {
        return Directory(publicPath);
      }
    }
    return await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  }

  Future<Uint8List> _synthesizeChapter(
    BookChapter chapter, {
    required TtsSettings settings,
    required bool Function()? isCancelled,
    required bool Function()? isPaused,
    required void Function(double fraction) onFraction,
  }) async {
    final communicator = Communicate(
      text: chapter.text,
      voice: settings.voice,
      rate: settings.rate,
      pitch: settings.pitch,
      // Sentence-boundary metadata is not needed for audio output. Disabling
      // it reduces websocket payloads and parsing work on mobile devices.
      sentenceBoundary: false,
    );
    final audioBuilder = BytesBuilder(copy: false);
    var audioBytes = 0;
    var reportedTextCharacters = 0;
    try {
      await for (final event in communicator.stream().timeout(
        const Duration(seconds: 45),
      )) {
        if (isCancelled?.call() == true) throw const ConversionCancelled();
        while (isPaused?.call() == true) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (event is AudioDataEvent) {
          audioBuilder.add(event.data);
          audioBytes += event.data.length;
        } else if (event is SentenceBoundaryEvent) {
          // Kept for compatibility if the TTS client emits metadata despite
          // the setting; normal mobile conversions use byte-based progress.
          reportedTextCharacters += event.text.length;
        }
        final textFraction = chapter.text.isEmpty
            ? 0.0
            : reportedTextCharacters / chapter.text.length;
        // Audio size is not a reliable measure of text completion: speech
        // duration, codec framing, and punctuation all change the byte ratio.
        // In particular, a rough bytes-per-character estimate can reach its
        // target near the start of a long chapter. Only turn.end (the normal
        // end of this stream) confirms that every text chunk was synthesized.
        final byteFraction = audioBytes / (chapter.text.length * 1200);
        onFraction(
          (reportedTextCharacters > 0 ? textFraction : byteFraction).clamp(
            0.0,
            0.98,
          ),
        );
      }
    } on TimeoutException {
      // A quiet connection is not proof that the chapter finished. Treat it
      // as a failed synthesis so the task cannot report truncated audio as
      // successful.
      rethrow;
    }
    final audio = audioBuilder.takeBytes();
    if (audio.isEmpty) {
      throw StateError('Edge TTS 没有为“${chapter.title}”返回音频');
    }
    return audio;
  }

  bool _isRateLimited(Object error) {
    final message = error.toString().toLowerCase();
    return error is TimeoutException ||
        message.contains('429') ||
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
