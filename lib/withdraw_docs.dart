import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'plan_bar.dart';
import 'product_images.dart' show productImageUrl;
import 'purchase_orders.dart' show kPoDocExt;
import 'withdraw_bill.dart' show WithdrawBillPage;

/// Documents of an approved withdrawal (upload by the branch, check by Head Office).
/// Server: POST/GET /withdrawals/:id/docs, POST /withdrawals/:id/check.
/// DOC_STATUS: empty -> submitted -> checked | rejected.

class _WdFile {
  final String name;
  final Uint8List bytes;
  const _WdFile(this.name, this.bytes);
}

String _wdMime(String name) {
  final e = name.toLowerCase().split('.').last;
  const m = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return m[e] ?? 'application/octet-stream';
}

String wdDocStatusLabel(String s) => s == 'submitted'
    ? 'ລໍຖ້າກວດ'
    : s == 'checked'
        ? 'ກວດແລ້ວ (ຜ່ານ)'
        : s == 'rejected'
            ? 'ບໍ່ຜ່ານ (ອັບໃໝ່ໄດ້)'
            : 'ຍັງບໍ່ໄດ້ອັບເອກະສານ';

Color wdDocStatusColor(String s) => s == 'submitted'
    ? Colors.orange
    : s == 'checked'
        ? Colors.green
        : s == 'rejected'
            ? Colors.red
            : Colors.grey;

String wdStageLabel(int s) => const {
      2: 'ຂັ້ນ 2 · ອັບເອກະສານທີ່ເຊັນແລ້ວ',
      3: 'ຂັ້ນ 3 · HQ ອະນຸມັດ (ອັບໃບສົ່ງເຄື່ອງໄດ້)',
      4: 'ຂັ້ນ 4 · ສາຂາຮັບເຄື່ອງ (ຮູບເຄື່ອງທີ່ໄດ້ຮັບ)',
      5: 'ຂັ້ນ 5 · ຕິດຕັ້ງ (ຮູບເຄື່ອງທີ່ຕິດຕັ້ງ)',
      6: 'ຂັ້ນ 6 · ສົ່ງອາໄຫຼ່ມີບັນຫາກັບ (ຮູບ)',
      7: 'ຂັ້ນ 7 · HQ ຮັບຄືນ ແລະ ປິດເຄດ (ຮູບ)',
    }[s] ?? 'ຂັ້ນ $s';

String _wdWhen(dynamic v) {
  final s = '${v ?? ''}'.replaceFirst('T', ' ');
  return s.length >= 16 ? s.substring(0, 16) : s;
}

// ---------------------------------------------------------------------------
// Section shown inside the bill page: documents + upload
// ---------------------------------------------------------------------------
class WithdrawDocsSection extends StatefulWidget {
  final Map<String, dynamic> w;
  final bool canUpload;
  final VoidCallback? onChanged;
  const WithdrawDocsSection(this.w,
      {super.key, this.canUpload = true, this.onChanged});
  @override
  State<WithdrawDocsSection> createState() => WithdrawDocsSectionState();
}

