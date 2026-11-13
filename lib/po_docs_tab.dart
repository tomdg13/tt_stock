import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'purchase_orders.dart' show uploadPoDocuments, kPoDocExt;
import 'theme.dart';
import 'widgets.dart';

/// "ເອກະສານ" tab of a PO: upload files, and see / open / delete the attached ones.
/// Uses the existing endpoints (no server change needed):
///   GET    /purchase-orders/:id                      -> { ..., documents: [...] }
///   POST   /purchase-orders/:id/documents            (multipart field "files")
///   DELETE /purchase-orders/:id/documents/:docId
class PoDocsTab extends StatefulWidget {
  final String poNo;
  const PoDocsTab({super.key, required this.poNo});

  @override
  State<PoDocsTab> createState() => _PoDocsTabState();
}

class _PoDocsTabState extends State<PoDocsTab> {
  String _poId = '';
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (_poId.isEmpty) {
        if (widget.poNo.isEmpty) throw 'ບໍ່ມີເລກ PO';
        final list = asList(await Api.get(
            '/purchase-orders?q=${Uri.encodeQueryComponent(widget.poNo)}'));
        final head = list.firstWhere((m) => pick(m, ['poNo']) == widget.poNo,
            orElse: () => <String, dynamic>{});
        if (head.isEmpty) throw 'ບໍ່ພົບ PO ${widget.poNo}';
        _poId = pick(head, ['id', 'poId', '_id']);
        if (_poId.isEmpty) throw 'ບໍ່ພົບ ID ຂອງ PO';
      }
      final d = await Api.get('/purchase-orders/${Uri.encodeComponent(_poId)}');
      var m = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
      if (m['data'] is Map) m = Map<String, dynamic>.from(m['data'] as Map);
      final docs = m['documents'] is List
          ? asList(m['documents'])
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------------------------------------------------------------- helpers
  String _nameOf(Map<String, dynamic> d) {
    final n =
        pick(d, ['name', 'origName', 'originalName', 'fileName', 'filename']);
    if (n.isNotEmpty) return n;
    return pick(d, ['url', 'filePath', 'path', 'file']).split('/').last;
  }

  String _sizeOf(Map<String, dynamic> d) {
    final b = num.tryParse(pick(d, ['size', 'sizeBytes']));
    if (b == null) return '';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  IconData _iconOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    if (n.endsWith('.doc') || n.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.attach_file;
  }

  Uri? _urlOf(Map<String, dynamic> d) {
    final v = pick(d, ['url', 'filePath', 'path', 'file']);
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return Uri.tryParse(v);
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.tryParse(
        v.startsWith('/') ? '$base$v' : '$base/uploads/purchase-orders/$v');
  }

  // ---------------------------------------------------------------- actions
  Future<void> _upload() async {
    if (_poId.isEmpty || _busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kPoDocExt,
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uploadPoDocuments(_poId, List<PlatformFile>.from(files));
      await _load(silent: true);
      if (mounted) _snack('ອັບໂຫຼດແລ້ວ');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> d) async {
    final u = _urlOf(d);
    var ok = false;
    if (u != null) {
      try {
        ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) _snack('ເປີດໄຟລ໌ບໍ່ໄດ້');
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບເອກະສານ?'),
        content: Text(_nameOf(d)),
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
          '/purchase-orders/${Uri.encodeComponent(_poId)}/documents/${pick(d, ['id'])}');
      if (mounted) {
        setState(() => _docs.removeWhere((x) => '${x['id']}' == '${d['id']}'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // ------------------------------------------------------------------- build
  Widget _tile(Map<String, dynamic> d, bool canWrite, Pal p) {
    final name = _nameOf(d);
    final size = _sizeOf(d);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconOf(name), color: p.mut),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: size.isEmpty
          ? null
          : Text(size, style: TextStyle(color: p.mut, fontSize: 12)),
      onTap: () => _open(d),
      trailing: canWrite
          ? IconButton(
              tooltip: 'ລຶບ',
              icon: Icon(Icons.delete_outline, color: p.bad),
              onPressed: () => _delete(d),
            )
          : const Icon(Icons.open_in_new, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_poId.isEmpty) {
      return ErrorView(_error ?? 'ບໍ່ພົບ PO', () => _load());
    }
    final canWrite = Api.can('RECEIVE');
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (canWrite)
            FilledButton.icon(
              onPressed: _busy ? null : _upload,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_busy ? 'ກຳລັງອັບໂຫຼດ…' : 'ອັບໂຫຼດເອກະສານ'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: p.bad)),
            ),
          const SizedBox(height: 12),
          AppCard(
            title: 'ເອກະສານ (${_docs.length})',
            child: _docs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('ຍັງບໍ່ມີເອກະສານ',
                        style: TextStyle(color: p.mut)),
                  )
                : Column(children: [
                    for (final d in _docs) _tile(d, canWrite, p),
                  ]),
          ),
        ],
      ),
    );
  }
}
