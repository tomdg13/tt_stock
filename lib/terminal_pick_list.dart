import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
import 'specs.dart';
import 'theme.dart';
import 'type_image.dart';
import 'widgets.dart';

/// Terminal picker list: status on top, full-width text, edit/delete under it.
class TerminalPickList extends StatefulWidget {
  final String extraQuery;
  final bool Function(Map<String, dynamic>) rowFilter;
  final void Function(Map<String, dynamic>) onTap;
  final Future<void> Function(Map<String, dynamic>)? onEdit, onDelete;
  final ValueNotifier<int>? reloadSignal;
  const TerminalPickList({
    super.key,
    required this.extraQuery,
    required this.rowFilter,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.reloadSignal,
  });
  @override
  State<TerminalPickList> createState() => _TerminalPickListState();
}

class _TerminalPickListState extends State<TerminalPickList> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.reloadSignal?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(_load);
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final d = await Api.get('/terminals?${widget.extraQuery}');
      if (!mounted) return;
      setState(() {
        _items = asList(d);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Color _tagColor(String s) {
    final t = s.toLowerCase();
    if (t == 'ready') return Colors.green;
    if (t == 'in use') return Colors.blue;
    return Colors.teal;
  }

  Widget _card(BuildContext context, Map<String, dynamic> m) {
    final p = pal(context);
    final state = pick(m, ['state', 'status']);
    final sub = [
      pick(m, ['typeName']),
      pick(m, ['serial'])
    ].where((e) => e.isNotEmpty).join(' · ');
    final tc = _tagColor(state);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onTap(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            typeThumb(context, pick(m, ['typeImage', 'imageFile']), size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(pick(m, ['barcode']),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      if (state.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: tc.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(state,
                              style: TextStyle(
                                  color: tc,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(width: 4),
                    ]),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub,
                            style: TextStyle(color: p.mut, fontSize: 13)),
                      ),
                    if (widget.onEdit != null || widget.onDelete != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (widget.onEdit != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'ແກ້ໄຂ',
                              onPressed: () => widget.onEdit!(m),
                            ),
                          if (widget.onDelete != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'ລຶບ',
                              onPressed: () => widget.onDelete!(m),
                            ),
                        ]),
                      )
                    else
                      const SizedBox(height: 8),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final rows = _items.where(widget.rowFilter).where((m) {
      if (q.isEmpty) return true;
      return [
        pick(m, ['barcode']),
        pick(m, ['typeName']),
        pick(m, ['serial']),
        pick(m, ['state', 'status'])
      ].join(' ').toLowerCase().contains(q);
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'ຄົ້ນຫາ',
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_q.clear)),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      itemBuilder: (c, i) => _card(c, rows[i]),
                    ),
                  ),
      ),
    ]);
  }
}
