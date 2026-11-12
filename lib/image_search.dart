// Shared product search tools: barcode scan + search by photo (take / import, crop).
// Usage:  suffixIcon: SearchTools(onResult: (v) { ctrl.text = v; setState(() => _q = v); })
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'photo_match.dart';
import 'product_images.dart';
import 'screens.dart' show BarcodeScanPage;

List<Map<String, dynamic>> _items(dynamic d) {
  final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
  if (raw is! List) return [];
  return [
    for (final e in raw)
      if (e is Map) Map<String, dynamic>.from(e)
  ];
}

String _s(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return '';
}

Widget _thumb(String v) {
  final ph = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          color: Colors.black12, borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.image_outlined));
  final url = productImageUrl(v);
  if (url.isEmpty) return ph;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ph),
  );
}

/// Scan a barcode -> returns the product name (or null).
Future<String?> searchByBarcode(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  final code = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
  if (code == null || code.isEmpty) return null;
  try {
    final d =
        await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
    final m = d is Map
        ? Map<String, dynamic>.from(d['data'] is Map ? d['data'] : d)
        : <String, dynamic>{};
    final name = _s(m, ['name', 'productName']);
    if (name.isNotEmpty) return name;
  } catch (_) {}
  msg.showSnackBar(SnackBar(content: Text('ບໍ່ພົບສິນຄ້າ: $code')));
  return null;
}

/// Take / import a photo, crop it, then choose from the most similar products.
/// Returns the chosen product name (or null).
Future<String?> searchByPhoto(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  void toast(String m) => msg.showSnackBar(SnackBar(content: Text(m)));

  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('ຖ່າຍຮູບ'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('ເລືອກຮູບຈາກເຄື່ອງ'),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null || !context.mounted) return null;
  final shot = await ImagePicker().pickImage(source: src, imageQuality: 90);
  if (shot == null || !context.mounted) return null;

  final crop = await ImageCropper().cropImage(
    sourcePath: shot.path,
    maxWidth: 800,
    maxHeight: 800,
    compressQuality: 85,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'ຕັດຮູບໃຫ້ເຫັນສິນຄ້າ',
        lockAspectRatio: false,
        initAspectRatio: CropAspectRatioPreset.original,
      ),
      IOSUiSettings(title: 'ຕັດຮູບ'),
    ],
  );
  if (crop == null || !context.mounted) return null;
  final bytes = await crop.readAsBytes();

  toast('ກຳລັງຄົ້ນຫາຈາກຮູບ…');
  final names = <String, String>{};
  final imgs = <String, String>{};
  try {
    for (final m in _items(await Api.get('/products?limit=200'))) {
      final id = _s(m, ['id', 'productId']);
      if (id.isEmpty) continue;
      names[id] = _s(m, ['name', 'productName']);
      imgs[id] = _s(m, ['imageUrl', 'image', 'photo']);
    }
  } catch (e) {
    toast('ໂຫຼດສິນຄ້າບໍ່ສຳເລັດ: $e');
    return null;
  }
  final res = await matchProductPhoto(bytes, imgs);
  if (!context.mounted) return null;
  final top = res.where((e) => names.containsKey(e.key)).take(3).toList();

  final chosen = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('ຮູບທີ່ໃຊ້ຄົ້ນຫາ',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, height: 160, fit: BoxFit.contain),
            ),
          ),
          const Divider(),
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text('ສິນຄ້າທີ່ຄ້າຍກັນ',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          if (top.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('ບໍ່ພົບສິນຄ້າທີ່ຄ້າຍກັນ')),
          for (final e in top)
            ListTile(
              leading: _thumb(imgs[e.key] ?? ''),
              title: Text(names[e.key]!),
              subtitle: Text('${(e.value * 100).round()}%'),
              onTap: () => Navigator.pop(c, names[e.key]),
            ),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('ຄົ້ນຫາໃໝ່'),
            onPressed: () => Navigator.pop(c, '__again__'),
          ),
        ]),
      ),
    ),
  );
  if (chosen == '__again__') {
    return context.mounted ? searchByPhoto(context) : null;
  }
  return (chosen == null || chosen.isEmpty) ? null : chosen;
}

/// Two small buttons (barcode + photo) to put in any search box.
class SearchTools extends StatelessWidget {
  final void Function(String name) onResult;
  const SearchTools({super.key, required this.onResult});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: const Icon(Icons.qr_code_scanner),
        tooltip: 'ສະແກນບາໂຄດ',
        onPressed: () async {
          final r = await searchByBarcode(context);
          if (r != null) onResult(r);
        },
      ),
      IconButton(
        icon: const Icon(Icons.photo_camera_outlined),
        tooltip: 'ຄົ້ນຫາດ້ວຍຮູບ',
        onPressed: () async {
          final r = await searchByPhoto(context);
          if (r != null) onResult(r);
        },
      ),
    ]);
  }
}
