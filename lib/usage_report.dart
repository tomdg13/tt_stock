import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'product_images.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart' show BarcodeScanPage;
import 'lao.dart';
import 'theme.dart';
import 'widgets.dart';

String _usD(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _usS(num n) => n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);

List<Map<String, dynamic>> _usList(dynamic d) {
  final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
  return asList(raw);
}

class UsageReportPage extends StatefulWidget {
  const UsageReportPage({super.key});
  @override
  State<UsageReportPage> createState() => _UsageReportPageState();
}

class _UsageReportPageState extends State<UsageReportPage> {
  late DateTimeRange _range;
  String? _branch;
  String _q = '';
  final _qc = TextEditingController();

  /// Take a photo with the camera and upload it to this product.
  Future<void> _uploadPhoto(String productId) async {
    final shot = await ImagePicker().pickImage(
        source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
    if (shot == null || !mounted) return;
    _toast('ກຳລັງອັບໂຫຼດຮູບ…');
    try {
      final bytes = await shot.readAsBytes();
      await uploadProductImages(productId, [PendingImage(shot.name, bytes)]);
      if (!mounted) return;
      setState(() => _future = _load());
      _toast('ອັບໂຫຼດຮູບສຳເລັດ');
    } catch (e) {
      if (mounted) _toast('ອັບໂຫຼດບໍ່ສຳເລັດ: $e');
    }
  }

  void _setQ(String v) {
    _qc.text = v;
    setState(() => _q = v);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Scan a barcode, look the product up, then filter the report by its name.
  Future<void> _scanSearch() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final d =
          await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
      final m = d is Map
          ? Map<String, dynamic>.from(d['data'] is Map ? d['data'] : d)
          : <String, dynamic>{};
      final name = pick(m, ['name', 'productName']);
      if (name.isNotEmpty) {
        _setQ(name);
        return;
      }
    } catch (_) {}
    if (mounted) _toast('ບໍ່ພົບສິນຄ້າ: $code');
  }

  /// Photo of the part label -> read the text -> pick the best matching product.
  Future<void> _photoSearch(List<Map<String, dynamic>> all) async {
    final shot = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 90);
    if (shot == null || !mounted) return;
    _toast('ກຳລັງອ່ານຂໍ້ຄວາມຈາກຮູບ…');
    var text = '';
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      text = (await rec.processImage(InputImage.fromFilePath(shot.path))).text;
    } catch (_) {
    } finally {
      await rec.close();
    }
    if (!mounted) return;
    final re = RegExp(r'[A-Za-z0-9\-]{3,}');
    final words =
        re.allMatches(text.toUpperCase()).map((m) => m.group(0)!).toSet();
    var best = '';
    var bestScore = 0;
    for (final r in all) {
      final name = pick(r, ['productName']);
      final score = re
          .allMatches(name.toUpperCase())
          .map((m) => m.group(0)!)
          .where(words.contains)
          .length;
      if (score > bestScore) {
        bestScore = score;
        best = name;
      }
    }
    if (best.isNotEmpty) {
      _setQ(best);
    } else {
      _toast('ບໍ່ພົບຊື່ສິນຄ້າໃນຮູບ');
    }
  }
  late Future<List<Map<String, dynamic>>> _future;
  Map<String, String> _imgs = {};

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _range = DateTimeRange(
        start: DateTime(n.year, n.month, 1),
        end: DateTime(n.year, n.month, n.day));
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get(
        '/stock/usage?from=${_usD(_range.start)}&to=${_usD(_range.end)}');
    try {
      final pr = await Api.get('/products?limit=200');
      debugPrint('PRODUCT SAMPLE: ${_usList(pr).isNotEmpty ? _usList(pr).first : pr}');
      _imgs = {
        for (final m in _usList(pr))
          '${pick(m, ['id', 'productId'])}':
              pick(m, ['imageUrl', 'image', 'photo', 'img', 'picture'])
      };
    } catch (e) {
      debugPrint('PRODUCTS ERR: $e');
    }
    return _usList(d);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ລາຍງານການນຳໃຊ້ອາໄຫຼ່'),
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
            for (final r in all) pick(r, ['branchName'])
          }.where((e) => e.isNotEmpty).toList()
            ..sort();
          final q = _q.trim().toUpperCase();
          final rows = all.where((r) {
            if (_branch != null && pick(r, ['branchName']) != _branch) {
              return false;
            }
            if (q.isEmpty) return true;
            return pick(r, ['productName']).toUpperCase().contains(q);
          }).toList();
          num tOpen = 0, tIn = 0, tOut = 0, tClose = 0;
          for (final r in rows) {
            tOpen += num0(r['opening']);
            tIn += num0(r['qtyIn']);
            tOut += num0(r['qtyOut']);
            tClose += num0(r['closing']);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text('${_usD(_range.start)} → ${_usD(_range.end)}'),
              onPressed: () async {
                final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: _range);
                if (r != null) {
                  setState(() {
                    _range = r;
                    _future = _load();
                  });
                }
              },
            ),
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
            const SizedBox(height: 8),
            TextField(
              controller: _qc,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'ຄົ້ນຫາອາໄຫຼ່',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_q.isNotEmpty)
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _setQ('')),
                  IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'ສະແກນບາໂຄດ',
                      onPressed: _scanSearch),
                  IconButton(
                      icon: const Icon(Icons.photo_camera_outlined),
                      tooltip: 'ຖ່າຍຮູບຊື່ອາໄຫຼ່',
                      onPressed: () => _photoSearch(all)),
                ]),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _cell('ຍອດຕົ້ນ', _usS(tOpen), null),
                      _cell('ນຳເຂົ້າ', _usS(tIn), Colors.green),
                      _cell('ເອົາອອກ', _usS(tOut), Colors.red),
                      _cell('ຍອດທ້າຍ', _usS(tClose), null),
                    ]),
              ),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))),
            for (final r in rows)
              InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => UsageCardPage(
                            row: r,
                            from: _usD(_range.start),
                            to: _usD(_range.end)))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.bd))),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _uploadPhoto('${r['productId']}'),
                            child: Stack(children: [
                              _thumb(context, _imgs['${r['productId']}'] ?? ''),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                          bottomRight: Radius.circular(8))),
                                  child: const Icon(Icons.photo_camera,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pick(r, ['productName']),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                      '${pick(r, ['branchName'])}  ${pick(r, ['unit'])}',
                                      style: TextStyle(
                                          color: p.mut, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _cell('ຍອດຕົ້ນ',
                                            _usS(num0(r['opening'])), null),
                                        _cell('ນຳເຂົ້າ',
                                            _usS(num0(r['qtyIn'])),
                                            Colors.green),
                                        _cell('ເອົາອອກ',
                                            _usS(num0(r['qtyOut'])),
                                            Colors.red),
                                        _cell('ຍອດທ້າຍ',
                                            _usS(num0(r['closing'])), null),
                                        const Icon(Icons.chevron_right),
                                      ]),
                                ]),
                          ),
                        ]),
                  ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _thumb(BuildContext context, String v) {
    final p = pal(context);
    final ph = Container(
      width: 48,
      height: 48,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: p.mut),
    );
    final url = productImageUrl(v);
    if (url.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph),
    );
  }

  Widget _cell(String label, String value, Color? c) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: c)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

