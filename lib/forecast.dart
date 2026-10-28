// Spare-part purchase forecast: usage (last 7 days, or 4-week average) + buffer %, minus current stock.
// Server: GET /stock/forecast?weeks=1|4&pct=15&branchId=
import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
import 'pages.dart' show loadBranches;
import 'theme.dart';
import 'widgets.dart';

class ForecastPage extends StatefulWidget {
  const ForecastPage({super.key});
  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
  final _pct = TextEditingController(text: '15');
  int _weeks = 1;
  dynamic _branchId;
  List<Map<String, dynamic>> _branches = [];
  Future<dynamic>? _f;

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _run();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  void _run() {
    final pct = int.tryParse(_pct.text.trim()) ?? 15;
    final q = [
      'weeks=$_weeks',
      'pct=$pct',
      if (_branchId != null) 'branchId=$_branchId'
    ].join('&');
    setState(() => _f = Api.get('/stock/forecast?$q'));
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ຄາດການຊື້ອາໄຫຼ່')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<dynamic>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ສາຂາ'),
              items: [
                const DropdownMenuItem<dynamic>(
                    value: null, child: Text('ທຸກສາຂາ')),
                for (final b in _branches)
                  DropdownMenuItem<dynamic>(
                      value: b['id'], child: Text(pick(b, ['name']))),
              ],
              onChanged: (v) {
                _branchId = v;
                _run();
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('7 ວັນຜ່ານມາ')),
                ButtonSegment(value: 4, label: Text('ສະເລ່ຍ 4 ອາທິດ')),
              ],
              selected: {_weeks},
              onSelectionChanged: (s) {
                _weeks = s.first;
                _run();
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pct,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ເພີ່ມ % (ສຳຮອງ)', suffixText: '%'),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ຄິດໃໝ່')),
            ]),
          ]),
        ),
        FutureBuilder<dynamic>(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (s.hasError) return ErrorView(s.error!, _run);
            final d = s.data;
            final items =
                d is Map ? asList(d['items']) : <Map<String, dynamic>>[];
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Text('ຍັງບໍ່ມີຂໍ້ມູນການໃຊ້ອາໄຫຼ່ ໃນຊ່ວງນີ້',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.mut)),
              );
            }
            final toBuy = items
                .where((m) => (num.tryParse(pick(m, ['suggest'])) ?? 0) > 0)
                .length;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('ຕ້ອງຊື້ ${toBuy} ລາຍການ ຈາກ ${items.length}',
                        style: TextStyle(color: p.mut)),
                  ),
                  for (final m in items)
                    Builder(builder: (c) {
                      final suggest = num.tryParse(pick(m, ['suggest'])) ?? 0;
                      final unit = pick(m, ['unit']);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pick(m, ['productName']),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ໃຊ້/ອາທິດ ${pick(m, [
                                            'weeklyUsed'
                                          ])} · ສະຕັອກ ${pick(m, [
                                            'stock'
                                          ])} · ຄາດ ${pick(m, [
                                            'forecast'
                                          ])} $unit',
                                      style:
                                          TextStyle(color: p.mut, fontSize: 13),
                                    ),
                                  ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    (suggest > 0 ? Colors.orange : Colors.green)
                                        .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                suggest > 0 ? 'ຊື້ $suggest' : 'ພໍ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: suggest > 0
                                        ? Colors.orange.shade800
                                        : Colors.green.shade700),
                              ),
                            ),
                          ]),
                        ),
                      );
                    }),
                ]);
          },
        ),
      ]),
    );
  }
}
