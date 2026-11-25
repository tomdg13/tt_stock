import 'package:flutter/material.dart';
import 'api.dart';
import 'withdraw_bill.dart';
import 'withdraw_page.dart';

/// ລາຍການໃບເບີກ of one terminal (GET /withdrawals, filtered by barcode).
/// The ສ້າງໃບເບີກ button opens a new withdrawal for this terminal;
/// saving it opens its bill and the list reloads.
class _StepTile {
  final String key, label;
  final IconData icon;
  const _StepTile(this.key, this.label, this.icon);
}

const _kTiles = <_StepTile>[
  _StepTile('wait', 'ລໍຖ້າອະນຸມັດ', Icons.hourglass_top_outlined),
  _StepTile('s4', 'ຮັບເຄື່ອງ', Icons.inventory_2_outlined),
  _StepTile('s5', 'ຕິດຕັ້ງ', Icons.build_outlined),
  _StepTile('s6', 'ສົ່ງຄືນ', Icons.undo),
  _StepTile('s7', 'HQ ຮັບຄືນ', Icons.move_to_inbox_outlined),
  _StepTile('closed', 'ປິດເຄດ', Icons.task_alt),
];

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

  String _filter = '';

  static String _group(Map<String, dynamic> w) {
    final st = '${w['status'] ?? ''}';
    final sg = int.tryParse('${w['stage'] ?? ''}') ?? 0;
    if (st == 'closed') return 'closed';
    if (st == 'requested') return 'wait';
    if (sg >= 4 && sg <= 7) return 's$sg';
    return 'other';
  }

  bool _match(Map<String, dynamic> w) =>
      _filter.isEmpty || _group(w) == _filter;

  Widget _tile(_StepTile t, int n) {
    final cs = Theme.of(context).colorScheme;
    final on = _filter == t.key;
    final c = on ? cs.primary : cs.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _filter = on ? '' : t.key),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: on ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(8)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: Icon(t.icon, size: 28, color: c),
          ),
          const SizedBox(height: 4),
          Text(t.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c)),
        ]),
      ),
    );
  }

  Widget _tiles(List<Map<String, dynamic>> all) {
    final cnt = <String, int>{};
    for (final w in all) {
      final g = _group(w);
      cnt[g] = (cnt[g] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('ສະຖານະໃບເບີກ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          TextButton(
              onPressed:
                  _filter.isEmpty ? null : () => setState(() => _filter = ''),
              child: const Text('ເບິ່ງທັງໝົດ ›')),
        ]),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final t in _kTiles) _tile(t, cnt[t.key] ?? 0),
          ]),
        ),
      ]),
    );
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
    final base = '${_when(w['createdAt'])} · ${_stageText(w)} · $n ລາຍການ';
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

  static int _stageOf(Map<String, dynamic> w) =>
      int.tryParse('${w['stage'] ?? ''}') ?? 0;

  /// Short step text for the list subtitle.
  String _stageText(Map<String, dynamic> w) {
    final st = '${w['status'] ?? ''}';
    if (st == 'closed') return 'ປິດເຄດແລ້ວ';
    final sg = _stageOf(w);
    return sg >= 2 ? 'ຂັ້ນ $sg' : st;
  }

  /// Current step of the withdrawal (stage 2..7) or closed.
  Widget _docChip(Map<String, dynamic> w) {
    final st = '${w['status'] ?? ''}';
    final sg = _stageOf(w);
    final hasReject = '${w['rejectNote'] ?? ''}'.isNotEmpty;
    final String label;
    final Color color;
    if (st == 'closed') {
      label = 'ປິດເຄດ';
      color = Colors.green;
    } else if (st == 'requested' && sg == 3) {
      label = 'ລໍຖ້າອະນຸມັດ';
      color = Colors.orange;
    } else if (st == 'requested') {
      label = hasReject ? 'ບໍ່ອະນຸມັດ' : 'ອັບເອກະສານ';
      color = hasReject ? Colors.red : Colors.grey;
    } else if (sg == 4) {
      label = 'ຮັບເຄື່ອງ';
      color = Colors.blue;
    } else if (sg == 5) {
      label = 'ຕິດຕັ້ງ';
      color = Colors.blue;
    } else if (sg == 6) {
      label = 'ສົ່ງຄືນ';
      color = Colors.blue;
    } else if (sg == 7) {
      label = 'HQ ຮັບຄືນ';
      color = Colors.deepPurple;
    } else {
      label = 'ເປີດຢູ່';
      color = Colors.grey;
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
            final all = snap.data ?? [];
              final rows = all.where(_match).toList();
            if (all.isEmpty) {
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
              itemCount: rows.isEmpty ? 2 : rows.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == 0) return _tiles(all);
                  if (rows.isEmpty) {
                    return Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                            child: Text('ບໍ່ມີລາຍການໃນຂັ້ນນີ້',
                                style: TextStyle(color: mut))));
                  }
                  final w = rows[i - 1];
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
