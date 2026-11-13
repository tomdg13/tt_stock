import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

// Product detail -> "POs that contain this product" and "ATM usage" pages.
// Wired in specs.dart as RowActions on the products spec.
//
// Backend endpoints expected:
//   GET /products/:id/purchase-orders
//     -> [{poId, poNo, title, vendor, status, createdAt, qty, unitPrice, lineTotal}]
//   GET /products/:id/installs
//     -> [{atmId, terminalId, serialNo, action, userName, logDate}]

String _pid(Map<String, dynamic> r) =>
    pick(r, ['id', 'productId', 'product_id']);
String _pname(Map<String, dynamic> r) => pick(r, ['name', 'productName']);

Future<void> openProductPOs(BuildContext c, Map<String, dynamic> r) =>
    Navigator.push<void>(
      c,
      MaterialPageRoute(
        builder: (_) => _UsagePage(
          title: 'ໃບສັ່ງຊື້ (PO)',
          subtitle: _pname(r),
          path: '/products/${Uri.encodeComponent(_pid(r))}/purchase-orders',
          rowBuilder: _poRow,
        ),
      ),
    );

Future<void> openProductInstalls(BuildContext c, Map<String, dynamic> r) =>
    Navigator.push<void>(
      c,
      MaterialPageRoute(
        builder: (_) => _UsagePage(
          title: 'ໃຊ້ໃນ ATM',
          subtitle: _pname(r),
          path: '/products/${Uri.encodeComponent(_pid(r))}/installs',
          rowBuilder: _installRow,
        ),
      ),
    );

String _date(String s) {
  if (s.isEmpty) return '';
  final t = s.replaceFirst('T', ' ');
  return t.length > 16 ? t.substring(0, 16) : t;
}

class _RowView {
  final String title;
  final String sub;
  final String trail;
  const _RowView(this.title, this.sub, this.trail);
}

_RowView _poRow(Map<String, dynamic> r) {
  final no = pick(r, ['poNo', 'po_no']);
  final title = pick(r, ['title']);
  final vendor = pick(r, ['vendor']);
  final status = pick(r, ['status']);
  final date = _date(pick(r, ['createdAt', 'created_at']));
  final qty = pick(r, ['qty']);
  final price = pick(r, ['unitPrice', 'unit_price']);
  return _RowView(
    [no, title].where((e) => e.isNotEmpty).join('  '),
    [vendor, status, date].where((e) => e.isNotEmpty).join(' · '),
    qty.isEmpty ? '' : '$qty × $price',
  );
}

_RowView _installRow(Map<String, dynamic> r) {
  final atm = pick(r, ['atmId', 'atm_id']);
  final term = pick(r, ['terminalId', 'terminal_id']);
  final serial = pick(r, ['serialNo', 'serial_no']);
  final action = pick(r, ['action']);
  final user = pick(r, ['userName', 'user_name']);
  return _RowView(
    [atm, term].where((e) => e.isNotEmpty).join('  '),
    [action, if (serial.isNotEmpty) 'S/N $serial', user]
        .where((e) => e.isNotEmpty)
        .join(' · '),
    _date(pick(r, ['logDate', 'log_date'])),
  );
}

class _UsagePage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String path;
  final _RowView Function(Map<String, dynamic>) rowBuilder;
  const _UsagePage({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.rowBuilder,
  });

  @override
  State<_UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<_UsagePage> {
  late Future<dynamic> _f = Api.get(widget.path);

  void _reload() => setState(() {
        _f = Api.get(widget.path);
      });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            if (widget.subtitle.isNotEmpty)
              Text(widget.subtitle,
                  style: TextStyle(fontSize: 12, color: p.mut)),
          ],
        ),
      ),
      body: FutureBuilder(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return ErrorView(s.error!, _reload);
          final rows = asList(s.data);
          if (rows.isEmpty) {
            return Center(
              child: Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final v = widget.rowBuilder(rows[i]);
                return AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (v.sub.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(v.sub,
                                    style: TextStyle(
                                        color: p.mut, fontSize: 12.5)),
                              ),
                          ],
                        ),
                      ),
                      if (v.trail.isNotEmpty)
                        Text(v.trail, style: TextStyle(color: p.mut)),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
