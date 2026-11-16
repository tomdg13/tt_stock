// Repair case workflow (7 steps, each step needs a document).
// Server: GET /repair/cases?barcode=, GET /repair/cases/:id,
//         POST /repair/cases (multipart: barcode, atmId, note, files)  -> opens the case at step 1
//         POST /repair/cases/:id/step (multipart: step, note, files)   -> saves the next step
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'crud.dart' show toastMsg;
import 'product_images.dart' show productImageUrl;
import 'purchase_orders.dart' show kPoDocExt;
import 'theme.dart';
import 'widgets.dart';

const kRepairSteps = [
  'ສາຂາຂໍ້ເຄືອງ',
  'ສ້າງສົງເຄືອງ',
  'ສາຂາຮັບເຄືອງ',
  'ລົງຕິດຕັ້ງ',
  'ສາຂາສົງເຄືອງກັບ',
  'ສ້າງຮັບເຄືອງ',
  'ສຳເລັດປິດເຄດ',
];
const _branchSteps = [1, 3, 4, 5];

/// 'branch' for steps 1,3,4,5 and 'hq' for steps 2,6,7
String repairSide(int n) => _branchSteps.contains(n) ? 'branch' : 'hq';
String repairSideLabel(int n) => repairSide(n) == 'hq' ? 'ສ້າງ' : 'ສາຂາ';
String repairStepName(int n) =>
    (n >= 1 && n <= 7) ? kRepairSteps[n - 1] : 'ຂັ້ນ $n';

/// 'hq' / 'branch' from the user's branch, or 'any' when unknown (server still checks).
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

