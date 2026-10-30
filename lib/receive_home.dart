import 'package:flutter/material.dart';
import 'api.dart';
import 'stock_drill.dart';
import 'purchase_orders.dart';
import 'screens.dart' show BarcodeScanPage;
import 'lao.dart';
import 'theme.dart';
import 'widgets.dart';
import 'invoice_import.dart';

// ------------------------------------------------------------- shared bits
import 'pages.dart';

/// ຮັບເຂົ້າ tab: recent receipts list first -> "ເພີ່ມ" opens the existing form.
class ReceiveHome extends StatefulWidget {
  const ReceiveHome({super.key});
  @override
  State<ReceiveHome> createState() => _ReceiveHomeState();
}

class _ReceiveHomeState extends State<ReceiveHome> {
  bool _adding = false;
  late Future<dynamic> _recent = Api.get('/stock/movements');

  void _reload() => setState(() {
        _recent = Api.get('/stock/movements');
      });

  void _backToList() {
    setState(() => _adding = false);
    _reload();
  }

  static const _labels = {
    'type': 'ປະເພດ',
    'movementType': 'ປະເພດ',
    'productName': 'ສິນຄ້າ',
    'name': 'ສິນຄ້າ',
    'branchName': 'ສາຂາ',
    'qty': 'ຈຳນວນ',
    'quantity': 'ຈຳນວນ',
    'grnNo': 'ເລກ GRN',
    'refNo': 'ເລກອ້າງອີງ',
    'poNo': 'PO',
    'note': 'ໝາຍເຫດ',
    'createdAt': 'ວັນທີ',
    'receiptDate': 'ວັນທີຮັບເຂົ້າ',
    'createdBy': 'ຜູ້ບັນທຶກ',
    'userName': 'ຜູ້ບັນທຶກ',
  };

  void _openDetail(Map<String, dynamic> m) {
    final p = pal(context);
    final scalars = m.entries
        .where((e) => e.value != null && e.value is! Map && e.value is! List)
        .toList();
    final lines = [
      for (final k in ['lines', 'items'])
        if (m[k] is List) ...(m[k] as List).whereType<Map>()
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('ລາຍລະອຽດການຮັບເຂົ້າ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final e in scalars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 120,
                          child: Text(_labels[e.key] ?? e.key,
                              style: TextStyle(color: p.mut))),
                      Expanded(child: Text('${e.value}')),
                    ]),
              ),
            if (lines.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('ລາຍການສິນຄ້າ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final l in lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(pick(Map<String, dynamic>.from(l),
                      ['productName', 'name', 'productId'])),
                  trailing: Text(
                      'x${pick(Map<String, dynamic>.from(l), ['qty', 'quantity'])}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);

    // ---- add form (existing page) ----
    if (_adding) {
      return Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back),
            label: const Text('ກັບໄປລາຍການຮັບເຂົ້າ'),
          ),
        ),
        const Expanded(child: StockFormPage(issue: false)),
      ]);
    }

    // ---- list first ----
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _adding = true),
        icon: const Icon(Icons.add),
        label: const Text('ເພີ່ມ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            AppCard(
              title: 'ຮັບເຂົ້າລ່າສຸດ',
              child: futureBlock(_recent, _reload, (d) {
                final all = asList(d);
                var rows = all.where((m) {
                  final t = pick(m, ['type', 'movementType']);
                  return t.contains('purchase') || t.contains('receive');
                }).toList();
                if (rows.isEmpty) rows = all;
                if (rows.isEmpty) {
                  return Text('ຍັງບໍ່ມີລາຍການ',
                      style: TextStyle(color: p.mut));
                }
                return Column(children: [
                  for (final m in rows.take(30))
                    InkWell(
                      onTap: () => _openDetail(m),
                      child: moveRow(context, m),
                    ),
                ]);
              }),
            ),
          ],
        ),
      ),
    );
  }
}
