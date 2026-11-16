import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart' show toastMsg;
import 'request_status_bar.dart';
import 'stock_request.dart' show reqStatusChip, reqStatusItems, StockRequestsPage;
import 'theme.dart';
import 'widgets.dart';

/// Status check for inter-branch part requests: status icons with counts
/// (tap to filter) and one list with both incoming and my own requests.
/// The + button opens a repair case (ເຄດສ້ອມ) for a terminal barcode.
class RequestStatusPage extends StatefulWidget {
  final Map<String, dynamic>? terminal;
  const RequestStatusPage({super.key, this.terminal});
  @override
  State<RequestStatusPage> createState() => _RequestStatusPageState();
}

class _RequestStatusPageState extends State<RequestStatusPage> {
  late Future<dynamic> _f = Api.get('/stock/requests');
  String? _filter;

  dynamic get _mine => Api.user?['branchId'];

  void _reload() => setState(() {
        _f = Api.get('/stock/requests');
      });

  Future<void> _newCase() async {
    final tm = widget.terminal;
    if (tm != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StockRequestsPage(terminal: tm, onChanged: _reload)));
      if (mounted) _reload();
      return;
    }
    var typed = '';
    final code = await showDialog<String>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('ເປີດເຄດສ້ອມ'),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'ບາໂຄດຕູ້ (TID)', border: OutlineInputBorder()),
          onChanged: (v) => typed = v,
          onSubmitted: (v) => Navigator.pop(dc, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(dc, typed.trim()),
              child: const Text('ຕໍ່ໄປ')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final bc = code.toUpperCase();
    try {
      final t = await Api.get('/terminals/${Uri.encodeComponent(bc)}');
      if (mounted == false) return;
      if ((t is Map) == false) {
        toastMsg(context, 'ຫາຕູ້ນີ້ບໍ່ເຫັນ');
        return;
      }
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StockRequestsPage(
                  terminal: Map<String, dynamic>.from(t as Map),
                  onChanged: _reload)));
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        toastMsg(context, 'ຫາຕູ້ບໍ່ເຫັນ: ${'$e'.replaceFirst('Exception: ', '')}');
      }
    }
  }

  List<Map<String, dynamic>> _rows(dynamic d) {
    final all = asList(d);
    final m = _mine;
    if (m == null) return all;
    return all
        .where((r) =>
            '${r['supBranchId']}' == '$m' || '${r['reqBranchId']}' == '$m')
        .toList();
  }

  String _dir(Map<String, dynamic> r) {
    final m = _mine;
    if (m == null) return '';
    return '${r['supBranchId']}' == '$m' ? 'ຄຳຂໍທີ່ເຂົ້າມາ' : 'ຄຳຂໍຂອງຂ້ອຍ';
  }

  Widget _card(Map<String, dynamic> r) {
    final p = pal(context);
    final items =
        r['items'] is List ? asList(r['items']) : <Map<String, dynamic>>[];
    final lines = items
        .map((i) =>
            '${pick(i, ['productName', 'productId'])} × ${pick(i, ['qty'])}')
        .join('\n');
    final note = pick(r, ['note']);
    final created = pick(r, ['createdAt']);
    final dir = _dir(r);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: p.bd),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(pick(r, ['requestNo', 'id']),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          reqStatusChip(pick(r, ['status'])),
        ]),
        const SizedBox(height: 2),
        Text('${pick(r, ['reqName'])} ຂໍຈາກ ${pick(r, ['supName'])}',
            style: TextStyle(color: p.mut, fontSize: 13)),
        if (dir.isNotEmpty || created.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                [dir, created.isEmpty ? '' : created.split('T').first]
                    .where((x) => x.isNotEmpty)
                    .join(' · '),
                style: TextStyle(color: p.mut, fontSize: 12)),
          ),
        if (lines.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(lines)),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: TextStyle(color: p.mut, fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ສະຖານະຄຳຂໍ')),
      floatingActionButton: Api.can('ATM_MANAGE')
          ? FloatingActionButton.extended(
              onPressed: _newCase,
              icon: const Icon(Icons.add),
              label: const Text('ເປີດເຄດສ້ອມ'),
            )
          : null,
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) return ErrorView(s.error ?? '', _reload);
          if (s.connectionState == ConnectionState.done) {
            final all = _rows(s.data);
            final flt = _filter;
            final rows = flt == null
                ? all
                : all.where((r) => pick(r, ['status']) == flt).toList();
            final counts = <String, int>{};
            for (final r in all) {
              final st = pick(r, ['status']);
              counts[st] = (counts[st] ?? 0) + 1;
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    RequestStatusBar(
                      items: reqStatusItems(),
                      counts: counts,
                      selected: flt,
                      onSelect: (k) =>
                          setState(() => _filter = k == _filter ? null : k),
                    ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('ຍັງບໍ່ມີລາຍການ',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.mut)),
                      ),
                    for (final r in rows) _card(r),
                  ]),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
