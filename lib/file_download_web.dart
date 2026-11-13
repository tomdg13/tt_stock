import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<bool> downloadBytes(
    Uint8List bytes, String fileName, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
