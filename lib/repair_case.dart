// Repair cases: one case = one repair of one terminal, 6 steps, each step needs a document.
// Flow: pick parts (FixTerminalPage) -> case created (step 0) -> print the request form,
//       the branch signs it -> attach the signed document (step 1) -> steps 2..6.
// Step 3 cuts the stock (Head Office) and reinstalls the terminal (done by the server).
// Server: GET /repair/cases?barcode=, GET /repair/cases/:id,
//         POST /repair/cases (json), POST /repair/cases/:id/step (multipart: step, note, files)
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'crud.dart' show toastMsg;
import 'product_images.dart' show productImageUrl;
import 'purchase_orders.dart' show kPoDocExt;
import 'terminal_actions.dart' show FixTerminalPage;
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Steps and helpers
// ---------------------------------------------------------------------------
const kRepairSteps = [
  'ສາຂາຂໍ້ເຄືອງ',
  'ສ້າງສົງເຄືອງ',
  'ລົງຕິດຕັ້ງ',
  'ສາຂາສົງເຄືອງກັບ',
  'ສ້າງຮັບເຄືອງ',
  'ສຳເລັດປິດເຄດ',
];
const _branchSteps = [1, 3, 4];

/// 'branch' for steps 1,3,4 and 'hq' for steps 2,5,6
String repairSide(int n) => _branchSteps.contains(n) ? 'branch' : 'hq';
String repairSideLabel(int n) => repairSide(n) == 'hq' ? 'ສ້າງ' : 'ສາຂາ';
String repairStepName(int n) =>
    (n >= 1 && n <= kRepairSteps.length) ? kRepairSteps[n - 1] : 'ຂັ້ນ $n';

String nextStepLabel(int n) => n == 1
    ? 'ແນບເອກະສານທີ່ເຊັນແລ້ວ (ຂັ້ນ 1)'
    : 'ຂັ້ນ $n · ${repairStepName(n)}';
String waitingLabel(int n) =>
    'ລໍຖ້າ ${repairSideLabel(n)} ເຮັດຂັ້ນ $n · ${repairStepName(n)}';

String caseChipText(Map<String, dynamic> c) {
  if ('${c['status']}' == 'CLOSED') return 'ປິດເຄດແລ້ວ';
  final n = int.tryParse('${c['currentStep']}') ?? 0;
  if (n == 0) return 'ລໍຖ້າເອກະສານເຊັນ (ຂັ້ນ 1)';
  return 'ຂັ້ນ $n · ${repairStepName(n)}';
}

/// 'hq' / 'branch' from the user's branch, or 'any' when unknown (the server still checks).
Future<String> repairMySide() async {
  final b = Api.user?['branchId'];
  if (b == null) return 'any';
  try {
    final rows = asList(await Api.get('/repair/branches'));
    for (final r in rows) {
      if ('${r['id']}' == '$b') return '${r['isHq']}' == '1' ? 'hq' : 'branch';
    }
  } catch (_) {}
  return 'any';
}

String _dt(dynamic v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '${v ?? ''}';
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}

MediaType _rmt(String name) {
  final l = name.toLowerCase();
  if (l.endsWith('.pdf')) return MediaType('application', 'pdf');
  if (l.endsWith('.jpg') || l.endsWith('.jpeg')) {
    return MediaType('image', 'jpeg');
  }
  if (l.endsWith('.png')) return MediaType('image', 'png');
  if (l.endsWith('.webp')) return MediaType('image', 'webp');
  if (l.endsWith('.docx')) {
    return MediaType('application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document');
  }
  if (l.endsWith('.doc')) return MediaType('application', 'msword');
  if (l.endsWith('.xlsx')) {
    return MediaType(
        'application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  if (l.endsWith('.xls')) return MediaType('application', 'vnd.ms-excel');
  return MediaType('application', 'octet-stream');
}

class _Doc {
  final String name;
  final Uint8List bytes;
  _Doc(this.name, this.bytes);
}

Future<dynamic> _postMultipart(
    String path, Map<String, String> fields, List<_Doc> files) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base$path');
  final req = http.MultipartRequest('POST', uri);
  if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
  req.fields.addAll(fields);
  for (final f in files) {
    req.files.add(http.MultipartFile.fromBytes('files', f.bytes,
        filename: f.name, contentType: _rmt(f.name)));
  }
  apiLog(
      '-> POST $uri  multipart fields=$fields files=${files.map((e) => e.name).toList()}');
  final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 90)));
  final body = utf8.decode(res.bodyBytes, allowMalformed: true);
  apiLog('<- ${res.statusCode} POST $uri\n      ${apiClip(body)}');
  if (res.statusCode >= 400) {
    var msg = 'Error ${res.statusCode}';
    try {
      final d = jsonDecode(body);
      if (d is Map && d['message'] != null) {
        msg = d['message'] is List
            ? (d['message'] as List).join(', ')
            : '${d['message']}';
      }
    } catch (_) {}
    throw Exception(msg);
  }
  return jsonDecode(body);
}

