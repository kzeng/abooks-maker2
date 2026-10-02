import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TaskStore {
  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    final storeDirectory = Directory(p.join(directory.path, 'Abooks Maker'));
    await storeDirectory.create(recursive: true);
    return File(p.join(storeDirectory.path, 'conversion_tasks.json'));
  }

  Future<List<Map<String, dynamic>>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> save(List<Map<String, dynamic>> tasks) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(tasks), flush: true);
  }
}
