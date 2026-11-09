import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'product_images.dart';

const List<String> _ext = [
  'pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'xls', 'xlsx'
];

MediaType _mt(String n) {
  final e = n.toLowerCase().split('.').last;
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
  return MediaType.parse(m[e] ?? 'application/octet-stream');
}

IconData _icon(String n) {
  final e = n.toLowerCase().split('.').last;
  if (e == 'pdf') return Icons.picture_as_pdf_outlined;
  if (e == 'xls' || e == 'xlsx') return Icons.table_view_outlined;
  if (e == 'doc' || e == 'docx') return Icons.description_outlined;
  return Icons.image_outlined;
}

String _size(num b) {
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}

String _dt(Object? v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

List<dynamic> _asL(dynamic d) {
  if (d is List) return d;
  if (d is Map && d['data'] is List) return d['data'] as List;
  return <dynamic>[];
}

String _msg(http.Response res) {
  var msg = 'Error ${res.statusCode}';
  try {
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    if (d is Map && d['message'] != null) {
      msg = d['message'] is List
          ? (d['message'] as List).join('\n')
          : '${d['message']}';
    }
  } catch (_) {}
  return msg;
}

class ReportDocsPage extends StatefulWidget {
  final int branchId;
  final String branchName;
  final String from;
  final String to;
  const ReportDocsPage({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.from,
    required this.to,
  });
  @override
  State<ReportDocsPage> createState() => _ReportDocsPageState();
}

class _ReportDocsPageState extends State<ReportDocsPage> {
  List<dynamic> _docs = <dynamic>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _qs() =>
      'branchId=${widget.branchId}&from=${widget.from}&to=${widget.to}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      debugPrint('[DOCS] load ${_qs()}');
      final d = await Api.get('/report-docs?${_qs()}');
      if (mounted == false) return;
      debugPrint('[DOCS] loaded ${_asL(d).length}');
      setState(() {
        _docs = _asL(d);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[DOCS] load failed: $e');
      if (mounted == false) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _AddDocSheet(
          branchId: widget.branchId, from: widget.from, to: widget.to),
    );
    if (done == true) _load();
  }

  Future<void> _open(Map m) async {
    try {
      await launchUrl(Uri.parse(productImageUrl('${m['url']}')),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[DOCS] open failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ເປີດບໍ່ໄດ້: $e')));
      }
    }
  }

  Future<void> _delete(Map m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບເອກະສານ?'),
        content: Text('${m['topic'] ?? ''}\n${m['name'] ?? ''}'),
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
      await Api.delete('/report-docs/${m['id']}');
      debugPrint('[DOCS] deleted ${m['id']}');
      _load();
    } catch (e) {
      debugPrint('[DOCS] delete failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ລຶບບໍ່ສຳເລັດ: $e')));
      }
    }
  }

  Widget _tile(Map m) {
    final cs = Theme.of(context).colorScheme;
    final nm = '${m['name'] ?? ''}';
    final sz = num.tryParse('${m['size']}') ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(_icon(nm), color: cs.onPrimaryContainer)),
        title: Text('${m['topic'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '$nm\n${_size(sz)} · ${m['createdByName'] ?? '-'} · ${_dt(m['createdAt'])}'),
        isThreeLine: true,
        onTap: () => _open(m),
        trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(m)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ເອກະສານແນບ')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('ເພີ່ມເອກະສານ')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('${widget.branchName} · ${widget.from} - ${widget.to}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 4),
              Text('${_docs.length} ເອກະສານ',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator())),
              if (_loading == false && _error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error, style: TextStyle(color: cs.error))),
              if (_loading == false && _error.isEmpty && _docs.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: Text('ຍັງບໍ່ມີເອກະສານ',
                            style: TextStyle(color: cs.onSurfaceVariant)))),
              for (final d in _docs) _tile(d as Map),
            ]),
      ),
    );
  }
}

class _PickedDoc {
  final String name;
  final List<int> bytes;
  const _PickedDoc(this.name, this.bytes);
}

class _AddDocSheet extends StatefulWidget {
  final int branchId;
  final String from;
  final String to;
  const _AddDocSheet(
      {required this.branchId, required this.from, required this.to});
  @override
  State<_AddDocSheet> createState() => _AddDocSheetState();
}

class _AddDocSheetState extends State<_AddDocSheet> {
  final TextEditingController _topic = TextEditingController();
  final List<_PickedDoc> _files = <_PickedDoc>[];
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: _ext);
      if (picked.isEmpty) {
        debugPrint('[DOCS] picker cancelled');
        return;
      }
      final add = <_PickedDoc>[];
      for (final f in picked) {
        add.add(_PickedDoc(f.name, await f.readAsBytes()));
      }
      debugPrint('[DOCS] picked ${add.length} files');
      if (mounted) setState(() => _files.addAll(add));
    } catch (e) {
      debugPrint('[DOCS] pick failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      setState(() => _error = 'ໃສ່ຫົວຂໍ້');
      return;
    }
    if (_files.isEmpty) {
      setState(() => _error = 'ເລືອກໄຟລ໌ກ່ອນ');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
      for (var i = 0; i < _files.length; i += 10) {
        final req =
            http.MultipartRequest('POST', Uri.parse('$base/report-docs'));
        final tk = Api.token;
        if (tk != null) req.headers['Authorization'] = 'Bearer $tk';
        req.fields['topic'] = topic;
        req.fields['branchId'] = '${widget.branchId}';
        req.fields['from'] = widget.from;
        req.fields['to'] = widget.to;
        for (final f in _files.skip(i).take(10)) {
          req.files.add(http.MultipartFile.fromBytes('files', f.bytes,
              filename: f.name, contentType: _mt(f.name)));
        }
        debugPrint(
            '[DOCS] upload batch ${i ~/ 10 + 1} files=${req.files.length} topic=$topic');
        final res = await http.Response.fromStream(
            await req.send().timeout(const Duration(seconds: 120)));
        debugPrint(
            '[DOCS] status=${res.statusCode} body=${utf8.decode(res.bodyBytes, allowMalformed: true)}');
        if (res.statusCode >= 400) throw Exception(_msg(res));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[DOCS] upload failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ເພີ່ມເອກະສານ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                  controller: _topic,
                  decoration: const InputDecoration(labelText: 'ຫົວຂໍ້ (Topic)')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('ເລືອກໄຟລ໌')),
              for (var i = 0; i < _files.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icon(_files[i].name)),
                  title: Text(_files[i].name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(_files[i].bytes.length)),
                  trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed:
                          _busy ? null : () => setState(() => _files.removeAt(i))),
                ),
              if (_error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error, style: TextStyle(color: cs.error))),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? 'ກຳລັງອັບໂຫຼດ...' : 'ບັນທຶກ'),
              ),
            ]),
      ),
    );
  }
}
