// Many barcodes per product.
// Server: GET/PUT /products/:id/barcodes, GET /products/by-barcode/:code
import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
import 'screens.dart' show BarcodeScanPage;
import 'theme.dart';
import 'widgets.dart';

/// Holds the barcodes of the product form; saved after the product is saved.
class ProductBarcodesController {
  final codes = <String>[];
  bool dirty = false;
  Future<void> apply(String productId) async {
    await Api.put('/products/${Uri.encodeComponent(productId)}/barcodes',
        {'barcodes': List<String>.from(codes)});
    dirty = false;
  }
}

class ProductBarcodesEditor extends StatefulWidget {
  final String? productId; // null while adding a new product
  final ProductBarcodesController controller;
  const ProductBarcodesEditor(
      {super.key, required this.productId, required this.controller});
  @override
  State<ProductBarcodesEditor> createState() => _ProductBarcodesEditorState();
}

class _ProductBarcodesEditorState extends State<ProductBarcodesEditor> {
  final _in = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null && widget.productId!.isNotEmpty) _load();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get(
          '/products/${Uri.encodeComponent(widget.productId!)}/barcodes');
      if (d is List) {
        widget.controller.codes
          ..clear()
          ..addAll(d.map((e) => '$e'));
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _add([String? v]) async {
    final code = (v ?? _in.text).trim();
    if (code.isEmpty) return;
    final c = widget.controller;
    if (c.codes.contains(code)) {
      setState(() => _err = 'ມີ barcode ນີ້ແລ້ວ');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r =
          await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
      final owner = r is Map ? r['productId'] : null;
      if (owner != null && '$owner' != (widget.productId ?? '')) {
        if (mounted)
          setState(() =>
              _err = 'barcode ນີ້ໃຊ້ກັບສິນຄ້າອື່ນແລ້ວ: ${(r as Map)['name']}');
        return;
      }
    } catch (_) {
      // server re-checks when saving
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    c.codes.add(code);
    c.dirty = true;
    _in.clear();
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final s = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
    if (s != null && s.trim().isNotEmpty) await _add(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = widget.controller;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BARCODE (1 ສິນຄ້າ ມີໄດ້ຫຼາຍ barcode)',
          style: TextStyle(color: p.mut, fontSize: 14)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _in,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              hintText: 'ພິມ ຫຼື ສະແກນ barcode',
              suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'ສະແກນ',
                  onPressed: _scan),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('ເພີ່ມ'),
        ),
      ]),
      if (_err != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_err!,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      if (c.codes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final b in c.codes)
              InputChip(
                avatar: const Icon(Icons.qr_code_2, size: 18),
                label: Text(b),
                onDeleted: () => setState(() {
                  c.codes.remove(b);
                  c.dirty = true;
                }),
              ),
          ]),
        ),
    ]);
  }
}
