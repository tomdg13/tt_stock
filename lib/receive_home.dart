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
import 'po_info.dart';

/// ຮັບເຂົ້າ tab: recent receipts grouped by PO -> tap a PO to see its items.
class ReceiveHome extends StatefulWidget {
  const ReceiveHome({super.key});
  @override
  State<ReceiveHome> createState() => _ReceiveHomeState();
}

class _ReceiveHomeState extends State<ReceiveHome> {
  bool _adding = false;
  late Future<dynamic> _recent = Api.get('/stock/movements');

  // key names tried in order (adjust if your API uses other names)
  static const _poKeys = ['poNo', 'poNumber', 'po', 'poCode', 'refNo'];
  static const _grnKeys = ['grnNo', 'grn', 'docNo', 'refNo'];
  static const _qtyKeys = [
    'qty',
    'quantity',
    'qtyChange',
    'delta',
    'change',
    'qtyIn',
    'received',
    'amount'
  ];
  static const _dateKeys = ['receiptDate', 'createdAt', 'date'];

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

  String _day(Map<String, dynamic> m) {
    final d = pick(m, _dateKeys);
    return d.length >= 10 ? d.substring(0, 10) : d;
  }

  /// Group movements by PO (falls back to GRN when a row has no PO).
  List<_PoGroup> _group(List<Map<String, dynamic>> rows) {
    final map = <String, _PoGroup>{};
    for (final m in rows) {
      final po = pick(m, _poKeys);
      final grn = pick(m, _grnKeys);
      final key =
          po.isNotEmpty ? 'PO:$po' : (grn.isNotEmpty ? 'GRN:$grn' : 'NONE');
      final g = map.putIfAbsent(
          key,
          () => _PoGroup(
                label: po.isNotEmpty
                    ? 'PO $po'
                    : (grn.isNotEmpty ? 'GRN $grn' : 'ບໍ່ມີ PO'),
                po: po,
                grn: grn,
                branch: pick(m, ['branchName', 'branchId']),
                date: _day(m),
              ));
      g.items.add(m);
      g.total += num0(pick(m, _qtyKeys));
    }
    return map.values.toList();
  }

  // ---- item detail (one movement line) ----
  void _openDetail(Map<String, dynamic> m) {
    final p = pal(context);
    final scalars = m.entries
        .where((e) => e.value != null && e.value is! Map && e.value is! List)
        .toList();
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
            Text(pick(m, ['productName', 'name', 'productId']),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
          ],
        ),
      ),
    );
  }

  // ---- PO detail: nav-bar style tabs (ລາຍການ / ຂໍ້ມູນ PO) ----
  void _openPo(_PoGroup g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        var tab = 0;
        return StatefulBuilder(builder: (ctx, setS) {
          final p = pal(ctx);
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.label,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            [g.branch, g.grn, g.date]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            style: TextStyle(color: p.mut, fontSize: 13)),
                      ]),
                ),
              ),
              Expanded(
                child: tab == 0
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          Text(
                              '${g.items.length} ລາຍການ · ລວມ +${fmtNum(g.total)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const Divider(height: 24),
                          for (final m in g.items)
                            InkWell(
                              onTap: () => _openDetail(m),
                              child: moveRow(context, m),
                            ),
                        ],
                      )
                    : PoInfoView(poNo: g.po),
              ),
              NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setS(() => tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.list_alt_outlined), label: 'ລາຍການ'),
                  NavigationDestination(
                      icon: Icon(Icons.info_outline), label: 'ຂໍ້ມູນ PO'),
                ],
              ),
            ]),
          );
        });
      },
    );
  }

  Widget _poRow(_PoGroup g) {
    final p = pal(context);
    return InkWell(
      onTap: () => _openPo(g),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                  [g.branch, g.grn, g.date]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
              Text('${g.items.length} ລາຍການ',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
            ]),
          ),
          Text('+${fmtNum(g.total)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);

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
              title: 'ຮັບເຂົ້າລ່າສຸດ (ຕາມ PO)',
              child: futureBlock(_recent, _reload, (d) {
                final all = asList(d);
                var rows = all.where((m) {
                  final t = pick(m, ['type', 'movementType']);
                  return t.contains('purchase') || t.contains('receive');
                }).toList();
                if (rows.isEmpty) rows = all;
                if (rows.isEmpty) {
                  return Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut));
                }
                final groups = _group(rows);
                return Column(children: [
                  for (var i = 0; i < groups.length && i < 30; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _poRow(groups[i]),
                  ],
                ]);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoGroup {
  final String label, po, grn, branch, date;
  final List<Map<String, dynamic>> items = [];
  double total = 0;
  _PoGroup(
      {required this.label,
      required this.po,
      required this.grn,
      required this.branch,
      required this.date});
}
