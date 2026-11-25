import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api.dart';

MediaType _mt(String name) {
  final l = name.toLowerCase();
  if (l.endsWith('.pdf')) return MediaType('application', 'pdf');
  if (l.endsWith('.png')) return MediaType('image', 'png');
  if (l.endsWith('.webp')) return MediaType('image', 'webp');
  if (l.endsWith('.jpg') || l.endsWith('.jpeg')) {
    return MediaType('image', 'jpeg');
  }
  if (l.endsWith('.docx')) {
    return MediaType('application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document');
  }
  if (l.endsWith('.doc')) return MediaType('application', 'msword');
  if (l.endsWith('.xlsx')) {
    return MediaType(
        'application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  if (l.endsWith('.xls')) return MediaType('application', 'vnd.ms-excel');
  return MediaType('application', 'octet-stream');
}

Future<void> _send(
    String planId, List<MapEntry<String, List<int>>> files) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri =
      Uri.parse('$base/stock/buy-plans/${Uri.encodeComponent(planId)}/docs');
  for (var i = 0; i < files.length; i += 10) {
    final req = http.MultipartRequest('POST', uri);
    if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
    for (final f in files.skip(i).take(10)) {
      req.files.add(http.MultipartFile.fromBytes('files', f.value,
          filename: f.key, contentType: _mt(f.key)));
    }
    if (req.files.isEmpty) continue;
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 120)));
    if (res.statusCode >= 400) {
      var msg = 'Error ${res.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map && d['message'] != null) {
          msg = d['message'] is List
              ? (d['message'] as List).join('\n')
              : '${d['message']}';
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }
}

Future<void> uploadPlanDocumentBytes(
        String planId, List<MapEntry<String, List<int>>> files) =>
    _send(planId, files);

Future<void> uploadPlanDocuments(String planId, List<PlatformFile> files) async {
  final list = <MapEntry<String, List<int>>>[];
  for (final f in files) {
    list.add(MapEntry(f.name, await f.readAsBytes()));
  }
  await _send(planId, list);
}
