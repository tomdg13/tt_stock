import 'package:flutter/material.dart';

class PlanNavItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const PlanNavItem(this.icon, this.label, this.onTap, {this.loading = false});
}

class PlanNav extends StatelessWidget {
  final List<PlanNavItem> items;
  final String? summary;
  const PlanNav({super.key, required this.items, this.summary});

  Widget _item(BuildContext context, PlanNavItem it) {
    final cs = Theme.of(context).colorScheme;
    final c = it.onTap == null ? cs.outline : cs.primary;
    return Expanded(
      child: InkWell(
        onTap: it.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            it.loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(it.icon, color: c),
            const SizedBox(height: 2),
            Text(it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = summary;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (s is String)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child:
                  Text(s, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          Row(children: [for (final it in items) _item(context, it)]),
        ]),
      ),
    );
  }
}

class PlanBar extends StatefulWidget {
  final Future<void> Function() onSave;
  final Future<void> Function() onExport;
  final Future<void> Function()? onPdf;
  final VoidCallback? onList;
  final VoidCallback? onAdd;
  final String? summary;
  const PlanBar(
      {super.key,
      required this.onSave,
      required this.onExport,
      this.onPdf,
      this.onList,
      this.onAdd,
      this.summary});
  @override
  State<PlanBar> createState() => _PlanBarState();
}

class _PlanBarState extends State<PlanBar> {
  bool _saving = false;
  bool _exporting = false;
  bool _pdfing = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    var msg = 'ບັນທຶກແລ້ວ';
    try {
      await widget.onSave();
    } catch (e) {
      msg = 'ບັນທຶກບໍ່ສຳເລັດ: $e';
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    String? err;
    try {
      await widget.onExport();
    } catch (e) {
      err = 'ສົ່ງອອກບໍ່ສຳເລັດ: $e';
    }
    if (mounted) {
      setState(() => _exporting = false);
      if (err is String) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  Future<void> _pdf() async {
    final f = widget.onPdf;
    if (f == null) return;
    setState(() => _pdfing = true);
    String? err;
    try {
      await f();
    } catch (e) {
      err = 'ສ້າງ PDF ບໍ່ສຳເລັດ: $e';
    }
    if (mounted) {
      setState(() => _pdfing = false);
      if (err is String) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _exporting || _pdfing;
    final ol = widget.onList;
    final oa = widget.onAdd;
    final op = widget.onPdf;
    return PlanNav(
      summary: widget.summary,
      items: [
        PlanNavItem(Icons.save_outlined, 'ບັນທຶກ', busy ? null : _save,
            loading: _saving),
        if (ol is VoidCallback) PlanNavItem(Icons.checklist, 'ລາຍການ', ol),
        if (oa is VoidCallback) PlanNavItem(Icons.add_task, 'ເລືອກເພີ່ມ', oa),
        if (op is Function)
          PlanNavItem(Icons.picture_as_pdf_outlined, 'PDF', busy ? null : _pdf,
              loading: _pdfing),
        PlanNavItem(Icons.table_view_outlined, 'Excel', busy ? null : _export,
            loading: _exporting),
      ],
    );
  }
}
