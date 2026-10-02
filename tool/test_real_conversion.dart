import 'dart:io';
import 'dart:typed_data';

import 'package:abooks_maker/core/parsers/book_parser.dart';
import 'package:edge_tts/edge_tts.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/test_real_conversion.dart EPUB OUTPUT_DIR',
    );
    exitCode = 2;
    return;
  }
  final input = File(args[0]);
  final parser = BookParser();
  final book = await parser.parse(
    fileName: input.path,
    bytes: await input.readAsBytes(),
  );
  stdout.writeln(
    'book=${book.title} chapters=${book.chapters.length} chars=${book.characterCount}',
  );
  final outputDirectory = Directory(args[1])..createSync(recursive: true);
  final outputFiles = <File>[];
  for (var index = 0; index < book.chapters.length; index++) {
    final chapter = book.chapters[index];
    final builder = BytesBuilder(copy: false);
    var audioBytes = 0;
    var reportedCharacters = 0;
    var lastReportedPercent = -1;
    await for (final event in Communicate(
      text: chapter.text,
      voice: 'zh-CN-YunjianNeural',
      rate: '+5%',
      pitch: '+1Hz',
      sentenceBoundary: true,
    ).stream()) {
      if (event is AudioDataEvent) {
        builder.add(event.data);
        audioBytes += event.data.length;
      } else if (event is SentenceBoundaryEvent) {
        reportedCharacters += event.text.length;
      }
      final textFraction = reportedCharacters / chapter.text.length;
      final byteFraction = audioBytes / (chapter.text.length * 30);
      final chapterFraction =
          (reportedCharacters > 0 ? textFraction : byteFraction).clamp(
            0.0,
            0.98,
          );
      final fraction = (index + chapterFraction) / book.chapters.length;
      final percent = (fraction * 100).floor();
      if (percent != lastReportedPercent) {
        lastReportedPercent = percent;
        stdout.writeln(
          'progress=$percent% chapter=$index/${book.chapters.length}',
        );
      }
    }
    final file = File('${outputDirectory.path}/${index + 1}.mp3');
    await file.writeAsBytes(builder.takeBytes(), flush: true);
    outputFiles.add(file);
  }
  stdout.writeln('completed chapters=${outputFiles.length}');
}
