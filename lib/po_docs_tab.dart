import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'purchase_orders.dart'
    show uploadPoDocuments, uploadPoDocumentBytes, kPoDocExt;
import 'theme.dart';
import 'widgets.dart';

/// "ເອກະສານ" tab of a PO, styled like Google Drive:
/// upload button, list / grid switch, file cards with previews, a "more" menu
/// per file, and a full-page drop overlay (drag & drop on web / desktop).
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

enum _Kind { pdf, image, word, excel, other }

_Kind _kindOf(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return _Kind.pdf;
  if (n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.webp') ||
      n.endsWith('.gif')) {
    return _Kind.image;
  }
  if (n.endsWith('.doc') || n.endsWith('.docx')) return _Kind.word;
  if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) {
    return _Kind.excel;
  }
  return _Kind.other;
}

/// File type colors, like Drive: PDF red, Word blue, Excel green, photos purple.
Color _colorOf(_Kind k, Pal p) => switch (k) {
      _Kind.pdf => const Color(0xFFD93025),
      _Kind.image => const Color(0xFF9334E6),
      _Kind.word => const Color(0xFF4285F4),
      _Kind.excel => const Color(0xFF0F9D58),
      _Kind.other => p.mut,
    };

IconData _iconOfKind(_Kind k) => switch (k) {
      _Kind.pdf => Icons.picture_as_pdf,
      _Kind.image => Icons.image,
      _Kind.word => Icons.description,
      _Kind.excel => Icons.table_chart,
      _Kind.other => Icons.insert_drive_file,
    };

class _PoDocsTabState extends State<PoDocsTab> {
  String _poId = '';
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _busy = false;
  bool _dragging = false;
  bool _grid = true;
  String? _error;

  /// Drag & drop only makes sense with a mouse: web and desktop.
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

  Uri? _urlOf(Map<String, dynamic> d) {
    final v = pick(d, ['url', 'filePath', 'path', 'file']);
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return Uri.tryParse(v);
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.tryParse(
        v.startsWith('/') ? '$base$v' : '$base/uploads/purchase-orders/$v');
  }

