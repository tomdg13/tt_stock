// Many images per product.
// Server routes (already in atm-stock-api, src/products.ts):
//   GET    /products/:id/images            -> [ { id, url: '/uploads/products/x.jpg', sortNo } ]
//   POST   /products/:id/images            multipart/form-data, field "images" (max 10 files, JPG/PNG/WEBP, 8 MB each)
//   DELETE /products/:id/images/:imageId
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'crud.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openProductImages(BuildContext context, Map<String, dynamic> product) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductImagesPage(product)));

String _imgType(String name) {
  final l = name.toLowerCase();
  return l.endsWith('.png') ? 'image/png' : l.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
}

/// Image url from the server ("/uploads/..." is served under /api/uploads/).
String productImageUrl(String v) {
  if (v.isEmpty || v.startsWith('http') || v.startsWith('data:')) return v;
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (v.startsWith('/api/')) return '${base.replaceAll(RegExp(r'/api$'), '')}$v';
  return '$base${v.startsWith('/') ? '' : '/'}$v';
}

class PendingImage {
  final String name, type;
  final Uint8List bytes;
  PendingImage(this.name, this.bytes, [String? type]) : type = (type != null && type.startsWith('image/')) ? type : _imgType(name);
}

/// POST multipart, field "images" (server accepts 10 files per request).
Future<void> uploadProductImages(String productId, List<PendingImage> files) async {
  final uri = Uri.parse('${Api.baseUrl.replaceAll(RegExp(r'/+$'), '')}/products/${Uri.encodeComponent(productId)}/images');
  for (var i = 0; i < files.length; i += 10) {
    final req = http.MultipartRequest('POST', uri);
    if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
    for (final f in files.skip(i).take(10)) {
      final t = f.type.split('/');
      req.files.add(http.MultipartFile.fromBytes('images', f.bytes,
          filename: f.name, contentType: MediaType(t[0], t[1])));
    }
    apiLog('-> POST $uri  multipart field=images files=[${files.skip(i).take(10).map((f) => '${f.name} ${f.type} ${f.bytes.length}B').join(', ')}]');
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 90)));
    apiLog('<- ${res.statusCode} POST $uri\n      ${apiClip(utf8.decode(res.bodyBytes, allowMalformed: true))}');
    if (res.statusCode >= 400) {
      var msg = 'Error ${res.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map && d['message'] != null) msg = d['message'] is List ? (d['message'] as List).join('\n') : '${d['message']}';
      } catch (_) {}
      throw Exception(msg);
    }
  }
}

/// Holds the photos picked in the product form; they are uploaded after the product is saved.
class ProductImagesController {
  final pending = <PendingImage>[];
  Future<void> uploadAll(String productId) async {
    await uploadProductImages(productId, List<PendingImage>.from(pending));
    pending.clear();
  }
}

/// Read-only strip of a product's images (detail page). Tap one to see it larger.
class ProductImageStrip extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const ProductImageStrip(this.items, {super.key});

  Widget _img(String url, {BoxFit fit = BoxFit.cover}) => Image.network(
        url,
        fit: fit,
        headers: Api.token == null ? null : {'Authorization': 'Bearer ${Api.token}'},
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (c, i) {
          final url = productImageUrl(pick(items[i], ['url', 'path', 'imageUrl']));
          return GestureDetector(
            onTap: () => showDialog(
              context: c,
              builder: (d) => Dialog(
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(child: _img(url, fit: BoxFit.contain)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 120, height: 120, child: _img(url)),
            ),
          );
        },
      ),
    );
  }
}

/// Image section used inside the add / edit product form.
class ProductImagesEditor extends StatefulWidget {
  final String? productId; // null while adding a new product
  final ProductImagesController controller;
  const ProductImagesEditor({super.key, required this.productId, required this.controller});
  @override
  State<ProductImagesEditor> createState() => _ProductImagesEditorState();
}

class _ProductImagesEditorState extends State<ProductImagesEditor> {
  Future<dynamic>? _f;
  String get _base => '/products/${Uri.encodeComponent(widget.productId!)}/images';

  @override
  void initState() {
    super.initState();
    if (widget.productId != null && widget.productId!.isNotEmpty) _f = Api.get(_base);
  }

  void _reload() => setState(() {
        _f = Api.get(_base);
      });

  String _url(Map<String, dynamic> m) => productImageUrl(pick(m, ['url', 'path', 'imageUrl']));

