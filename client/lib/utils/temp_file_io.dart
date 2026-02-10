import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> writeTempBytes(List<int> bytes, String suffix) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}_$suffix';
  await File(path).writeAsBytes(bytes);
  return path;
}
