// Purchase plan: product image, usage, predicted need (week / month / year) and amount to buy.
// Server: GET /stock/purchase-plan?weeks=12&pct=15&branchId=
import 'package:flutter/material.dart';
import 'api.dart';
import 'product_images.dart' show productImageUrl;
import 'theme.dart';
import 'widgets.dart';

class PurchasePlanPage extends StatefulWidget {
  const PurchasePlanPage({super.key});
  @override
  State<PurchasePlanPage> createState() => _PurchasePlanPageState();
}

class _PurchasePlanPageState extends State<PurchasePlanPage> {
  final _pct = TextEditingController(text: '15');
  int _weeks = 12;
  String _h = 'Month';
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
    setState(() {
      _f = Api.get('/stock/purchase-plan?$q');
    });
  }

  Widget _thumb(String raw) {
    final url = productImageUrl(raw);
    final holder = Container(
        width: 64,
        height: 64,
        color: Colors.black12,
        child: const Icon(Icons.inventory_2_outlined));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? holder
          : SizedBox(
              width: 64,
              height: 64,
              child: Image.network(url,
                  fit: BoxFit.cover,
                  headers: Api.token == null
                      ? null
                      : {'Authorization': 'Bearer ${Api.token}'},
                  errorBuilder: (_, __, ___) => holder)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final buyKey = 'buy$_h';
    return Scaffold(
      appBar: AppBar(title: const Text('ແຜນຈັດຊື້ອາໄຫຼ່')),
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
            DropdownButtonFormField<int>(
              initialValue: _weeks,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'ປະຫວັດການໃຊ້ (ອາທິດ)'),
              items: const [
                DropdownMenuItem(value: 4, child: Text('4 ອາທິດ')),
                DropdownMenuItem(value: 12, child: Text('12 ອາທິດ')),
                DropdownMenuItem(value: 26, child: Text('26 ອາທິດ')),
                DropdownMenuItem(value: 52, child: Text('52 ອາທິດ')),
              ],
              onChanged: (v) {
                _weeks = v ?? 12;
                _run();
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Week', label: Text('ອາທິດໜ້າ')),
                ButtonSegment(value: 'Month', label: Text('ເດືອນໜ້າ')),
                ButtonSegment(value: 'Year', label: Text('ປີໜ້າ')),
              ],
              selected: {_h},
              onSelectionChanged: (s) => setState(() => _h = s.first),
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
                  child: Center(
                      child: Text('ບໍ່ມີຂໍ້ມູນ',
                          style: TextStyle(color: p.mut))));
            }
            final toBuy = items
                .where((m) => (num.tryParse(pick(m, [buyKey])) ?? 0) > 0)
                .length;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('ຕ້ອງຊື້ $toBuy ລາຍການ ຈາກ ${items.length}',
                        style: TextStyle(color: p.mut)),
                  ),
                  for (final m in items)
                    Builder(builder: (c) {
                      final buy = num.tryParse(pick(m, [buyKey])) ?? 0;
                      final unit = pick(m, ['unit']);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            _thumb(pick(m, ['imageUrl'])),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pick(m, ['productName']),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ໃຊ້ທັງໝົດ ${pick(m, ['totalUsed'])} · ໃຊ້ $_weeks ອາທິດ ${pick(m, ['used'])} · ສະຕັອກ ${pick(m, ['stock'])} $unit',
                                      style:
                                          TextStyle(color: p.mut, fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'ຄາດ: ອາທິດ ${pick(m, ['weekNeed'])} · ເດືອນ ${pick(m, ['monthNeed'])} · ປີ ${pick(m, ['yearNeed'])}',
                                      style:
                                          TextStyle(color: p.mut, fontSize: 13),
                                    ),
                                  ]),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: (buy > 0 ? Colors.orange : Colors.green)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                buy > 0 ? 'ຊື້ $buy' : 'ພໍ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: buy > 0
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
