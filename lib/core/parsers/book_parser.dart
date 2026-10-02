import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:xml/xml.dart';

import '../models/book_document.dart';

class BookParser {
  Future<BookDocument> parse({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = p.extension(fileName).toLowerCase();
    return switch (extension) {
      '.epub' => _parseEpub(fileName, bytes),
      '.txt' => _parseTxt(fileName, bytes),
      '.pdf' => _parsePdf(fileName, bytes),
      _ => throw FormatException('暂不支持的文件格式：$extension'),
    };
  }

  BookDocument _parseTxt(String fileName, Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    text = _cleanText(text);
    if (text.isEmpty) throw const FormatException('TXT 文件没有可朗读的文字');

    return BookDocument(
      title: p.basenameWithoutExtension(fileName),
      format: BookFormat.txt,
      chapters: [BookChapter(title: '正文', text: text)],
    );
  }

  BookDocument _parseEpub(String fileName, Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (file.isFile) files[_normaliseZipPath(file.name)] = file.readBytes()!;
    }

    final container = files['META-INF/container.xml'];
    if (container == null) throw const FormatException('EPUB 缺少 container.xml');
    final containerXml = XmlDocument.parse(utf8.decode(container));
    final rootfiles = _elementsByLocalName(containerXml, 'rootfile');
    final rootfile = rootfiles.isEmpty ? null : rootfiles.first;
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null) throw const FormatException('EPUB 缺少 OPF 目录');

    final opfBytes = files[_normaliseZipPath(opfPath)];
    if (opfBytes == null) throw const FormatException('找不到 EPUB OPF 文件');
    final opf = XmlDocument.parse(utf8.decode(opfBytes));
    final opfDirectory = p.posix.dirname(_normaliseZipPath(opfPath));
    final manifest = <String, String>{};
    for (final item in _elementsByLocalName(opf, 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id != null && href != null && mediaType.contains('html')) {
        manifest[id] = _normaliseZipPath(p.posix.join(opfDirectory, href));
      }
    }

    final chapters = <BookChapter>[];
    for (final itemref in _elementsByLocalName(opf, 'itemref')) {
      final idref = itemref.getAttribute('idref');
      final path = idref == null ? null : manifest[idref];
      final chapterBytes = path == null ? null : files[path];
      if (path == null || chapterBytes == null) continue;
      final document = html_parser.parse(utf8.decode(chapterBytes));
      final text = _cleanText(document.body?.text ?? document.text ?? '');
      if (text.isEmpty) continue;
      if (_shouldSkipChapter(path, text)) continue;
      final chapterText = chapters.isEmpty ? _removeFrontMatter(text) : text;
      if (chapterText.isEmpty) continue;
      final heading = document.querySelector('h1, h2, h3')?.text.trim();
      chapters.add(
        BookChapter(
          title: heading?.isNotEmpty == true
              ? heading!
              : '第 ${chapters.length + 1} 章',
          text: chapterText,
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 没有可朗读的正文');

    final titles = _elementsByLocalName(opf, 'title');
    final title = titles.isEmpty ? null : titles.first.innerText.trim();
    return BookDocument(
      title: title?.isNotEmpty == true
          ? title!
          : p.basenameWithoutExtension(fileName),
      format: BookFormat.epub,
      chapters: chapters,
    );
  }

  Future<BookDocument> _parsePdf(String fileName, Uint8List bytes) async {
    final document = await PdfDocument.openData(bytes);
    final chapters = <BookChapter>[];
    final buffer = StringBuffer();
    var chapterNumber = 1;
    try {
      for (final page in document.pages) {
        final pageText = await page.loadText();
        final text = _cleanText(pageText?.fullText ?? '');
        if (text.isEmpty) continue;
        if (buffer.length + text.length > 30000 && buffer.isNotEmpty) {
          chapters.add(
            BookChapter(title: '第 $chapterNumber 节', text: buffer.toString()),
          );
          chapterNumber++;
          buffer.clear();
        }
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
      if (buffer.isNotEmpty) {
        chapters.add(
          BookChapter(title: '第 $chapterNumber 节', text: buffer.toString()),
        );
      }
    } finally {
      document.dispose();
    }
    if (chapters.isEmpty) {
      throw const FormatException('PDF 没有可提取的文字，扫描版需要 OCR（暂不支持）');
    }
    return BookDocument(
      title: p.basenameWithoutExtension(fileName),
      format: BookFormat.pdf,
      chapters: chapters,
    );
  }

  String _cleanText(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  bool _shouldSkipChapter(String path, String text) {
    final lowerPath = path.toLowerCase();
    final lowerText = text.toLowerCase();
    final adSignals = RegExp(
      r'公众号|电子书搜索下载|书单分享|网站[:：]|资源分享|chenjin5\.com|welib\.org',
    ).allMatches(lowerText).length;
    final looksLikeAdvertisement =
        (lowerPath.contains('ad') || adSignals >= 2) && text.length < 3000;
    final chapterSignals = RegExp(
      r'第\s*(?:\d+|[一二三四五六七八九十百千万]+)\s*章',
    ).allMatches(text).length;
    final looksLikeContents =
        text.length < 15000 &&
        chapterSignals >= 3 &&
        (lowerText.contains('目录') || chapterSignals >= 8);
    return looksLikeAdvertisement || looksLikeContents;
  }

  String _removeFrontMatter(String text) {
    final match = RegExp(r'第\s*(?:\d+|[一二三四五六七八九十百千万]+)\s*章').firstMatch(text);
    if (match == null || match.start == 0) return text;
    return text.substring(match.start).trim();
  }

  String _normaliseZipPath(String value) =>
      p.posix.normalize(value).replaceFirst('./', '');

  Iterable<XmlElement> _elementsByLocalName(
    XmlDocument document,
    String name,
  ) => document.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == name,
  );
}
