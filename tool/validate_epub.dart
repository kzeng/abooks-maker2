import 'dart:io';
import 'dart:typed_data';

import 'package:abooks_maker/core/parsers/book_parser.dart';
import 'package:abooks_maker/core/models/book_document.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/validate_epub.dart /path/to/book.epub',
    );
    exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }
  try {
    final document = await BookParser().parse(
      fileName: file.uri.pathSegments.last,
      bytes: Uint8List.fromList(await file.readAsBytes()),
    );
    stdout.writeln('title=${document.title}');
    stdout.writeln('format=${document.format.label}');
    stdout.writeln('chapters=${document.chapters.length}');
    stdout.writeln('characters=${document.characterCount}');
    for (var i = 0; i < document.chapters.length && i < 10; i++) {
      final chapter = document.chapters[i];
      final preview = chapter.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      stdout.writeln(
        '${i + 1}. ${chapter.title} chars=${chapter.text.length} '
        'preview=${preview.substring(0, preview.length > 80 ? 80 : preview.length)}',
      );
    }
  } on Object catch (error) {
    stderr.writeln('EPUB validation failed: $error');
    exitCode = 1;
  }
}
