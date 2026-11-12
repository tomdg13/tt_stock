import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';
import 'product_images.dart' show productImageUrl;

class TerminalPartsPage extends StatefulWidget {
  final String barcode;
  const TerminalPartsPage(this.barcode, {super.key});
  @override
  State<TerminalPartsPage> createState() => _TerminalPartsPageState();
}

class _TerminalPartsPageState extends State<TerminalPartsPage> {
  late Future<List<List<Map<String, dynamic>>>> _f = _load();
  final Map<String, String> _imgById = {};
  final Map<String, String> _imgByName = {};

  void _reload() => setState(() {
        _f = _load();
      });

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final enc = Uri.encodeComponent(widget.barcode);
    final t = await Api.get('/terminals/$enc');
    final parts = t is Map ? asList(t['parts']) : <Map<String, dynamic>>[];
    var logs = <Map<String, dynamic>>[];
    try {
      logs = asList(await Api.get('/install/log?barcode=$enc&limit=300'));
    } catch (_) {}
    final used = logs
        .where((l) => pick(l, ['action']).toUpperCase().startsWith('MA PART'))
        .toList();
    try {
      final pr = asList(await Api.get('/products?limit=500'));
      _imgById.clear();
      _imgByName.clear();
      for (final x in pr) {
        final u = pick(x, ['imageUrl']);
        if (u.isEmpty) continue;
        _imgById[pick(x, ['id'])] = u;
        _imgByName[pick(x, ['name']).trim()] = u;
      }
    } catch (_) {}
    return [parts, used];
  }

  String _d(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final l = d.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)} ${t(l.hour)}:${t(l.minute)}';
  }

  String _qty(String action) {
    final m = RegExp(r'X(\d+)$').firstMatch(action.toUpperCase());
    return m == null ? '' : ' × ${m.group(1)}';
  }

  Widget _thumb(String id, String name) {
    final p = pal(context);
    final ph = Container(
      width: 44,
      height: 44,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: p.mut),
    );
    final u = productImageUrl(_imgById[id] ?? _imgByName[name.trim()] ?? '');
    if (u.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(u,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph),
    );
  }

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _empty(BuildContext c) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: pal(c).mut)),
      );

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: Text('ຂໍ້ມູນອາໄຫຼ່ · ${widget.barcode}')),
      body: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return ErrorView(s.error ?? '', _reload);
          final data = s.data ?? <List<Map<String, dynamic>>>[[], []];
          final parts = data[0];
          final used = data[1];
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _head('ອາໄຫຼ່ທີ່ຕິດຕັ້ງຢູ່ (Serial)'),
              if (parts.isEmpty) _empty(c),
              for (final e in parts)
                cardBox(
                  c,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _thumb(
                        pick(e, ['productId']), pick(e, ['productName'])),
                    title: Text(pick(e, ['productName', 'productId']),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        [
                          pick(e, ['serialNo']),
                          pick(e, ['installedBy'])
                        ].where((x) => x.isNotEmpty).join(' · '),
                        style: TextStyle(color: p.mut, fontSize: 13)),
                    trailing: Text(_d(pick(e, ['installedAt'])),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.mut, fontSize: 12)),
                  ),
                ),
              _head('ອາໄຫຼ່ທີ່ເຄີຍໃຊ້ສ້ອມ'),
              if (used.isEmpty) _empty(c),
              for (final e in used)
                cardBox(
                  c,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _thumb('', pick(e, ['productName'])),
                    title: Text(
                        '${pick(e, ['productName']).isEmpty ? pick(e, [
                                'action'
                              ]) : pick(e, [
                                'productName'
                              ])}${_qty(pick(e, ['action']))}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(pick(e, ['userName']),
                        style: TextStyle(color: p.mut, fontSize: 13)),
                    trailing: Text(_d(pick(e, ['logDate'])),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.mut, fontSize: 12)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