class WithdrawDocsSectionState extends State<WithdrawDocsSection> {
  List<Map<String, dynamic>> _docs = [];
  final List<_WdFile> _pending = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _id => '${widget.w['id']}';
  String get _status => '${widget.w['status'] ?? ''}';
  String get _docStatus => '${widget.w['docStatus'] ?? ''}';
  int get _stage => int.tryParse('${widget.w['stage'] ?? ''}') ?? 2;
  bool _problem = false;
  final TextEditingController _noteC = TextEditingController();
  bool get _mayUpload =>
      widget.canUpload &&
      _status != 'closed' &&
      _stage >= 2 &&
      _stage <= 7 &&
      Api.can('WD_S$_stage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteC.dispose();
    super.dispose();
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/withdrawals/$_id/docs');
      if (!mounted) return;
      setState(() {
        _docs = d is List
            ? [
                for (final e in d)
                  if (e is Map) Map<String, dynamic>.from(e)
              ]
            : [];
        _loading = false;
      });
    } catch (e) {
      debugPrint('[WD] docs load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> reload() => _load();

  void pickFiles() {
    if (_mayUpload) {
      _pick();
    } else {
      _msg('ຂັ້ນນີ້ອັບໂຫຼດບໍ່ໄດ້');
    }
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
        final add = <_WdFile>[];
        for (final f in files) {
          add.add(_WdFile(f.name, await f.readAsBytes()));
        }
        if (mounted) setState(() => _pending.addAll(add));
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
        if (!RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false)
            .hasMatch(name)) {
          name = '$name.jpg';
        }
        if (mounted) setState(() => _pending.add(_WdFile(name, bytes)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'ເປີດກ້ອງ/ໄຟລ໌ບໍ່ໄດ້: $e');
    }
  }

  Future<void> _upload() async {
    if (_pending.isEmpty) {
      setState(() => _error = 'ກະລຸນາເລືອກເອກະສານກ່ອນ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final req =
          http.MultipartRequest('POST', Uri.parse('$base/withdrawals/$_id/docs'));
      if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
      req.fields['stage'] = '$_stage';
      if (_stage >= 4 && _stage <= 6) {
        req.fields['hasProblem'] = _problem ? '1' : '0';
        req.fields['note'] = _noteC.text.trim();
      }
      for (final f in _pending) {
        req.files.add(http.MultipartFile.fromBytes('files', f.bytes,
            filename: f.name, contentType: MediaType.parse(_wdMime(f.name))));
      }
      debugPrint('[WD] upload docs withdrawal=$_id files=${_pending.length}');
      final res = await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 120)));
      if (res.statusCode >= 300) {
        var m = res.body;
        try {
          final j = jsonDecode(res.body);
          if (j is Map && j['message'] != null) m = '${j['message']}';
        } catch (_) {}
        throw Exception(m);
      }
      if (!mounted) return;
      setState(() => _pending.clear());
      await _load();
      widget.onChanged?.call();
      _noteC.clear();
      if (mounted) setState(() => _problem = false);
      _msg('ອັບໂຫຼດແລ້ວ');
    } catch (e) {
      debugPrint('[WD] upload failed: $e');
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> d) async {
    final url = productImageUrl('${d['url'] ?? ''}');
    final mime = '${d['mime'] ?? ''}';
    if (mime.startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24), child: Text('ເປີດຮູບບໍ່ໄດ້'))),
          ),
        ),
      );
    } else {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) _msg('ເປີດໄຟລ໌ບໍ່ໄດ້');
    }
  }

  List<Widget> _groups() {
    final mut = Theme.of(context).hintColor;
    final primary = Theme.of(context).colorScheme.primary;
    final by = <int, List<Map<String, dynamic>>>{};
    for (final d in _docs) {
      final s = int.tryParse('${d['stage'] ?? ''}') ?? 2;
      by.putIfAbsent(s, () => <Map<String, dynamic>>[]).add(d);
    }
    final out = <Widget>[];
    for (var s = 2; s <= 7; s++) {
      final list = by[s] ?? const <Map<String, dynamic>>[];
      final cur = s == _stage;
      final color = cur ? primary : mut;
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Row(children: [
          Icon(
              list.isNotEmpty
                  ? Icons.check_circle
                  : (cur
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
              size: 18,
              color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(wdStageLabel(s),
                  style: TextStyle(
                      fontWeight: cur ? FontWeight.w700 : FontWeight.w500,
                      color: color))),
          Text('${list.length}', style: TextStyle(color: mut)),
        ]),
      ));
      if (list.isEmpty) {
        out.add(Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 2),
            child: Text(s > _stage ? 'ຍັງບໍ່ເຖິງຂັ້ນນີ້' : 'ບໍ່ມີເອກະສານ',
                style: TextStyle(color: mut, fontSize: 12))));
      }
      for (final d in list) {
        out.add(ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 24),
          leading: _leading(d),
          title: Text('${d['name'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${d['by'] ?? ''} · ${_wdWhen(d['at'])}'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _open(d),
        ));
      }
    }
    return out;
  }

  Widget _leading(Map<String, dynamic> d) {
    final mime = '${d['mime'] ?? ''}';
    if (mime.startsWith('image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(productImageUrl('${d['url'] ?? ''}'),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined)),
      );
    }
    return const Icon(Icons.description_outlined, size: 32);
  }

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    final color = wdDocStatusColor(_docStatus);
    final note = '${widget.w['checkNote'] ?? ''}';
    final by = '${widget.w['checkedBy'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
                child: Text('ເອກະສານ',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Chip(
              label: Text(wdDocStatusLabel(_docStatus)),
              backgroundColor: color.withValues(alpha: 0.15),
              side: BorderSide(color: color),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          if ((_docStatus == 'checked' || _docStatus == 'rejected') &&
              (by.isNotEmpty || note.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  [if (by.isNotEmpty) 'ຜູ້ກວດ: $by', if (note.isNotEmpty) 'ໝາຍເຫດ: $note']
                      .join('  ·  '),
                  style: TextStyle(color: mut)),
            ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()))
          else if (_docs.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('ຍັງບໍ່ມີເອກະສານ', style: TextStyle(color: mut)))
          else
            ..._groups(),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  _mayUpload
                      ? wdStageLabel(_stage)
                      : (_status == 'closed'
                          ? 'ປິດເຄດແລ້ວ ບໍ່ສາມາດອັບເພີ່ມ'
                          : 'ຂັ້ນ $_stage · ຂັ້ນນີ້ບໍ່ແມ່ນສິດຂອງທ່ານ'),
                  style: TextStyle(color: mut))),
          if (_mayUpload) ...[
            const SizedBox(height: 8),
            if (_stage >= 4 && _stage <= 6) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('ມີບັນຫາ'),
                value: _problem,
                onChanged: _busy ? null : (v) => setState(() => _problem = v),
              ),
              TextField(
                controller: _noteC,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ໝາຍເຫດ (ບັນຫາທີ່ພົບ)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
            ],
            if (_pending.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < _pending.length; i++)
                  InputChip(
                    avatar: const Icon(Icons.attach_file, size: 16),
                    label: Text(_pending[i].name),
                    onDeleted:
                        _busy ? null : () => setState(() => _pending.removeAt(i)),
                  ),
              ]),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.add),
                  label: const Text('ເລືອກເອກະສານ'),
                ),
              ),
              if (_pending.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _upload,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('ອັບໂຫຼດ'),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Head Office: list of withdrawals with documents
// ---------------------------------------------------------------------------
class WithdrawDocCheckPage extends StatefulWidget {
  const WithdrawDocCheckPage({super.key});
  @override
  State<WithdrawDocCheckPage> createState() => _WithdrawDocCheckPageState();
}

class _WithdrawDocCheckPageState extends State<WithdrawDocCheckPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  bool _all = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get('/withdrawals');
    final out = <Map<String, dynamic>>[];
    if (d is List) {
      for (final w in d) {
        if (w is Map) out.add(Map<String, dynamic>.from(w));
      }
    }
    return out;
  }

  void _reload() => setState(() {
        _f = _load();
      });

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: const Text('ກວດເອກະສານເບີກ')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            ChoiceChip(
                label: const Text('ລໍຖ້າກວດ'),
                selected: !_all,
                onSelected: (_) => setState(() => _all = false)),
            const SizedBox(width: 8),
            ChoiceChip(
                label: const Text('ມີເອກະສານທັງໝົດ'),
                selected: _all,
                onSelected: (_) => setState(() => _all = true)),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
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
                final rows = (snap.data ?? [])
                    .where((w) {
                      final st = '${w['docStatus'] ?? ''}';
                      return _all ? st.isNotEmpty : st == 'submitted';
                    })
                    .toList();
                if (rows.isEmpty) {
                  return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      children: [
                        Center(
                            child: Text(
                                _all
                                    ? 'ຍັງບໍ່ມີລາຍການທີ່ມີເອກະສານ'
                                    : 'ບໍ່ມີລາຍການລໍຖ້າກວດ',
                                style: TextStyle(color: mut))),
                      ]);
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final w = rows[i];
                    final st = '${w['docStatus'] ?? ''}';
                    return ListTile(
                      leading: Icon(Icons.fact_check_outlined,
                          color: wdDocStatusColor(st)),
                      title: Text(
                          '${w['withdrawNo'] ?? w['id']} · ${w['branchName'] ?? ''}'),
                      subtitle: Text(
                          '${w['barcode'] ?? ''} ${w['atmId'] ?? ''} · ${wdDocStatusLabel(st)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final r = await Navigator.push<dynamic>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => WithdrawDocCheckDetail(w)));
                        if (r == true && mounted) _reload();
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class WithdrawDocCheckDetail extends StatefulWidget {
  final Map<String, dynamic> w;
  const WithdrawDocCheckDetail(this.w, {super.key});
  @override
  State<WithdrawDocCheckDetail> createState() => _WithdrawDocCheckDetailState();
}

class _WithdrawDocCheckDetailState extends State<WithdrawDocCheckDetail> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _check(String result) async {
    final note = _note.text.trim();
    if (result == 'rejected' && note.isEmpty) {
      setState(() => _error = 'ກະລຸນາໃສ່ໝາຍເຫດເຫດຜົນທີ່ບໍ່ຜ່ານ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      debugPrint('[WD] check withdrawal=${widget.w['id']} result=$result');
      await Api.post('/withdrawals/${widget.w['id']}/check', {
        'result': result,
        if (note.isNotEmpty) 'note': note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result == 'checked' ? 'ບັນທຶກ: ຜ່ານ' : 'ບັນທຶກ: ບໍ່ຜ່ານ')));
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[WD] check failed: $e');
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final st = '${w['docStatus'] ?? ''}';
    final mut = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text('ກວດເອກະສານ · ${w['withdrawNo'] ?? w['id']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _kv('ເລກທີ່', '${w['withdrawNo'] ?? ''}'),
              _kv('ສາຂາ', '${w['branchName'] ?? ''}'),
              _kv('Terminal', '${w['barcode'] ?? ''}'),
              _kv('ຕູ້ ATM', '${w['atmId'] ?? ''}'),
              _kv('ຜູ້ບັນທຶກ', '${w['createdBy'] ?? ''}'),
              _kv('ວັນທີ', _wdWhen(w['createdAt'])),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              WithdrawBillPage(Map<String, dynamic>.from(w)))),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('ເບິ່ງໃບເບີກ'),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        WithdrawDocsSection(w, canUpload: false),
        const SizedBox(height: 8),
        if (st == 'submitted' && Api.can('WD_S3')) ...[
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'ໝາຍເຫດ (ຕ້ອງໃສ່ຖ້າບໍ່ຜ່ານ)',
                border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _check('rejected'),
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text('ບໍ່ຜ່ານ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _check('checked'),
                icon: const Icon(Icons.check),
                label: const Text('ຜ່ານ'),
              ),
            ),
          ]),
        ] else if (st == 'submitted')
          Text('ສະເພາະ Head Office ກວດໄດ້', style: TextStyle(color: mut)),
      ]),
    );
  }
}


