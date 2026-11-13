// One picture per terminal type (TT_TERMINAL_TYPES.IMAGE_FILE).
// Server routes: POST /terminal-types/:id/image (multipart, field "image"), DELETE /terminal-types/:id/image
// Files are served from /api/uploads/terminal-types/<file>
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'product_images.dart';
import 'theme.dart';

String terminalTypeImageUrl(String file) {
  if (file.isEmpty) return '';
  if (file.startsWith('/') || file.startsWith('http')) {
    return productImageUrl(file);
  }
  return productImageUrl('/uploads/terminal-types/$file');
}

/// Type picture, or a plain icon when the type has none.
Widget typeThumb(BuildContext context, String file,
    {double size = 44, IconData icon = Icons.memory}) {
  final p = pal(context);
  final ph =
      SizedBox(width: size, height: size, child: Icon(icon, color: p.mut));
  final url = terminalTypeImageUrl(file);
  if (url.isEmpty) return ph;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(url,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ph),
  );
}

/// Holds the picture chosen in the type form; applied after the type is saved.
class TypeImageController {
  PendingImage? picked;
  bool removed = false;
  bool get dirty => picked != null || removed;

  Future<void> apply(String typeId) async {
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri =
        Uri.parse('$base/terminal-types/${Uri.encodeComponent(typeId)}/image');
    final img = picked;
    if (img != null) {
      final req = http.MultipartRequest('POST', uri);
      if (Api.token != null) {
        req.headers['Authorization'] = 'Bearer ${Api.token}';
      }
      final t = img.type.split('/');
      req.files.add(http.MultipartFile.fromBytes('image', img.bytes,
          filename: img.name, contentType: MediaType(t[0], t[1])));
      apiLog(
          '-> POST $uri  multipart field=image file=[${img.name} ${img.type} ${img.bytes.length}B]');
      final res = await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 60)));
      apiLog(
          '<- ${res.statusCode} POST $uri\n      ${apiClip(utf8.decode(res.bodyBytes, allowMalformed: true))}');
      if (res.statusCode >= 400) {
        var msg = 'Error ${res.statusCode}';
        try {
          final d = jsonDecode(utf8.decode(res.bodyBytes));
          if (d is Map && d['message'] != null) msg = '${d['message']}';
        } catch (_) {}
        throw Exception(msg);
      }
    } else if (removed) {
      await Api.delete('/terminal-types/${Uri.encodeComponent(typeId)}/image');
    }
    picked = null;
    removed = false;
  }
}

/// Picture field used in the terminal type form.
class TypeImageEditor extends StatefulWidget {
  final String existingFile;
  final TypeImageController controller;
  const TypeImageEditor(
      {super.key, required this.existingFile, required this.controller});
  @override
  State<TypeImageEditor> createState() => _TypeImageEditorState();
}

class _TypeImageEditorState extends State<TypeImageEditor> {
  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    widget.controller.picked =
        PendingImage(x.name.isEmpty ? 'image.jpg' : x.name, bytes, x.mimeType);
    widget.controller.removed = false;
    if (mounted) setState(() {});
  }

  void _remove() {
    widget.controller.picked = null;
    widget.controller.removed = widget.existingFile.isNotEmpty;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = widget.controller;
    Widget? preview;
    if (c.picked != null) {
      preview = Image.memory(c.picked!.bytes, fit: BoxFit.cover);
    } else if (!c.removed && widget.existingFile.isNotEmpty) {
      preview = Image.network(terminalTypeImageUrl(widget.existingFile),
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image_outlined)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ຮູບປະເພດ', style: TextStyle(color: p.mut, fontSize: 14)),
      const SizedBox(height: 6),
      Row(children: [
        if (preview != null)
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: preview),
              Positioned(
                top: 2,
                right: 2,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _remove,
                    child: const Padding(
                        padding: EdgeInsets.all(3),
                        child:
                            Icon(Icons.close, size: 16, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          )
        else
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  border: Border.all(color: p.bd),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, color: p.mut),
                    Text('ເພີ່ມຮູບ',
                        style: TextStyle(color: p.mut, fontSize: 12)),
                  ]),
            ),
          ),
        const SizedBox(width: 12),
        if (preview != null)
          OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('ປ່ຽນຮູບ')),
      ]),
    ]);
  }
}
