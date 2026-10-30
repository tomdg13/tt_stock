import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
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

/// Loads the PO by its number and shows its information in a bottom sheet.
Future<void> showPoInfo(BuildContext context, String poNo) {
  Future<Map<String, dynamic>> load() async {
    final list =
        asList(await Api.get('/purchase-orders?q=${Uri.encodeQueryComponent(poNo)}'));
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

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      final p = pal(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (_, sc) => FutureBuilder<Map<String, dynamic>>(
          future: load(),
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
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text('ຂໍ້ມູນ PO $poNo',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
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
        ),
      );
    },
  );
}
