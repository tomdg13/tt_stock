// Purchase orders (PO): create a PO first, attach many documents to it, then pick it on the receive page.
// Server: GET/POST /purchase-orders, GET/PUT/DELETE /purchase-orders/:id,
//         POST /purchase-orders/:id/documents (multipart field "files"), DELETE /purchase-orders/:id/documents/:docId
// Needs:  flutter pub add file_picker url_launcher
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'crud.dart';
import 'product_images.dart' show productImageUrl;
import 'theme.dart';
import 'widgets.dart';

const _kDocExt = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'doc',
  'docx',
  'xls',
  'xlsx'
];

MediaType _mt(String name) {
  final l = name.toLowerCase();
  if (l.endsWith('.pdf')) return MediaType('application', 'pdf');
  if (l.endsWith('.png')) return MediaType('image', 'png');
  if (l.endsWith('.webp')) return MediaType('image', 'webp');
  if (l.endsWith('.jpg') || l.endsWith('.jpeg'))
    return MediaType('image', 'jpeg');
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

IconData _iconFor(String name) {
  final l = name.toLowerCase();
  if (l.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (l.endsWith('.xls') || l.endsWith('.xlsx'))
    return Icons.table_chart_outlined;
  if (l.endsWith('.doc') || l.endsWith('.docx'))
    return Icons.description_outlined;
  return Icons.image_outlined;
}

String _size(num b) {
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}

Future<void> uploadPoDocuments(String poId, List<PlatformFile> files) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final uri =
      Uri.parse('$base/purchase-orders/${Uri.encodeComponent(poId)}/documents');
  for (var i = 0; i < files.length; i += 10) {
    final req = http.MultipartRequest('POST', uri);
    if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
    for (final f in files.skip(i).take(10)) {
      final bytes = await f.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes('files', bytes,
          filename: f.name, contentType: _mt(f.name)));
    }
    if (req.files.isEmpty) continue;
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 120)));
    if (res.statusCode >= 400) {
      var msg = 'Error ${res.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map && d['message'] != null) {
          msg = d['message'] is List
              ? (d['message'] as List).join('\n')
              : '${d['message']}';
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }
}

// ------------------------------------------------------------------ picker
/// List of POs. Tap one to select it (returns the PO row). "+ ສ້າງ PO" creates a new one and selects it.
class PoPickerPage extends StatefulWidget {
  const PoPickerPage({super.key});
  @override
  State<PoPickerPage> createState() => _PoPickerPageState();
}

