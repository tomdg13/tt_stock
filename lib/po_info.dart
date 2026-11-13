import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

const _poLabels = {
  'poNo': 'ເລກ PO',
  'vendorName': 'ຜູ້ສະໜອງ',
  'vendor': 'ຜູ້ສະໜອງ',
  'supplier': 'ຜູ້ສະໜອງ',
  'poDate': 'ວັນທີ PO',
  'date': 'ວັນທີ',
  'status': 'ສະຖານະ',
  'note': 'ໝາຍເຫດ',
  'amount': 'ມູນຄ່າ',
  'total': 'ມູນຄ່າລວມ',
  'currency': 'ສະກຸນເງິນ',
  'createdAt': 'ສ້າງເມື່ອ',
  'createdBy': 'ຜູ້ສ້າງ',
};

/// PO information (header fields + attached documents), loaded by PO number.
/// Embed it inside a sheet/tab.
class PoInfoView extends StatefulWidget {
  final String poNo;
  const PoInfoView({super.key, required this.poNo});
  @override
  State<PoInfoView> createState() => _PoInfoViewState();
}

class _PoInfoViewState extends State<PoInfoView> {
  late final Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    final poNo = widget.poNo;
    if (poNo.isEmpty) throw 'ບໍ່ມີເລກ PO';
    final list = asList(
        await Api.get('/purchase-orders?q=${Uri.encodeQueryComponent(poNo)}'));
    final head = list.firstWhere((m) => pick(m, ['poNo']) == poNo,
        orElse: () => <String, dynamic>{});
    if (head.isEmpty) throw 'ບໍ່ພົບ PO $poNo';
    final id = pick(head, ['id', 'poId', '_id']);
    if (id.isEmpty) return head;
    final d = await Api.get('/purchase-orders/${Uri.encodeComponent(id)}');
    Map<String, dynamic> m = d is Map ? Map<String, dynamic>.from(d) : head;
    if (m['data'] is Map) m = Map<String, dynamic>.from(m['data'] as Map);
    return {...head, ...m};
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        final m = snap.data!;
        final scalars = m.entries
            .where((e) =>
                e.value != null &&
                e.value is! Map &&
                e.value is! List &&
                '${e.value}'.isNotEmpty &&
                !e.key.toLowerCase().endsWith('id'))
            .toList();
        final docs = [
          for (final k in ['documents', 'docs', 'files'])
            if (m[k] is List) ...(m[k] as List).whereType<Map>()
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            for (final e in scalars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 120,
                          child: Text(_poLabels[e.key] ?? e.key,
                              style: TextStyle(color: p.mut))),
                      Expanded(child: Text('${e.value}')),
                    ]),
              ),
            if (docs.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('ເອກະສານແນບ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final d in docs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(pick(Map<String, dynamic>.from(d),
                      ['name', 'fileName', 'originalName', 'filename'])),
                ),
            ],
          ],
        );
      },
    );
  }
}
