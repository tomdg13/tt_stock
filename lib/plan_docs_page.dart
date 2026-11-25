import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'plan_bar.dart';
import 'purchase_orders.dart' show kPoDocExt;
import 'plan_docs_upload.dart';
import 'widgets.dart';

class PlanDocsPage extends StatefulWidget {
  final String planId;
  final String planName;
  const PlanDocsPage({super.key, required this.planId, required this.planName});
  @override
  State<PlanDocsPage> createState() => _PlanDocsPageState();
}

class _PlanDocsPageState extends State<PlanDocsPage> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _busy = false;
  bool _dragging = false;
  String? _error;

  bool get _dropSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load({bool silent = false}) async {
    if (silent == false) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await Api.get('/stock/buy-plans/${widget.planId}/docs');
      if (mounted) {
        setState(() {
          _docs = asList(d);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  bool _allowed(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return false;
    final ext = name.substring(i + 1).toLowerCase();
    return kPoDocExt.contains(ext);
  }

  Future<void> _pick() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kPoDocExt,
    );
    if (files.isEmpty || mounted == false) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uploadPlanDocuments(widget.planId, List<PlatformFile>.from(files));
      await _load(silent: true);
      if (mounted) _snack('ອັບໂຫຼດແລ້ວ');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dropped(List<MapEntry<String, List<int>>> ok, int skipped) async {
    if (_busy) return;
    if (ok.isEmpty) {
      if (mounted) setState(() => _error = 'ປະເພດໄຟລ໌ນີ້ບໍ່ຮອງຮັບ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uploadPlanDocumentBytes(widget.planId, ok);
      await _load(silent: true);
      if (mounted) {
        _snack(skipped > 0
            ? 'ອັບໂຫຼດແລ້ວ (ຂ້າມ $skipped ໄຟລ໌ທີ່ບໍ່ຮອງຮັບ)'
            : 'ອັບໂຫຼດແລ້ວ');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Uri? _urlOf(Map<String, dynamic> d) {
    final v = pick(d, ['url']);
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return Uri.tryParse(v);
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.tryParse(v.startsWith('/') ? '$base$v' : '$base/$v');
  }

  Future<void> _open(Map<String, dynamic> d) async {
    final u = _urlOf(d);
    var ok = false;
    if (u != null) {
      try {
        ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (ok == false && mounted) _snack('ເປີດໄຟລ໌ບໍ່ໄດ້');
  }

  Future<void> _delete(Map<String, dynamic> d) async {
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
          '/stock/buy-plans/${widget.planId}/docs/${pick(d, ['id'])}');
      if (mounted) {
        setState(() => _docs.removeWhere((x) => '${x['id']}' == '${d['id']}'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  IconData _icon(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (l.endsWith('.xls') || l.endsWith('.xlsx')) return Icons.table_chart;
    if (l.endsWith('.doc') || l.endsWith('.docx')) return Icons.description;
    return Icons.image;
  }

  Color _color(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.pdf')) return const Color(0xFFD93025);
    if (l.endsWith('.xls') || l.endsWith('.xlsx')) {
      return const Color(0xFF0F9D58);
    }
    if (l.endsWith('.doc') || l.endsWith('.docx')) {
      return const Color(0xFF4285F4);
    }
    return const Color(0xFF9334E6);
  }

  String _size(dynamic v) {
    final b = num.tryParse('$v');
    if (b == null) return '';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  String _day(dynamic v) {
    final s = '${v ?? ''}';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Widget _row(Map<String, dynamic> d) {
    final name = pick(d, ['name']);
    final sub = [_size(d['size']), _day(d['createdAt'])]
        .where((e) => e.isNotEmpty)
        .join(' • ');
    return ListTile(
      leading: Icon(_icon(name), color: _color(name), size: 32),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty ? null : Text(sub),
      onTap: () => _open(d),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(d),
      ),
    );
  }

  Widget _dropHint() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primary.withAlpha(40),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_upload_outlined, size: 56, color: cs.primary),
          const SizedBox(height: 8),
          Text('ວາງໄຟລ໌ທີ່ນີ້ເພື່ອອັບໂຫຼດ',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ]),
      ),
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error case final String e)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(e)),
            ]),
          ),
        if (_docs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(children: [
              const Icon(Icons.folder_open_outlined, size: 56),
              const SizedBox(height: 12),
              const Text('ຍັງບໍ່ມີເອກະສານ'),
              if (_dropSupported) ...[
                const SizedBox(height: 4),
                const Text('ລາກໄຟລ໌ມາວາງທີ່ນີ້ໄດ້'),
              ],
            ]),
          )
        else
          for (final d in _docs) _row(d),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _content(),
    );
    final Widget main = _dropSupported
        ? DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) async {
              if (mounted) setState(() => _dragging = false);
              final ok = <MapEntry<String, List<int>>>[];
              var skipped = 0;
              for (final x in detail.files) {
                if (_allowed(x.name)) {
                  ok.add(MapEntry(x.name, await x.readAsBytes()));
                } else {
                  skipped++;
                }
              }
              await _dropped(ok, skipped);
            },
            child: Stack(fit: StackFit.expand, children: [
              body,
              if (_dragging) Positioned.fill(child: IgnorePointer(child: _dropHint())),
            ]),
          )
        : body;
    return Scaffold(
      appBar: AppBar(title: Text('ເອກະສານ - ${widget.planName}')),
      body: main,
      bottomNavigationBar: PlanNav(
        summary: '${_docs.length} ໄຟລ໌',
        items: [
          PlanNavItem(Icons.upload_file, 'ອັບໂຫຼດ', _busy ? null : _pick,
              loading: _busy),
          PlanNavItem(Icons.refresh, 'ໂຫຼດໃໝ່',
              _busy ? null : () => _load(silent: true)),
        ],
      ),
    );
  }
}
