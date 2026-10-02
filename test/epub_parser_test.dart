import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abooks_maker/core/models/book_document.dart';
import 'package:abooks_maker/core/parsers/book_parser.dart';

void main() {
  test('parses an EPUB using OPF spine order and strips HTML', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '''<?xml version="1.0"?><container version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '''<?xml version="1.0"?><package><metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">罗马人的故事</dc:title></metadata><manifest><item id="copyright" href="copyright.xhtml" media-type="application/xhtml+xml"/><item id="two" href="text/two.xhtml" media-type="application/xhtml+xml"/><item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/><item id="ad" href="ad.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="copyright"/><itemref idref="one"/><itemref idref="ad"/><itemref idref="two"/></spine></package>''',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/copyright.xhtml',
          '<html><body>版权页 版权所有 出版社 ISBN 978-7-0000-0000-0</body></html>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/text/one.xhtml',
          '<html><body><p>版权和目录</p><h1>第1章</h1><p>第一段正文。</p></body></html>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/ad.xhtml',
          '<html><body>读累了记得休息一会哦~ 公众号：广告推广 电子书搜索下载</body></html>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/text/two.xhtml',
          '<html><body><h2>第二章</h2><p>第二段正文。</p></body></html>',
        ),
      );

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final document = await BookParser().parse(
      fileName: 'roman.epub',
      bytes: bytes,
    );

    expect(document.format, BookFormat.epub);
    expect(document.title, '罗马人的故事');
    expect(document.chapters.map((chapter) => chapter.title), ['第1章', '第二章']);
    expect(document.chapters.first.text, startsWith('第1章'));
    expect(document.chapters.first.text, contains('第一段正文'));
    expect(document.chapters.first.text, isNot(contains('<p>')));
  });
}