/// Opens the form of one step. true = saved.
Future<bool> openStepForm(BuildContext context, Map<String, dynamic> c,
    int step, String barcode) async {
  final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => RepairStepForm(
                stepNo: step,
                caseId: int.tryParse('${c['caseId']}') ?? 0,
                barcode: barcode,
                atmId: '',
              )));
  return ok == true;
}

// ---------------------------------------------------------------------------
// Page of one terminal: its repair cases + create a new case
// ---------------------------------------------------------------------------
class TerminalRepairPage extends StatefulWidget {
  final Map<String, dynamic> terminal;
  final VoidCallback? onChanged;
  const TerminalRepairPage(this.terminal, {super.key, this.onChanged});
  @override
  State<TerminalRepairPage> createState() => _TerminalRepairPageState();
}

class _TerminalRepairPageState extends State<TerminalRepairPage> {
  late Future<Map<String, dynamic>> _f = _load();

  String get _barcode => pick(widget.terminal, ['barcode']);
  String get _atm => pick(widget.terminal, ['atmId']);

  Future<Map<String, dynamic>> _load() async {
    final d = await Api.get(
        '/repair/cases?barcode=${Uri.encodeQueryComponent(_barcode)}');
    return {'cases': asList(d), 'side': await repairMySide()};
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _create() async {
    final r = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                FixTerminalPage(widget.terminal, onChanged: widget.onChanged)));
    if (!mounted) return;
    _reload();
    if (r is Map) {
      // show the request form right away so it can be printed and signed
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  RepairRequestFormPage(Map<String, dynamic>.from(r))));
      if (mounted) _reload();
    }
  }

  Future<void> _next(Map<String, dynamic> c, int n) async {
    if (await openStepForm(context, c, n, _barcode)) {
      widget.onChanged?.call();
      if (mounted) _reload();
    }
  }

  Future<void> _form(Map<String, dynamic> c) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => RepairRequestFormPage(c)));
  }

  Future<void> _details(Map<String, dynamic> c, String side) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RepairCasePage(c, barcode: _barcode, side: side)));
    widget.onChanged?.call();
    if (mounted) _reload();
  }

  Widget _progress(int cur, bool closed) {
    final p = pal(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Row(children: [
      for (var n = 1; n <= kRepairSteps.length; n++)
        Expanded(
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: n <= cur ? Colors.green : null,
                border: Border.all(
                    color: n <= cur
                        ? Colors.green
                        : (n == cur + 1 && closed == false)
                            ? primary
                            : p.bd,
                    width: 1.5),
              ),
              child: n <= cur
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text('$n',
                      style: TextStyle(
                          fontSize: 12, color: n == cur + 1 ? primary : p.mut)),
            ),
          ),
        ),
    ]);
  }

  Widget _card(Map<String, dynamic> c, String side) {
    final p = pal(context);
    final cur = int.tryParse('${c['currentStep']}') ?? 0;
    final closed = '${c['status']}' == 'CLOSED';
    final next = (closed || cur >= kRepairSteps.length) ? null : cur + 1;
    final canAct = next != null &&
        Api.can('ATM_MANAGE') &&
        (side == 'any' || side == repairSide(next));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ເຄດ ${c['reqNo'] ?? '#${c['caseId']}'}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _progress(cur, closed),
          const SizedBox(height: 8),
          Text(caseChipText(c),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final pt in asList(c['parts']))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  '• ${pick(pt, ['name'])}  × ${pick(pt, ['qty'])} ${pick(pt, [
                        'unit'
                      ])}',
                  style: TextStyle(color: p.mut, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          if (next != null && canAct)
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => _next(c, next),
                child: Text(nextStepLabel(next)),
              ),
            ),
          if (next != null && canAct == false)
            Text(waitingLabel(next),
                textAlign: TextAlign.center, style: TextStyle(color: p.mut)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _form(c),
                icon: const Icon(Icons.description_outlined),
                label: const Text('ໃບຂໍອາໄຫຼ່'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _details(c, side),
                icon: const Icon(Icons.timeline),
                label: const Text('ລາຍລະອຽດ'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: Text('ເຄດສ້ອມ · $_barcode')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(24), children: [
                Text('${snap.error}', style: TextStyle(color: p.bad)),
                TextButton(onPressed: _reload, child: const Text('ລອງໃໝ່')),
              ]);
            }
            final data = snap.data ?? {};
            final cases = (data['cases'] as List).cast<Map<String, dynamic>>();
            final side = '${data['side']}';
            final open =
                cases.where((e) => '${e['status']}' == 'OPEN').toList();
            final done =
                cases.where((e) => '${e['status']}' != 'OPEN').toList();
            final canCreate =
                Api.can('ATM_MANAGE') && open.isEmpty && side != 'hq';
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(_barcode,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    pick(widget.terminal, ['typeName']),
                    if (_atm.isNotEmpty) 'ຕູ້ $_atm',
                    pick(widget.terminal, ['state']),
                  ].where((e) => e.isNotEmpty).join('  ·  ')),
                ),
              ),
              const SizedBox(height: 8),
              if (canCreate)
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('ສ້າງເຄດສ້ອມ (ເລືອກອາໄຫຼ່)'),
                  ),
                ),
              if (open.isEmpty && side == 'hq')
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('ສາຂາເປັນຜູ້ສ້າງເຄດ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.mut)),
                ),
              if (cases.isEmpty && canCreate == false && side != 'hq')
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('ຍັງບໍ່ມີເຄດສ້ອມ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.mut)),
                ),
              for (final cs in open) _card(cs, side),
              if (done.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Text('ເຄດທີ່ປິດແລ້ວ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                for (final cs in done) _card(cs, side),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full page: 6-step timeline of one case
// ---------------------------------------------------------------------------
class RepairCasePage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String barcode, side;
  const RepairCasePage(this.data,
      {super.key, required this.barcode, this.side = 'any'});
  @override
  State<RepairCasePage> createState() => _RepairCasePageState();
}

class _RepairCasePageState extends State<RepairCasePage> {
  late Map<String, dynamic> _c = widget.data;

  int get _cur => int.tryParse('${_c['currentStep']}') ?? 0;
  bool get _closed => '${_c['status']}' == 'CLOSED';

  Map<String, dynamic>? _stepRow(int n) {
    for (final s in asList(_c['steps'])) {
      if ('${s['stepNo']}' == '$n') return s;
    }
    return null;
  }

  Future<void> _reload() async {
    try {
      final d = await Api.get('/repair/cases/${_c['caseId']}');
      if (d is Map && mounted) {
        setState(() => _c = Map<String, dynamic>.from(d));
      }
    } catch (_) {}
  }

  Future<void> _next(int n) async {
    if (await openStepForm(context, _c, n, widget.barcode)) await _reload();
  }

  Future<void> _openDoc(Map<String, dynamic> d) async {
    final url = productImageUrl(pick(d, ['url']));
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) toastMsg(context, 'ເປີດບໍ່ໄດ້: $e');
    }
  }

  Widget _row(int n) {
    final p = pal(context);
    final row = _stepRow(n);
    final done = row != null;
    final isNext = done == false && _closed == false && n == _cur + 1;
    final color = done
        ? Colors.green
        : isNext
            ? Theme.of(context).colorScheme.primary
            : p.mut;
    final docs = done ? asList(row['docs']) : <Map<String, dynamic>>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: isNext ? color : p.bd),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              done
                  ? Icons.check_circle
                  : isNext
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text('ຂັ້ນ $n · ${repairStepName(n)}',
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ),
          Text(repairSideLabel(n),
              style: TextStyle(color: p.mut, fontSize: 12)),
        ]),
        if (done) ...[
          const SizedBox(height: 6),
          Text(
              [
                pick(row, ['userName']),
                _dt(row['stepDate'])
              ].where((e) => e.isNotEmpty).join('  ·  '),
              style: TextStyle(color: p.mut, fontSize: 12)),
          if (pick(row, ['note']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(pick(row, ['note'])),
            ),
          for (final d in docs)
            InkWell(
              onTap: () => _openDoc(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.attach_file, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(pick(d, ['name']),
                        style: const TextStyle(
                            decoration: TextDecoration.underline)),
                  ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final next = (_closed || _cur >= kRepairSteps.length) ? null : _cur + 1;
    final canAct = next != null &&
        Api.can('ATM_MANAGE') &&
        (widget.side == 'any' || widget.side == repairSide(next));
    final parts = asList(_c['parts']);
    return Scaffold(
      appBar: AppBar(title: Text('ເຄດ ${_c['reqNo'] ?? '#${_c['caseId']}'}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(caseChipText(_c),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${widget.barcode}  ·  ${_c['refNo'] ?? ''}',
              style: TextStyle(color: p.mut)),
          const SizedBox(height: 12),
          if (parts.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ອາໄຫຼ່ທີ່ຂໍ',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final pt in parts)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Expanded(child: Text(pick(pt, ['name']))),
                            Text(
                                '× ${pick(pt, ['qty'])} ${pick(pt, ['unit'])}'),
                          ]),
                        ),
                    ]),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => RepairRequestFormPage(_c))),
            icon: const Icon(Icons.description_outlined),
            label: const Text('ເບິ່ງ / ພິມ / ແຊຣ໌ ໃບຂໍອາໄຫຼ່'),
          ),
          const SizedBox(height: 12),
          for (var n = 1; n <= kRepairSteps.length; n++) _row(n),
          const SizedBox(height: 8),
          if (next != null && canAct)
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => _next(next),
                child: Text(nextStepLabel(next)),
              ),
            ),
          if (next != null && canAct == false)
            Text(waitingLabel(next),
                textAlign: TextAlign.center, style: TextStyle(color: p.mut)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form: note + documents (required) for one step. Take a photo or pick a file.
// ---------------------------------------------------------------------------
class RepairStepForm extends StatefulWidget {
  final int stepNo, caseId;
  final String barcode;
  const RepairStepForm(
      {super.key,
      required this.stepNo,
      required this.caseId,
      required this.barcode,
      required String atmId});
  @override
  State<RepairStepForm> createState() => _RepairStepFormState();
}

class _RepairStepFormState extends State<RepairStepForm> {
  final _note = TextEditingController();
  final _files = <_Doc>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('ຖ່າຍຮູບເອກະສານ'),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('ເລືອກຮູບຈາກຄັງຮູບ'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('ເລືອກໄຟລ໌ (PDF, Word, Excel, ຮູບ)'),
            onTap: () => Navigator.pop(c, 'file'),
          ),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    try {
      if (how == 'file') {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: kPoDocExt,
        );
        if (files.isEmpty || !mounted) return;
        final add = <_Doc>[];
        for (final f in files) {
          add.add(_Doc(f.name, await f.readAsBytes()));
        }
        if (mounted) setState(() => _files.addAll(add));
      } else {
        final x = await ImagePicker().pickImage(
            source: how == 'camera' ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 85,
            maxWidth: 2400);
        if (x == null || !mounted) return;
        final bytes = await x.readAsBytes();
        var name = x.name;
        if (name.isEmpty) {
          name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        }
        if (RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false)
                .hasMatch(name) ==
            false) {
          name = '$name.jpg';
        }
        if (mounted) setState(() => _files.add(_Doc(name, bytes)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'ເປີດກ້ອງ/ໄຟລ໌ບໍ່ໄດ້: $e');
    }
  }

  Future<bool> _confirmStep4() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ຢືນຢັນຂັ້ນ 4'),
        content: const Text(
            'ຈະຕັດສະຕັອກອາໄຫຼ່ຂອງເຄດນີ້ຈາກ Head Office ແລະຕິດຕັ້ງ terminal ຄືນເຂົ້າຕູ້ (In Use). ດຳເນີນການຕໍ່ບໍ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ຢືນຢັນ')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (_files.isEmpty) {
      setState(() => _error = 'ກະລຸນາແນບເອກະສານ');
      return;
    }
    if (widget.stepNo == 3) {
      final ok = await _confirmStep4();
      if (ok == false || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await _postMultipart(
          '/repair/cases/${widget.caseId}/step',
          {
            'step': '${widget.stepNo}',
            if (note.isNotEmpty) 'note': note,
          },
          _files);
      if (!mounted) return;
      toastMsg(context, 'ບັນທຶກຂັ້ນ ${widget.stepNo} ແລ້ວ');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final n = widget.stepNo;
    return Scaffold(
      appBar: AppBar(title: Text('ຂັ້ນ $n · ${repairStepName(n)}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.barcode}  ·  ${repairSideLabel(n)}',
            style: TextStyle(color: p.mut)),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)'),
        ),
        const SizedBox(height: 12),
        const Text('ເອກະສານ (ຈຳເປັນ)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < _files.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(_files[i].name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(Icons.close, color: p.bad),
              onPressed:
                  _busy ? null : () => setState(() => _files.removeAt(i)),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.attach_file),
          label: const Text('ຖ່າຍຮູບ / ເພີ່ມເອກະສານ'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error ?? '', style: TextStyle(color: p.bad)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ບັນທຶກ'),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Request form (ໃບຂໍອາໄຫຼ່): shown on screen, then printed or shared as PDF.
// The sheet is drawn by Flutter (correct Lao text) and put into the PDF as an image.
// ---------------------------------------------------------------------------
class RepairRequestFormPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const RepairRequestFormPage(this.data, {super.key});
  @override
  State<RepairRequestFormPage> createState() => _RepairRequestFormPageState();
}

class _RepairRequestFormPageState extends State<RepairRequestFormPage> {
  final _key = GlobalKey();
  late final Future<Map<String, String>> _f = _info();
  bool _busy = false;

  String get _name => '${widget.data['reqNo'] ?? 'repair-request'}';

  Future<Map<String, String>> _info() async {
    final d = widget.data;
    final out = {'branch': '', 'atm': '', 'type': ''};
    try {
      for (final b in asList(await Api.get('/repair/branches'))) {
        if ('${b['id']}' == '${d['branchId']}')
          out['branch'] = pick(b, ['name']);
      }
    } catch (_) {}
    final atmId = '${d['atmId'] ?? ''}';
    if (atmId.isNotEmpty) {
      try {
        final a = await Api.get('/atms/${Uri.encodeComponent(atmId)}');
        if (a is Map) {
          out['atm'] = pick(Map<String, dynamic>.from(a), ['atmLocation']);
        }
      } catch (_) {}
    }
    try {
      final t = await Api.get(
          '/terminals/${Uri.encodeComponent('${d['barcode'] ?? ''}')}');
      if (t is Map) {
        out['type'] = pick(Map<String, dynamic>.from(t), ['typeName']);
      }
    } catch (_) {}
    return out;
  }

  Future<Uint8List> _pdf() async {
    final obj = _key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) throw Exception('ໜ້າຍັງບໍ່ພ້ອມ');
    final image = await obj.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('ສ້າງຮູບບໍ່ໄດ້');
    final img = pw.MemoryImage(data.buffer.asUint8List());
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
    ));
    return doc.save();
  }

  Future<void> _run(Future<void> Function(Uint8List) fn) async {
    setState(() => _busy = true);
    try {
      await fn(await _pdf());
    } catch (e) {
      if (mounted) toastMsg(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sheet(Map<String, String> info) {
    final d = widget.data;
    final parts = asList(d['parts']);
    const base = TextStyle(color: Colors.black, fontSize: 14, height: 1.4);
    const bold = TextStyle(
        color: Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4);
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: bold)),
            Expanded(child: Text(v.isEmpty ? '-' : v, style: base)),
          ]),
        );
    Widget cell(String t, {bool head = false}) => Padding(
          padding: const EdgeInsets.all(6),
          child: Text(t, style: head ? bold : base),
        );
    Widget sign(String title) => Expanded(
          child: Column(children: [
            const SizedBox(height: 64),
            Container(
                height: 1,
                color: Colors.black54,
                margin: const EdgeInsets.symmetric(horizontal: 16)),
            const SizedBox(height: 4),
            Text(title, style: bold),
            const SizedBox(height: 4),
            const Text('ວັນທີ ........../........../..........', style: base),
          ]),
        );
    final date = _dt(d['openedAt']);
    return Container(
      width: 595,
      color: Colors.white,
      padding: const EdgeInsets.all(32),
      child: DefaultTextStyle(
        style: base,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('ໃບຂໍອາໄຫຼ່',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('ເລກທີ່: ${d['reqNo'] ?? ''}',
                  textAlign: TextAlign.center, style: bold),
              const SizedBox(height: 16),
              kv('ວັນທີ', date.length >= 10 ? date.substring(0, 10) : date),
              kv('ສາຂາ', info['branch'] ?? ''),
              kv('ຕູ້ ATM', '${d['atmId'] ?? ''}  ${info['atm'] ?? ''}'.trim()),
              kv('Terminal',
                  '${d['barcode'] ?? ''}  ${info['type'] ?? ''}'.trim()),
              const SizedBox(height: 12),
              const Text('ລາຍການອາໄຫຼ່ທີ່ຂໍ', style: bold),
              const SizedBox(height: 6),
              Table(
                border: TableBorder.all(color: Colors.black54),
                columnWidths: const {
                  0: FixedColumnWidth(56),
                  1: FlexColumnWidth(3),
                  2: FlexColumnWidth(2),
                  3: FixedColumnWidth(70),
                  4: FixedColumnWidth(60),
                },
                children: [
                  TableRow(children: [
                    cell('ລຳດັບ', head: true),
                    cell('ຊື່ອາໄຫຼ່', head: true),
                    cell('Part No', head: true),
                    cell('ຫົວໜ່ວຍ', head: true),
                    cell('ຈຳນວນ', head: true),
                  ]),
                  for (var i = 0; i < parts.length; i++)
                    TableRow(children: [
                      cell('${i + 1}'),
                      cell(pick(parts[i], ['name'])),
                      cell(pick(parts[i], ['partNo'])),
                      cell(pick(parts[i], ['unit'])),
                      cell(pick(parts[i], ['qty'])),
                    ]),
                ],
              ),
              const SizedBox(height: 12),
              kv('ໝາຍເຫດ', '${d['remark'] ?? ''}'),
              const SizedBox(height: 24),
              Row(children: [sign('ຜູ້ຂໍ'), sign('ຫົວໜ້າສາຂາ')]),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ໃບຂໍອາໄຫຼ່ · $_name')),
      body: FutureBuilder<Map<String, String>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              fit: BoxFit.fitWidth,
              child: RepaintBoundary(
                key: _key,
                child: _sheet(snap.data ?? {}),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((bytes) async {
                          await Printing.layoutPdf(
                              onLayout: (_) async => bytes, name: _name);
                        }),
                icon: const Icon(Icons.print_outlined),
                label: const Text('ພິມ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((bytes) async {
                          await Printing.sharePdf(
                              bytes: bytes, filename: '$_name.pdf');
                        }),
                icon: const Icon(Icons.ios_share),
                label: const Text('ແຊຣ໌ PDF'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