  Future<void> _pick() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 80);
    for (final x in picked) {
      widget.controller.pending.add(PendingImage(x.name.isEmpty ? 'image.jpg' : x.name, await x.readAsBytes(), x.mimeType));
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteSaved(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບຮູບນີ້?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ຍົກເລີກ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ລຶບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('$_base/${Uri.encodeComponent(pick(m, ['id']))}');
      _reload();
    } catch (e) {
      if (mounted) toastMsg(context, '$e');
    }
  }

  Widget _box(Widget child, VoidCallback onRemove) => SizedBox(
        width: 84,
        height: 84,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 16, color: Colors.white)),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final pending = widget.controller.pending;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ຮູບພາບສິນຄ້າ', style: TextStyle(color: p.mut, fontSize: 14)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (_f != null)
          FutureBuilder(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const SizedBox(width: 84, height: 84, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              if (s.hasError) {
                return Text('${s.error}', style: TextStyle(color: p.bad, fontSize: 12));
              }
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in asList(s.data))
                  _box(
                    Image.network(
                      _url(m),
                      fit: BoxFit.cover,
                      headers: Api.token == null ? null : {'Authorization': 'Bearer ${Api.token}'},
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                    () => _deleteSaved(m),
                  ),
              ]);
            },
          ),
        for (final x in pending)
          _box(Image.memory(x.bytes, fit: BoxFit.cover), () => setState(() => pending.remove(x))),
        InkWell(
          onTap: _pick,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(border: Border.all(color: p.bd), borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined, color: p.mut),
              Text('ເພີ່ມຮູບ', style: TextStyle(color: p.mut, fontSize: 12)),
            ]),
          ),
        ),
      ]),
      if (pending.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('ຮູບໃໝ່ ${pending.length} ຮູບ ຈະອັບໂຫຼດເມື່ອກົດບັນທຶກ', style: TextStyle(color: p.mut, fontSize: 12)),
        ),
    ]);
  }
}

class ProductImagesPage extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductImagesPage(this.product, {super.key});
  @override
  State<ProductImagesPage> createState() => _ProductImagesPageState();
}

class _ProductImagesPageState extends State<ProductImagesPage> {
  late Future<dynamic> _f = _load();
  bool _busy = false;
  String? _msg;

  String get _id => pick(widget.product, ['id', 'productId']);
  String get _base => '/products/${Uri.encodeComponent(_id)}/images';
  bool get _canEdit => Api.can('PRODUCT_MANAGE');

  Future<dynamic> _load() => Api.get(_base);
  void _reload() => setState(() {
        _f = _load();
      });

  String _url(Map<String, dynamic> m) => productImageUrl(pick(m, ['url', 'path', 'imageUrl']));

  Future<void> _add() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 80);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final files = <PendingImage>[
        for (final x in picked) PendingImage(x.name.isEmpty ? 'image.jpg' : x.name, await x.readAsBytes(), x.mimeType),
      ];
      await uploadProductImages(_id, files);
      if (mounted) setState(() => _msg = 'ອັບໂຫຼດແລ້ວ ${files.length} ຮູບ');
    } catch (e) {
      if (mounted) setState(() => _msg = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບຮູບນີ້?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ຍົກເລີກ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ລຶບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('$_base/${Uri.encodeComponent(pick(m, ['id']))}');
      _reload();
    } catch (e) {
      if (mounted) toastMsg(context, '$e');
    }
  }

  Widget _img(String url, {BoxFit fit = BoxFit.cover}) => Image.network(
        url,
        fit: fit,
        headers: Api.token == null ? null : {'Authorization': 'Bearer ${Api.token}'},
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
        loadingBuilder: (c, w, p) =>
            p == null ? w : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );

  void _view(String url) => showDialog(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(child: _img(url, fit: BoxFit.contain)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final title = pick(widget.product, ['name', 'productName', 'id']);
    return Scaffold(
      appBar: AppBar(
        title: Text('ຮູບ · $title'),
        actions: [
          if (_canEdit)
            TextButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('ເພີ່ມຮູບ'),
              onPressed: _busy ? null : _add,
            ),
        ],
      ),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        if (_msg != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_msg!, style: TextStyle(color: p.mut))),
        Expanded(
          child: FutureBuilder(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return ErrorView(s.error!, _reload);
              final items = asList(s.data);
              if (items.isEmpty) {
                return Center(child: Text('ຍັງບໍ່ມີຮູບ', style: TextStyle(color: p.mut)));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final m = items[i];
                  final url = _url(m);
                  return Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                      onTap: () => _view(url),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _img(url)),
                    ),
                    if (_canEdit)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _delete(m),
                            child: const Padding(
                                padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 18, color: Colors.white)),
                          ),
                        ),
                      ),
                  ]);
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