class _PoPickerPageState extends State<PoPickerPage> {
  final _q = TextEditingController();
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() =>
      Api.get('/purchase-orders?q=${Uri.encodeQueryComponent(_q.text.trim())}');
  void _reload() => setState(() {
        _f = _load();
      });

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final r = await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => const PoFormPage()));
    if (r != null && mounted) Navigator.pop(context, r);
  }

  Future<void> _edit(Map<String, dynamic> m) async {
    await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => PoFormPage(row: m)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ເລືອກ PO'),
        actions: [
          TextButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('ສ້າງ PO')),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _q,
            onChanged: (_) => _reload(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ຄົ້ນຫາ PO / ຫົວຂໍ້ / ຜູ້ສະໜອງ',
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _q.clear();
                        _reload();
                      }),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return Center(child: Text('${s.error}'));
              final rows = asList(s.data);
              if (rows.isEmpty) {
                return Center(
                    child: Text('ຍັງບໍ່ມີ PO — ກົດ "ສ້າງ PO"',
                        style: TextStyle(color: p.mut)));
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final m = rows[i];
                  final docs = int.tryParse(pick(m, ['docCount'])) ?? 0;
                  final sub = [
                    pick(m, ['title']),
                    pick(m, ['vendor'])
                  ].where((e) => e.isNotEmpty).join(' · ');
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, m),
                      title: Text(pick(m, ['poNo']),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: sub.isEmpty
                          ? null
                          : Text(sub,
                              style: TextStyle(color: p.mut, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (docs > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Row(children: [
                              Icon(Icons.attach_file, size: 16, color: p.mut),
                              Text('$docs', style: TextStyle(color: p.mut)),
                            ]),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'ແກ້ໄຂ / ເອກະສານ',
                          onPressed: () => _edit(m),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------------- form
class _PendingDoc {
  final PlatformFile file;
  final int size;
  _PendingDoc(this.file, this.size);
}

/// Create / edit a PO and manage its documents (one PO, many documents).
class PoFormPage extends StatefulWidget {
  final Map<String, dynamic>? row;
  const PoFormPage({super.key, this.row});
  @override
  State<PoFormPage> createState() => _PoFormPageState();
}

class _PoFormPageState extends State<PoFormPage> {
  final _no = TextEditingController();
  final _title = TextEditingController();
  final _vendor = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _docs = [];
  final _pending = <_PendingDoc>[];
  String? _id;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r != null) {
      _id = pick(r, ['id']);
      _no.text = pick(r, ['poNo']);
      _title.text = pick(r, ['title']);
      _vendor.text = pick(r, ['vendor']);
      _note.text = pick(r, ['note']);
      _loadDocs();
    }
  }

  @override
  void dispose() {
    _no.dispose();
    _title.dispose();
    _vendor.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    try {
      final d = await Api.get('/purchase-orders/${Uri.encodeComponent(_id!)}');
      if (d is Map && mounted) setState(() => _docs = asList(d['documents']));
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kDocExt,
    );
    if (files.isEmpty || !mounted) return;
    final added = <_PendingDoc>[];
    for (final f in files) {
      added.add(_PendingDoc(f, (await f.length()) ?? 0));
    }
    if (mounted) setState(() => _pending.addAll(added));
  }

  Future<void> _open(Map<String, dynamic> d) async {
    final url = productImageUrl(pick(d, ['url']));
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) toastMsg(context, 'ເປີດບໍ່ໄດ້: $e');
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບເອກະສານ?'),
        content: Text(pick(d, ['name'])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ລຶບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete(
          '/purchase-orders/${Uri.encodeComponent(_id!)}/documents/${pick(d, [
            'id'
          ])}');
      if (mounted)
        setState(() => _docs.removeWhere((x) => '${x['id']}' == '${d['id']}'));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final no = _no.text.trim();
    if (no.isEmpty) {
      setState(() => _error = 'ໃສ່ເລກ PO');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'poNo': no,
      'title': _title.text.trim(),
      'vendor': _vendor.text.trim(),
      'note': _note.text.trim(),
    };
    try {
      if (_id != null) {
        await Api.put('/purchase-orders/${Uri.encodeComponent(_id!)}', body);
      } else {
        final r = await Api.post('/purchase-orders', body);
        _id = r is Map ? pick(Map<String, dynamic>.from(r), ['id']) : null;
        if (_id == null || _id!.isEmpty) {
          _id = null;
          throw Exception('ບໍ່ພົບ id ຂອງ PO');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      if (_pending.isNotEmpty) {
        await uploadPoDocuments(_id!, _pending.map((e) => e.file).toList());
        _pending.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'ບັນທຶກ PO ແລ້ວ ແຕ່ອັບໂຫຼດໄຟລ໌ບໍ່ສຳເລັດ: $e';
          _busy = false;
        });
      }
      return;
    }
    if (!mounted) return;
    toastMsg(context, 'ບັນທຶກ PO ແລ້ວ');
    Navigator.pop(context, {
      'id': _id,
      'poNo': no,
      'title': _title.text.trim(),
      'vendor': _vendor.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: Text(_id == null ? 'ສ້າງ PO' : 'PO · ${_no.text}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          title: 'ຂໍ້ມູນ PO',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _no,
                decoration: const InputDecoration(labelText: 'ເລກ PO *')),
            const SizedBox(height: 12),
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'ຫົວຂໍ້')),
            const SizedBox(height: 12),
            VendorDropdown(controller: _vendor),
            const SizedBox(height: 12),
            TextField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
          ]),
        ),
        AppCard(
          title: 'ເອກະສານ (1 PO ມີໄດ້ຫຼາຍໄຟລ໌)',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_docs.isEmpty && _pending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('ຍັງບໍ່ມີເອກະສານ',
                    style: TextStyle(color: p.mut),
                    textAlign: TextAlign.center),
              ),
            for (final d in _docs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(pick(d, ['name']))),
                title: Text(pick(d, ['name']), overflow: TextOverflow.ellipsis),
                subtitle: Text(_size(num.tryParse(pick(d, ['size'])) ?? 0),
                    style: TextStyle(color: p.mut, fontSize: 12)),
                onTap: () => _open(d),
                trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: p.bad),
                    onPressed: () => _deleteDoc(d)),
              ),
            for (var i = 0; i < _pending.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(_pending[i].file.name)),
                title: Text(_pending[i].file.name,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text('${_size(_pending[i].size)} · ລໍຖ້າອັບໂຫຼດ',
                    style: TextStyle(color: p.mut, fontSize: 12)),
                trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _pending.removeAt(i))),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.attach_file),
              label: const Text('ເພີ່ມເອກະສານ'),
            ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: p.bad)),
          ),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ບັນທຶກ PO'),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- dropdown