// ---------------------------------------------------------------------------
// Documents page of one withdrawal (opened from the bill page bottom bar)
// ---------------------------------------------------------------------------
class WithdrawDocsPage extends StatefulWidget {
  final Map<String, dynamic> w;
  const WithdrawDocsPage(this.w, {super.key});
  @override
  State<WithdrawDocsPage> createState() => _WithdrawDocsPageState();
}

class _WithdrawDocsPageState extends State<WithdrawDocsPage> {
  late Map<String, dynamic> _w = Map<String, dynamic>.from(widget.w);
  final GlobalKey<WithdrawDocsSectionState> _key =
      GlobalKey<WithdrawDocsSectionState>();
  bool _closing = false;

  Future<void> _closeCase() async {
    final items = (_w['items'] is List ? _w['items'] as List : const [])
        .whereType<Map>()
        .toList();
    var problems = <Map>[];
    try {
      final n = await Api.get('/withdrawals/${_w['id']}/notes');
      if (n is List) {
        problems = [
          for (final x in n)
            if (x is Map && x['problem'] == true) x
        ];
      }
    } catch (e) {
      debugPrint('[WD] notes load failed: $e');
    }
    if (mounted == false) return;
    final used = {
      for (final i in items)
        '${i['id']}': TextEditingController(text: '${i['qtyUsed'] ?? 0}')
    };
    final back = {
      for (final i in items)
        '${i['id']}': TextEditingController(text: '${i['qtyReturned'] ?? 0}')
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('ປິດເຄດ ${_w['withdrawNo'] ?? _w['id']}'),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (problems.isNotEmpty) ...[
                  const Text('ສາຂາລາຍງານບັນຫາ:',
                      style: TextStyle(
                          color: Colors.orange, fontWeight: FontWeight.w700)),
                  for (final p in problems)
                    Text('ຂັ້ນ ${p['stage']}: ${p['note'] ?? ''}'),
                  const SizedBox(height: 12),
                ],
                for (final i in items) ...[
                  Text('${i['productName']} (ເບີກ ${i['qty']})'),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: used['${i['id']}'],
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'ໃຊ້ແລ້ວ'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: back['${i['id']}'],
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'ຄືນ'))),
                  ]),
                  const SizedBox(height: 12),
                ],
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ປິດເຄດ')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _closing = true);
    try {
      await Api.post('/withdrawals/${_w['id']}/return', {
        'items': [
          for (final i in items)
            {
              'id': i['id'],
              'qtyUsed': int.tryParse(used['${i['id']}']?.text ?? '') ?? 0,
              'qtyReturned': int.tryParse(back['${i['id']}']?.text ?? '') ?? 0,
            }
        ],
      });
      await _reloadW();
      await _key.currentState?.reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ປິດເຄດແລ້ວ')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _reloadW() async {
    try {
      final list = await Api.get('/withdrawals');
      if (list is List) {
        for (final x in list) {
          if (x is Map && '${x['id']}' == '${_w['id']}') {
            if (mounted) setState(() => _w = Map<String, dynamic>.from(x));
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[WD] docs page reload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ເອກະສານ - ${_w['withdrawNo'] ?? _w['id']}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: WithdrawDocsSection(_w, key: _key, onChanged: _reloadW),
      ),
      bottomNavigationBar: PlanNav(
        items: [
          PlanNavItem(Icons.upload_file, 'ເພີ່ມໄຟລ໌',
              () => _key.currentState?.pickFiles()),
          PlanNavItem(Icons.refresh, 'ໂຫຼດໃໝ່', () async {
            await _reloadW();
            await _key.currentState?.reload();
          }),
          if (Api.can('WD_S7') &&
              '${_w['status']}' == 'open' &&
              (int.tryParse('${_w['stage'] ?? ''}') ?? 0) == 7)
            PlanNavItem(Icons.task_alt, 'ປິດເຄດ',
                _closing ? null : _closeCase, loading: _closing),
        ],
      ),
    );
  }
}