Future<dynamic> _postMultipart(
    String path, Map<String, String> fields, List<_Doc> files) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.parse('$base$path');
  final req = http.MultipartRequest('POST', uri);
  if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
  req.fields.addAll(fields);
  for (final f in files) {
    final bytes = f.bytes;
    req.files.add(http.MultipartFile.fromBytes('files', bytes,
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

String _dt(dynamic v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '${v ?? ''}';
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}

String caseChipText(Map<String, dynamic> c) {
  if ('${c['status']}' == 'CLOSED') return 'ປິດເຄດແລ້ວ';
  final n = int.tryParse('${c['currentStep']}') ?? 1;
  return 'ຂັ້ນ $n · ${repairStepName(n)}';
}

// ---------------------------------------------------------------------------
// Section shown on the repair tab: list of cases of one terminal + open button
// ---------------------------------------------------------------------------
class RepairCasesSection extends StatefulWidget {
  final String barcode, atmId;
  const RepairCasesSection(this.barcode, {super.key, this.atmId = ''});
  @override
  State<RepairCasesSection> createState() => _RepairCasesSectionState();
}

class _RepairCasesSectionState extends State<RepairCasesSection> {
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    final d = await Api.get(
        '/repair/cases?barcode=${Uri.encodeQueryComponent(widget.barcode)}');
    return {'cases': asList(d), 'side': await repairMySide()};
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _open() async {
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RepairStepForm(
                stepNo: 1, barcode: widget.barcode, atmId: widget.atmId)));
    if (ok == true && mounted) _reload();
  }

  Future<void> _show(Map<String, dynamic> c, String side) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RepairCasePage(c,
                barcode: widget.barcode, atmId: widget.atmId, side: side)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Card(
            child: ListTile(
              title: Text('${snap.error}', style: TextStyle(color: p.bad)),
              trailing:
                  TextButton(onPressed: _reload, child: const Text('ລອງໃໝ່')),
            ),
          );
        }
        final data = snap.data ?? {};
        final cases = (data['cases'] as List).cast<Map<String, dynamic>>();
        final side = '${data['side']}';
        final hasOpen = cases.any((e) => '${e['status']}' == 'OPEN');
        final canOpen =
            Api.can('ATM_MANAGE') && hasOpen == false && side != 'hq';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('ເຄດສ້ອມ (7 ຂັ້ນຕອນ)',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              if (cases.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                      Text('ຍັງບໍ່ມີເຄດສ້ອມ', style: TextStyle(color: p.mut)),
                ),
              for (final cs in cases)
                Card(
                  child: ListTile(
                    leading: Icon(
                        '${cs['status']}' == 'CLOSED'
                            ? Icons.check_circle
                            : Icons.timelapse,
                        color: '${cs['status']}' == 'CLOSED'
                            ? Colors.green
                            : Colors.orange),
                    title: Text('ເຄດ #${cs['caseId']}  ${cs['refNo'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(caseChipText(cs)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _show(cs, side),
                  ),
                ),
              if (canOpen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    onPressed: _open,
                    icon: const Icon(Icons.add),
                    label: const Text('ເປີດເຄດສ້ອມ (ຂັ້ນ 1)'),
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
            ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Full page: 7-step timeline of one case
// ---------------------------------------------------------------------------
class RepairCasePage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String barcode, atmId, side;
  const RepairCasePage(this.data,
      {super.key, required this.barcode, this.atmId = '', this.side = 'any'});
  @override
  State<RepairCasePage> createState() => _RepairCasePageState();
}

class _RepairCasePageState extends State<RepairCasePage> {
  late Map<String, dynamic> _c = widget.data;

  int get _cur => int.tryParse('${_c['currentStep']}') ?? 1;
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
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RepairStepForm(
                stepNo: n,
                caseId: int.tryParse('${_c['caseId']}'),
                barcode: widget.barcode,
                atmId: widget.atmId)));
    if (ok == true) await _reload();
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
                _dt(row['stepDate']),
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
    final next = (_closed || _cur >= 7) ? null : _cur + 1;
    final canAct = next != null &&
        Api.can('ATM_MANAGE') &&
        (widget.side == 'any' || widget.side == repairSide(next));
    return Scaffold(
      appBar: AppBar(title: Text('ເຄດ #${_c['caseId']} · ${widget.barcode}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(caseChipText(_c),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if ('${_c['refNo'] ?? ''}'.isNotEmpty)
            Text('${_c['refNo']}', style: TextStyle(color: p.mut)),
          const SizedBox(height: 12),
          for (var n = 1; n <= 7; n++) _row(n),
          const SizedBox(height: 8),
          if (next != null && canAct)
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => _next(next),
                child:
                    Text('ອັບເດດສະຖານະ · ຂັ້ນ $next ${repairStepName(next)}'),
              ),
            ),
          if (next != null && canAct == false)
            Text('ລໍຖ້າ ${repairSideLabel(next)} ເຮັດຂັ້ນ $next',
                textAlign: TextAlign.center, style: TextStyle(color: p.mut)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form: note + documents (required) for one step
// ---------------------------------------------------------------------------
class _Doc {
  final String name;
  final Uint8List bytes;
  _Doc(this.name, this.bytes);
}

class RepairStepForm extends StatefulWidget {
  final int stepNo;
  final int? caseId; // null = open a new case (step 1)
  final String barcode, atmId;
  const RepairStepForm(
      {super.key,
      required this.stepNo,
      this.caseId,
      required this.barcode,
      this.atmId = ''});
  @override
  State<RepairStepForm> createState() => _RepairStepFormState();
}

class _RepairStepFormState extends State<RepairStepForm> {
  final _note = TextEditingController();
  final _files = <_Doc>[];
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId = Api.user?['branchId'];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.caseId == null) _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final b = asList(await Api.get('/repair/branches'));
      dynamic pre;
      if (widget.atmId.isNotEmpty) {
        final a = await Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
        final ab = a is Map ? '${a['atmBranchId'] ?? ''}'.toLowerCase() : '';
        for (final x in b) {
          final n = '${x['name'] ?? ''}'.toLowerCase();
          if (n.isNotEmpty && ab.contains(n)) {
            pre = x['id'];
            break;
          }
        }
      }
      pre ??= _branchId;
      if (mounted == false) return;
      setState(() {
        _branches = b;
        _branchId = pre;
      });
    } catch (_) {}
  }

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

  Future<void> _save() async {
    if (widget.caseId == null && _branchId == null) {
      setState(() => _error = 'ຫາສາຂາຂອງຕູ້ນີ້ບໍ່ເຫັນ');
      return;
    }
    if (_files.isEmpty) {
      setState(() => _error = 'ກະລຸນາແນບເອກະສານ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      if (widget.caseId == null) {
        await _postMultipart(
            '/repair/cases',
            {
              'barcode': widget.barcode,
              if (widget.atmId.isNotEmpty) 'atmId': widget.atmId,
              if (_branchId != null) 'branchId': '$_branchId',
              if (note.isNotEmpty) 'note': note,
            },
            _files);
      } else {
        await _postMultipart(
            '/repair/cases/${widget.caseId}/step',
            {
              'step': '${widget.stepNo}',
              if (note.isNotEmpty) 'note': note,
            },
            _files);
      }
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
        if (widget.caseId == null && _branchId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                'ສາຂາ: ${_branches.where((b) => b['id'] == _branchId).map((b) => pick(b, ['name'])).join()}',
                style: TextStyle(color: p.mut)),
          ),
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