/// Dropdown of existing POs with a "+" button to create a new PO right here
/// (and an edit button to open the selected PO and manage its documents).
/// [value] / [onChanged] use the PO number (poNo).
class PoDropdown extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  const PoDropdown(
      {super.key,
      required this.value,
      required this.onChanged,
      this.label = 'ເລກ PO'});
  @override
  State<PoDropdown> createState() => _PoDropdownState();
}

class _PoDropdownState extends State<PoDropdown> {
  List<Map<String, dynamic>> _pos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/purchase-orders');
      if (mounted) {
        setState(() {
          _pos = asList(d);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final r = await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => const PoFormPage()));
    if (r == null || !mounted) return;
    await _load();
    widget.onChanged(pick(r, ['poNo']));
  }

  Future<void> _edit() async {
    final cur = _pos.where((m) => pick(m, ['poNo']) == widget.value).toList();
    if (cur.isEmpty) return;
    await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => PoFormPage(row: cur.first)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final has = _pos.any((m) => pick(m, ['poNo']) == widget.value);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('po-${_pos.length}-${widget.value}'),
          initialValue: has ? widget.value : null,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: widget.label,
              hintText: _loading ? 'ກຳລັງໂຫຼດ…' : null),
          items: [
            const DropdownMenuItem<String>(
                value: null, child: Text('— ບໍ່ລະບຸ —')),
            for (final m in _pos)
              DropdownMenuItem<String>(
                value: pick(m, ['poNo']),
                child: Text(
                  [
                    pick(m, ['poNo']),
                    pick(m, ['title'])
                  ].where((e) => e.isNotEmpty).join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.onChanged,
        ),
      ),
      IconButton.filledTonal(
        icon: const Icon(Icons.add),
        tooltip: 'ສ້າງ PO ໃໝ່',
        onPressed: _add,
      ),
      if (has)
        IconButton(
          icon: const Icon(Icons.attach_file),
          tooltip: 'ແກ້ໄຂ / ເອກະສານ PO',
          onPressed: _edit,
        ),
    ]);
  }
}

// ---------------------------------------------------------- vendor dropdown
class VendorDropdown extends StatefulWidget {
  final TextEditingController controller;
  const VendorDropdown({super.key, required this.controller});
  @override
  State<VendorDropdown> createState() => _VendorDropdownState();
}

class _VendorDropdownState extends State<VendorDropdown> {
  List<String> _names = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/vendors');
      final names = <String>[];
      for (final m in asList(d)) {
        final off = '${m['isActive'] ?? 1}';
        if (off == '0' || off == 'false') continue;
        final n = pick(m, ['name']);
        if (n.isNotEmpty) names.add(n);
      }
      if (mounted) {
        setState(() {
          _names = names;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
        context: context, builder: (_) => const _VendorDialog());
    if (name == null || name.isEmpty || !mounted) return;
    final exists = _names.any((n) => n.toLowerCase() == name.toLowerCase());
    if (!exists) {
      try {
        await Api.post('/vendors', {'name': name});
        await _load();
      } catch (e) {
        if (mounted) toastMsg(context, '$e');
        return;
      }
    }
    if (mounted) setState(() => widget.controller.text = name);
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.controller.text.trim();
    final items = [..._names];
    if (cur.isNotEmpty && !items.contains(cur)) items.add(cur);
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('v-${items.length}-$cur'),
          initialValue: cur.isEmpty ? null : cur,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: 'ຜູ້ສະໜອງ', hintText: _loading ? 'ກຳລັງໂຫຼດ…' : null),
          items: [
            const DropdownMenuItem<String>(
                value: null, child: Text('— ບໍ່ລະບຸ —')),
            for (final n in items)
              DropdownMenuItem<String>(
                  value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => widget.controller.text = v ?? ''),
        ),
      ),
      IconButton.filledTonal(
        icon: const Icon(Icons.add),
        tooltip: 'ເພີ່ມຜູ້ສະໜອງ',
        onPressed: _add,
      ),
    ]);
  }
}

class _VendorDialog extends StatefulWidget {
  const _VendorDialog();
  @override
  State<_VendorDialog> createState() => _VendorDialogState();
}

class _VendorDialogState extends State<_VendorDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ເພີ່ມຜູ້ສະໜອງ'),
      content: TextField(
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'ຊື່ຜູ້ສະໜອງ'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ')),
        FilledButton(
          onPressed: () {
            final n = _c.text.trim();
            Navigator.pop(context, n.isEmpty ? null : n);
          },
          child: const Text('ບັນທຶກ'),
        ),
      ],
    );
  }
}
