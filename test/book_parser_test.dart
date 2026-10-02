import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abooks_maker/core/models/book_document.dart';
import 'package:abooks_maker/core/parsers/book_parser.dart';

void main() {
  final parser = BookParser();

  test('parses UTF-8 TXT and removes the BOM', () async {
    final document = await parser.parse(
      fileName: 'sample.txt',
      bytes: Uint8List.fromList(utf8.encode('﻿第一行\n\n第二行')),
    );

    expect(document.format, BookFormat.txt);
    expect(document.title, 'sample');
    expect(document.chapters.single.text, '第一行\n\n第二行');
  });

  test('rejects unsupported formats before reading content', () async {
    expect(
      () => parser.parse(fileName: 'book.mobi', bytes: Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });
}
