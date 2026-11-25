import 'package:flutter/material.dart';
import 'api.dart';
import 'withdraw_bill.dart';
import 'withdraw_docs.dart' show wdDocStatusColor;
import 'withdraw_page.dart';

/// ລາຍການໃບເບີກ of one terminal (GET /withdrawals, filtered by barcode).
/// The ສ້າງໃບເບີກ button opens a new withdrawal for this terminal;
/// saving it opens its bill and the list reloads.
class WithdrawBillListPage extends StatefulWidget {
  final String barcode, atmId;
  const WithdrawBillListPage({super.key, this.barcode = '', this.atmId = ''});
  @override
  State<WithdrawBillListPage> createState() => _WithdrawBillListPageState();
}

class _WithdrawBillListPageState extends State<WithdrawBillListPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get('/withdrawals');
    final out = <Map<String, dynamic>>[];
    if (d is List) {
      for (final w in d) {
        if (w is! Map) continue;
        if (widget.barcode.isNotEmpty &&
            '${w['barcode'] ?? ''}' != widget.barcode) {
          continue;
        }
        out.add(Map<String, dynamic>.from(w));
      }
    }
    return out;
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _create() async {
    final r = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                WithdrawPage(barcode: widget.barcode, atmId: widget.atmId)));
    if (r == true && mounted) _reload();
  }

  /// Second line (terminal / ATM) only in the all-bills list.
  String _sub(Map<String, dynamic> w, int n) {
    final base = '${_when(w['createdAt'])} · ${w['status'] ?? ''} · $n ລາຍການ';
    final bc = '${w['barcode'] ?? ''}';
    if (widget.barcode.isNotEmpty || bc.isEmpty) return base;
    return '$base\n$bc · ATM ${w['atmId'] ?? ''}';
  }

  static String _when(dynamic v) {
    final s = v == null ? '' : '$v';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final l = d.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)} ${t(l.hour)}:${t(l.minute)}';
  }

  /// Waiting approval, or the status of the uploaded documents.
  Widget _docChip(Map<String, dynamic> w) {
    final st = '${w['status'] ?? ''}';
    final ds = '${w['docStatus'] ?? ''}';
    final String label;
    final Color color;
    if (st == 'requested') {
      label = 'ລໍຖ້າອະນຸມັດ';
      color = Colors.orange;
    } else if (ds == 'submitted') {
      label = 'ລໍຖ້າກວດ';
      color = wdDocStatusColor(ds);
    } else if (ds == 'checked') {
      label = 'ຜ່ານ';
      color = wdDocStatusColor(ds);
    } else if (ds == 'rejected') {
      label = 'ບໍ່ຜ່ານ';
      color = wdDocStatusColor(ds);
    } else {
      label = 'ຍັງບໍ່ອັບ';
      color = wdDocStatusColor('');
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.barcode.isEmpty
              ? 'ລາຍການໃບເບີກ'
              : 'ໃບເບີກ · ${widget.barcode}')),
      floatingActionButton: widget.barcode.isEmpty
          ? null
          : FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('ສ້າງໃບເບີກ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('${snap.error}'),
                    TextButton(
                        onPressed: _reload, child: const Text('ລອງໃໝ່')),
                  ]);
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: [
                    Center(
                        child: Text('ຍັງບໍ່ມີໃບເບີກ',
                            style: TextStyle(color: mut))),
                  ]);
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final w = rows[i];
                final n = w['items'] is List ? (w['items'] as List).length : 0;
                return ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                      '${w['withdrawNo'] ?? w['id']} · ${w['branchName'] ?? ''}'),
                  isThreeLine: widget.barcode.isEmpty,
                  subtitle: Text(_sub(w, n)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _docChip(w),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => WithdrawBillPage(w)));
                    if (mounted) _reload();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
