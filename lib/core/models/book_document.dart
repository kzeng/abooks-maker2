class BookDocument {
  const BookDocument({
    required this.title,
    required this.format,
    required this.chapters,
  });

  final String title;
  final BookFormat format;
  final List<BookChapter> chapters;

  int get characterCount =>
      chapters.fold(0, (total, chapter) => total + chapter.text.length);
}

class BookChapter {
  const BookChapter({required this.title, required this.text});

  final String title;
  final String text;
}

enum BookFormat { epub, txt, pdf }

extension BookFormatLabel on BookFormat {
  String get label => switch (this) {
    BookFormat.epub => 'EPUB',
    BookFormat.txt => 'TXT',
    BookFormat.pdf => 'PDF',
  };
}
