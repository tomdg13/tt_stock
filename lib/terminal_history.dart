// History of an ATM (all its terminals) or of one terminal:
// status changes (In Use / MA / Ready ...) + spare parts used / installed / removed.
// Uses existing routes: GET /atms/:id, GET /terminals/:barcode (activities) and GET /install/log.
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class _Ev {
  final DateTime? at;
  final String kind; // status | part
  final String title, sub;
  _Ev(this.at, this.kind, this.title, this.sub);
}

class HistoryPage extends StatefulWidget {
  final String? atmId, barcode;
  const HistoryPage({super.key, this.atmId, this.barcode});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<_Ev>> _f = _load();
  String _filter = 'all';

  bool get _byAtm => widget.atmId != null;
  String get _id => (_byAtm ? widget.atmId : widget.barcode) ?? '';
  void _reload() => setState(() {
        _f = _load();
      });

  String _partTitle(String action, String product) {
    final a = action.toUpperCase();
    final q = RegExp(r'X(\d+)$').firstMatch(a);
    final name = product.isEmpty ? '' : ': $product';
    if (a.startsWith('MA PART')) return 'ໃຊ້ອາໄຫຼ່$name${q == null ? '' : ' × ${q.group(1)}'}';
    if (a.startsWith('INSTALL')) return 'ຕິດຕັ້ງອາໄຫຼ່$name';
    if (a.startsWith('REMOVE')) return 'ເອົາອາໄຫຼ່ອອກ$name';
    return product.isEmpty ? action : '$action$name';
  }

  Future<List<_Ev>> _load() async {
    final enc = Uri.encodeComponent(_id);
    final results = await Future.wait<dynamic>([
      Api.get(_byAtm ? '/atms/$enc' : '/terminals/$enc'),
      Api.get('/install/log?${_byAtm ? 'atmId' : 'barcode'}=$enc&limit=300').catchError((_) => <dynamic>[]),
    ]);
    final base = results[0];
    final acts = base is Map ? asList(base['activities']) : <Map<String, dynamic>>[];
    final logs = asList(results[1]);
    final ev = <_Ev>[];
    for (final a in acts) {
      final st = pick(a, ['status']);
      final bc = pick(a, ['tidBarcode', 'barcode']);
      final atm = pick(a, ['atmId']);
      final title = _byAtm ? '$st  ·  $bc' : (atm.isEmpty ? st : '$st  ·  ATM $atm');
      final remark = pick(a, ['remark', 'equipmentList']).trim();
      ev.add(_Ev(DateTime.tryParse(pick(a, ['activityDate'])), 'status', title, remark));
    }
    for (final l in logs) {
      final action = pick(l, ['action']);
      final up = action.toUpperCase();
      if (!(up.startsWith('MA PART') || up.startsWith('INSTALL') || up.startsWith('REMOVE'))) continue;
      final sub = [if (_byAtm) pick(l, ['barcode']), pick(l, ['serialNo']), pick(l, ['userName'])]
          .where((e) => e.isNotEmpty)
          .join(' · ');
      ev.add(_Ev(DateTime.tryParse(pick(l, ['logDate'])), 'part', _partTitle(action, pick(l, ['productName'])), sub));
    }
    final zero = DateTime.fromMillisecondsSinceEpoch(0);
    ev.sort((a, b) => (b.at ?? zero).compareTo(a.at ?? zero));
    return ev;
  }

  String _fmt(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)}\n${t(l.hour)}:${t(l.minute)}';
  }

  Widget _chip(String k, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == k,
          onSelected: (_) => setState(() => _filter = k),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: Text('ປະຫວັດ · $_id')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            _chip('all', 'ທັງໝົດ'),
            _chip('status', 'ການປ່ຽນ Terminal'),
            _chip('part', 'ອາໄຫຼ່'),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<_Ev>>(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return ErrorView(s.error!, _reload);
              final items = (s.data ?? []).where((e) => _filter == 'all' || e.kind == _filter).toList();
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Center(child: Text('ຍັງບໍ່ມີປະຫວັດ', style: TextStyle(color: p.mut))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final e = items[i];
                          return cardBox(
                            context,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(e.kind == 'part' ? Icons.build_outlined : Icons.swap_horiz),
                              title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: e.sub.isEmpty
                                  ? null
                                  : Text(e.sub, maxLines: 4, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: p.mut, fontSize: 13)),
                              trailing: Text(_fmt(e.at),
                                  textAlign: TextAlign.right, style: TextStyle(color: p.mut, fontSize: 12)),
                            ),
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