  /// Same file types as the PO form's file chooser.
  bool _allowed(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return false;
    final ext = name.substring(i + 1).toLowerCase();
    return kPoDocExt.any((e) => e.toLowerCase().replaceFirst('.', '') == ext);
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

  /// Upload files that were dropped on the tab (name + bytes).
  Future<void> _uploadDropped(
      List<MapEntry<String, List<int>>> ok, int skipped) async {
    if (_poId.isEmpty || _busy) return;
    if (ok.isEmpty) {
      if (mounted) setState(() => _error = 'ປະເພດໄຟລ໌ນີ້ບໍ່ຮອງຮັບ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uploadPoDocumentBytes(_poId, ok);
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
          '/purchase-orders/${Uri.encodeComponent(_poId)}/documents/${pick(d, [
            'id'
          ])}');
      if (mounted) {
        setState(() => _docs.removeWhere((x) => '${x['id']}' == '${d['id']}'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // ------------------------------------------------------------------- parts
  Widget _toolbar(Pal p, bool canWrite) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(children: [
      if (canWrite)
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.add),
          label: const Text('ອັບໂຫຼດ'),
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      const SizedBox(width: 12),
      Text('${_docs.length} ໄຟລ໌', style: TextStyle(color: p.mut)),
      const Spacer(),
      _viewToggle(primary, p),
    ]);
  }

  Widget _viewToggle(Color primary, Pal p) {
    Widget seg(IconData icon, bool grid, String tip) {
      final sel = _grid == grid;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => setState(() => _grid = grid),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? primary.withAlpha(40) : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 20, color: sel ? primary : p.mut),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: p.bd),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(Icons.view_list_outlined, false, 'ລາຍການ'),
        seg(Icons.grid_view_outlined, true, 'ຕາຕະລາງ'),
      ]),
    );
  }

  /// The "⋮" menu of a file.
  Widget _menu(Map<String, dynamic> d, bool canWrite, Pal p) {
    return PopupMenuButton<String>(
      tooltip: 'ເພີ່ມເຕີມ',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        if (v == 'open') _open(d);
        if (v == 'delete') _delete(d);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.open_in_new),
            title: Text('ເປີດ'),
          ),
        ),
        if (canWrite)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: p.bad),
              title: Text('ລຶບ', style: TextStyle(color: p.bad)),
            ),
          ),
      ],
    );
  }

  /// Preview area of a card: the photo itself, or a big colored file icon.
  Widget _preview(Map<String, dynamic> d, _Kind kind, Color color) {
    final icon = Center(child: Icon(_iconOfKind(kind), size: 48, color: color));
    if (kind != _Kind.image) return icon;
    final u = _urlOf(d);
    if (u == null) return icon;
    return Image.network(
      u.toString(),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => icon,
    );
  }

  Widget _card(Map<String, dynamic> d, bool canWrite, Pal p) {
    final name = _nameOf(d);
    final kind = _kindOf(name);
    final color = _colorOf(kind, p);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: p.bd),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _open(d),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(children: [
                Icon(_iconOfKind(kind), size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                _menu(d, canWrite, p),
              ]),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _preview(d, kind, color),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _gridView(bool canWrite, Pal p) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 210).floor().clamp(2, 6).toInt();
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _docs.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (_, i) => _card(_docs[i], canWrite, p),
      );
    });
  }

  Widget _row(Map<String, dynamic> d, bool canWrite, Pal p) {
    final name = _nameOf(d);
    final size = _sizeOf(d);
    final kind = _kindOf(name);
    final color = _colorOf(kind, p);
    return InkWell(
      onTap: () => _open(d),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_iconOfKind(kind), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (size.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(size, style: TextStyle(color: p.mut, fontSize: 12.5)),
            ),
          _menu(d, canWrite, p),
        ]),
      ),
    );
  }

  Widget _listView(bool canWrite, Pal p) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: p.bd),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: [
          for (var i = 0; i < _docs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.bd),
            _row(_docs[i], canWrite, p),
          ],
        ]),
      ),
    );
  }

  Widget _empty(Pal p, bool canWrite) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(children: [
        Icon(Icons.cloud_upload_outlined, size: 64, color: p.mut),
        const SizedBox(height: 12),
        Text('ຍັງບໍ່ມີເອກະສານ', style: TextStyle(color: p.mut, fontSize: 16)),
        if (canWrite)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _dropSupported
                  ? 'ລາກໄຟລ໌ມາວາງບ່ອນນີ້ ຫຼື ກົດປຸ່ມອັບໂຫຼດ'
                  : 'ກົດປຸ່ມອັບໂຫຼດ',
              style: TextStyle(color: p.mut, fontSize: 13),
            ),
          ),
      ]),
    );
  }

  /// Shown over the whole tab while a file is dragged over it.
  Widget _dropOverlay() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: primary.withAlpha(36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary, width: 2),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_upload_outlined, size: 56, color: primary),
          const SizedBox(height: 8),
          Text('ປ່ອຍໄຟລ໌ເພື່ອອັບໂຫຼດ',
              style: TextStyle(
                  color: primary, fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_poId.isEmpty) {
      return ErrorView(_error ?? 'ບໍ່ພົບ PO', () => _load());
    }
    final canWrite = Api.can('RECEIVE');
    final body = RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _toolbar(p, canWrite),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.bad.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: p.bad),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: p.bad))),
              ]),
            ),
          const SizedBox(height: 16),
          if (_docs.isEmpty)
            _empty(p, canWrite)
          else if (_grid)
            _gridView(canWrite, p)
          else
            _listView(canWrite, p),
        ],
      ),
    );
    if (!canWrite || !_dropSupported) return body;
    return DropTarget(
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
        await _uploadDropped(ok, skipped);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (_dragging)
            Positioned.fill(child: IgnorePointer(child: _dropOverlay())),
        ],
      ),
    );
  }
}
