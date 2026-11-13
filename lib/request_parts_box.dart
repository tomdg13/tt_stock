import 'package:flutter/material.dart';
import 'api.dart';
import 'pages.dart';
import 'widgets.dart';
import 'terminal_actions.dart' show ScanBarcodePage;

/// Same look as the repair page: scan + pick buttons, rows with qty and delete.
class RequestPartsBox extends StatefulWidget {
  final List<Line> lines;
  const RequestPartsBox(this.lines, {super.key});
  @override
  State<RequestPartsBox> createState() => _RequestPartsBoxState();
}

class _RequestPartsBoxState extends State<RequestPartsBox> {
  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _add(Map<String, dynamic> prod) {
    final id = '${prod['id']}';
    for (final l in widget.lines) {
      if ('${l.product['id']}' == id) {
        setState(() => l.qty++);
        return;
      }
    }
    setState(() => widget.lines.add(Line(prod, 1)));
  }

  Future<void> _pick() async {
    final prod = await pickProduct(context);
    if (prod != null) _add(prod);
  }

  Future<void> _scan() async {
    final nav = Navigator.of(context);
    while (mounted) {
      final raw = await nav.push<String>(
          MaterialPageRoute(builder: (_) => const ScanBarcodePage()));
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      try {
        final r = await Api.get(
            '/products/by-barcode/${Uri.encodeComponent(raw.trim())}');
        final id = r is Map && r['productId'] != null ? '${r['productId']}' : '';
        if (id.isEmpty) {
          _msg('ບໍ່ພົບສິນຄ້າ: $raw');
          continue;
        }
        final p = await Api.get('/products/$id');
        if (p is Map) {
          _add(Map<String, dynamic>.from(p));
          _msg('+1 ${p['name'] ?? id}');
        }
      } catch (e) {
        _msg('$e');
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('ອາໄຫຼ່ທີ່ຂໍ', style: TextStyle(fontWeight: FontWeight.w700)),
      if (lines.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່'))),
      for (final l in lines)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.image_outlined),
          title: Text(pick(l.product, ['name', 'productName', 'id'])),
          subtitle: Text(pick(l.product, ['brandName', 'typeName'])),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: l.qty > 1 ? () => setState(() => l.qty--) : null),
            Text('${l.qty}'),
            IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => l.qty++)),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => setState(() => lines.remove(l))),
          ]),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('ສະແກນ'),
                onPressed: _scan)),
        const SizedBox(width: 8),
        Expanded(
            child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('ເລືອກຈາກສິນຄ້າ'),
                onPressed: _pick)),
      ]),
    ]);
  }
}