/// Stock card: opening, every transaction with running balance, closing.
class UsageCardPage extends StatefulWidget {
  final Map<String, dynamic> row;
  final String from, to;
  const UsageCardPage(
      {super.key, required this.row, required this.from, required this.to});
  @override
  State<UsageCardPage> createState() => _UsageCardPageState();
}

class _UsageCardPageState extends State<UsageCardPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  static const _types = {
    'receive': 'ຮັບເຂົ້າ',
    'issue': 'ເອົາອອກ',
    'transfer_out': 'ໂອນອອກ',
    'transfer_in': 'ໂອນເຂົ້າ',
    'opening': 'ຍອດຍົກມາ',
  };

  Future<List<Map<String, dynamic>>> _load() async {
    final r = widget.row;
    final d = await Api.get(
        '/stock/movements?branchId=${pick(r, ['branchId'])}&productId=${pick(r, ['productId'])}&from=${widget.from}&to=${widget.to}&limit=2000');
    final list = _usList(d);
    String key(Map<String, dynamic> m) =>
        '${pick(m, ['movementDate'])}|${pick(m, ['id']).padLeft(12, '0')}';
    list.sort((a, b) => key(a).compareTo(key(b)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final r = widget.row;
    final opening = num0(r['opening']);
    return Scaffold(
      appBar: AppBar(title: Text(pick(r, ['productName']))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('ຜິດພາດ: ${snap.error}'));
          }
          final list = snap.data ?? [];
          num bal = opening;
          final tiles = <Widget>[];
          for (final m in list) {
            final ch = num0(m['qtyChange']);
            bal += ch;
            final t = pick(m, ['movementType']);
            final dt = pick(m, ['movementDate']);
            tiles.add(Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.bd))),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_types[t] ?? t,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            '${dt.length >= 10 ? dt.substring(0, 10) : dt}  ${pick(m, ['refNo'])}',
                            style: TextStyle(color: p.mut, fontSize: 12)),
                      ]),
                ),
                SizedBox(
                    width: 64,
                    child: Text('${ch > 0 ? '+' : ''}${_usS(ch)}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ch >= 0 ? Colors.green : Colors.red))),
                SizedBox(
                    width: 64,
                    child: Text(_usS(bal),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${pick(r, ['branchName'])}  •  ${widget.from} → ${widget.to}',
                style: TextStyle(color: p.mut)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _c('ຍອດຕົ້ນ', _usS(opening), null),
                      _c('ນຳເຂົ້າ', _usS(num0(r['qtyIn'])), Colors.green),
                      _c('ເອົາອອກ', _usS(num0(r['qtyOut'])), Colors.red),
                      _c('ຍອດທ້າຍ', _usS(num0(r['closing'])), null),
                    ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: const [
              Expanded(
                  child: Text('ທຸລະກຳ',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 64,
                  child: Text('ຈຳນວນ',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 64,
                  child: Text('ຍອດ',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const Divider(),
            if (tiles.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('ບໍ່ມີທຸລະກຳໃນຊ່ວງນີ້'))),
            ...tiles,
          ]);
        },
      ),
    );
  }

  Widget _c(String label, String value, Color? c) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: c)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}
