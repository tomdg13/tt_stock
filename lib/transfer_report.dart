import 'package:flutter/material.dart';
import 'api.dart';
import 'lao.dart';
import 'theme.dart';
import 'widgets.dart';

class TransferReportPage extends StatefulWidget {
  const TransferReportPage({super.key});
  @override
  State<TransferReportPage> createState() => _TransferReportPageState();
}

class _TransferReportPageState extends State<TransferReportPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  DateTimeRange? _range;
  String? _branch;

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get('/stock/transfers');
    final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
    return asList(raw);
  }

  DateTime? _date(Map<String, dynamic> t) {
    final s =
        pick(t, ['createdAt', 'created_at', 'date', 'sentAt', 'createdDate']);
    return s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> t) =>
      t['items'] is List ? asList(t['items']) : <Map<String, dynamic>>[];

  num _qty(Map<String, dynamic> t) {
    final its = _items(t);
    if (its.isEmpty) return num0(t['qty'] ?? t['quantity']);
    return its.fold<num>(0, (s, i) => s + num0(i['qty'] ?? i['quantity']));
  }

  String _from(Map<String, dynamic> t) =>
      pick(t, ['fromBranchName', 'fromBranchId']);
  String _to(Map<String, dynamic> t) => pick(t, ['toBranchName', 'toBranchId']);

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    return rows.where((t) {
      if (_branch != null && _from(t) != _branch && _to(t) != _branch) {
        return false;
      }
      if (_range != null) {
        final d = _date(t);
        if (d == null) return false;
        if (d.isBefore(_range!.start) || d.isAfter(_range!.end)) return false;
      }
      return true;
    }).toList();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ລາຍງານໂອນອາໄຫຼ່ລະຫວ່າງສາຂາ'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _future = _load())),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('ຜິດພາດ: ${snap.error}'));
          }
          final all = snap.data ?? [];
          final branches = <String>{
            for (final t in all) ...[_from(t), _to(t)]
          }.where((e) => e.isNotEmpty).toList()
            ..sort();
          final rows = _filter(all);
          final totalQty = rows.fold<num>(0, (s, t) => s + _qty(t));
          final transit = rows
              .where((t) => pick(t, ['status', 'state']) == 'in_transit')
              .length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? 'ທຸກວັນທີ'
                      : '${_fmtDate(_range!.start)} → ${_fmtDate(_range!.end)}'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: _range);
                    if (r != null) setState(() => _range = r);
                  },
                ),
              ),
              if (_range != null)
                IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _range = null)),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              key: ValueKey(_branch),
              initialValue: _branch,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ສາຂາ'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('ທຸກສາຂາ')),
                for (final b in branches)
                  DropdownMenuItem<String?>(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _branch = v),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _sum('ຈຳນວນໃບໂອນ', '${rows.length}'),
                      _sum('ຈຳນວນອາໄຫຼ່ລວມ', fmtNum(totalQty.toDouble())),
                      _sum('ລະຫວ່າງທາງ', '$transit'),
                    ]),
              ),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))),
            for (final t in rows) _row(t, p),
          ]);
        },
      ),
    );
  }

  Widget _sum(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _row(Map<String, dynamic> t, dynamic p) {
    final st = pick(t, ['status', 'state']);
    final info = transferStatus[st];
    final its = _items(t);
    final lines = its.isEmpty
        ? pick(t, ['productName'])
        : its
            .map((i) => '${pick(i, [
                      'productName',
                      'name',
                      'productId'
                    ])} × ${fmtNum(num0(i['qty'] ?? i['quantity']))}')
            .join('\n');
    final d = _date(t);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(pick(t, ['ref', 'docNo', 'id']),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Tag(info?[0] ?? st, info?[1] ?? kindOf(st)),
        ]),
        Text('${_from(t)} → ${_to(t)}${d == null ? '' : '  •  ${_fmtDate(d)}'}',
            style: TextStyle(color: p.mut, fontSize: 13)),
        if (lines.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(lines)),
      ]),
    );
  }
}
