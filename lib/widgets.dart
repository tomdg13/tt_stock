import 'package:flutter/material.dart';
import 'api.dart';
import 'product_images.dart';
import 'theme.dart';

/// First non-empty value among [keys], as text.
String pick(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().isNotEmpty && v.toString() != 'null') {
      return v.toString();
    }
  }
  return '';
}

/// Accepts a plain array or {items|data|rows|list: [...]}.
List<Map<String, dynamic>> asList(dynamic d) {
  dynamic l = d;
  if (d is Map) l = d['items'] ?? d['data'] ?? d['rows'] ?? d['list'] ?? [];
  if (l is! List) return [];
  return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

String prettyKey(String k) {
  final s = k.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return s.isEmpty ? k : s[0].toUpperCase() + s.substring(1);
}

double num0(dynamic v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

String fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

Future<List<Map<String, dynamic>>> loadBranches() async =>
    asList(await Api.get('/branches'));

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, this.onRetry, {super.key});

  @override
  Widget build(BuildContext context) {
    final denied =
        error is ApiException && (error as ApiException).status == 403;
    final p = pal(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(denied ? Icons.lock_outline : Icons.error_outline,
              size: 40, color: p.bad),
          const SizedBox(height: 12),
          Text(denied ? 'ທ່ານບໍ່ມີສິດໃຊ້ງານໜ້ານີ້' : '$error',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (!denied)
            OutlinedButton(onPressed: onRetry, child: const Text('ລອງໃໝ່')),
        ]),
      ),
    );
  }
}

/// Renders any JSON value as readable rows (used when field names are unknown).
class DataView extends StatelessWidget {
  final dynamic data;
  const DataView(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d is Map) {
      return Column(children: [
        for (final e in d.entries) _entry(context, e.key.toString(), e.value)
      ]);
    }
    if (d is List) {
      return Column(children: [
        for (var i = 0; i < d.length; i++) _entry(context, '#${i + 1}', d[i])
      ]);
    }
    return Padding(padding: const EdgeInsets.all(12), child: Text('$d'));
  }

  Widget _entry(BuildContext context, String key, dynamic v) {
    final p = pal(context);
    if (v is Map || v is List) {
      final n = v is List ? ' (${v.length})' : '';
      return cardBox(
        context,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text('${prettyKey(key)}$n'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [DataView(v)],
        ),
      );
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(prettyKey(key), style: TextStyle(color: p.mut)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(v == null ? '-' : '$v', textAlign: TextAlign.end),
      ),
    );
  }
}

class DetailPage extends StatefulWidget {
  final String title, path;
  const DetailPage(this.title, this.path, {super.key});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<dynamic> _f = Api.get(widget.path);
  void _reload() => setState(() {
        _f = Api.get(widget.path);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return ErrorView(s.error!, _reload);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
                padding: const EdgeInsets.all(16),
                children: [AppCard(child: DataView(s.data))]),
          );
        },
      ),
    );
  }
}

/// Searchable, pull-to-refresh list of cards that opens a detail page on tap.
class ListPage extends StatefulWidget {
  final String title, path;
  final List<String> titleKeys, subKeys, trailKeys, tagKeys;
  final String? Function(Map<String, dynamic>)? detailPath;
  final bool searchable;
  final String extraQuery;
  final void Function(BuildContext, Map<String, dynamic>)? onTapItem;
  final ValueNotifier<int>? reloadSignal;
  final Widget Function(BuildContext, Map<String, dynamic>)? rowActions;
  final bool Function(Map<String, dynamic>)? rowFilter;

  const ListPage({
    super.key,
    required this.title,
    required this.path,
    required this.titleKeys,
    this.subKeys = const [],
    this.trailKeys = const [],
    this.tagKeys = const [],
    this.detailPath,
    this.searchable = true,
    this.extraQuery = '',
    this.onTapItem,
    this.reloadSignal,
    this.rowActions,
    this.rowFilter,
  });

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _q = TextEditingController();
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() {
    final parts = <String>[
      if (widget.searchable && _q.text.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(_q.text.trim())}',
      if (widget.extraQuery.isNotEmpty) widget.extraQuery,
    ];
    final qs = parts.isEmpty
        ? ''
        : '${widget.path.contains('?') ? '&' : '?'}${parts.join('&')}';
    return Api.get('${widget.path}$qs');
  }

  void _reload() => setState(() {
        _f = _load();
      });

  @override
  void initState() {
    super.initState();
    widget.reloadSignal?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      if (widget.searchable)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'ຄົ້ນຫາ',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _q.clear();
                    _reload();
                  }),
            ),
          ),
        ),
      Expanded(
        child: FutureBuilder(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) return ErrorView(s.error!, _reload);
            final items = asList(s.data)
                .where((m) => widget.rowFilter?.call(m) ?? true)
                .toList();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                          child: Text('ຍັງບໍ່ມີລາຍການ',
                              style: TextStyle(color: p.mut))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _tile(context, items[i]),
                    ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _thumb(BuildContext context, String v) {
    final p = pal(context);
    final ph = Container(
      width: 48,
      height: 48,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: p.mut),
    );
    final url = productImageUrl(v);
    if (url.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> m) {
    final p = pal(context);
    var t = pick(m, widget.titleKeys);
    if (t.isEmpty && m.isNotEmpty) t = '${m.values.first}';
    final sub = widget.subKeys
        .map((k) => pick(m, [k]))
        .where((e) => e.isNotEmpty)
        .join(' · ');
    final trail = pick(m, widget.trailKeys);
    final tag = pick(m, widget.tagKeys);
    final dp = widget.detailPath?.call(m);
    return cardBox(
      context,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: m.containsKey('imageUrl')
            ? _thumb(context, pick(m, ['imageUrl']))
            : m.containsKey('imageFile')
                ? _thumb(
                    context,
                    pick(m, ['imageFile']).isEmpty
                        ? ''
                        : '/uploads/terminal-types/${pick(m, ['imageFile'])}')
                : m.containsKey('typeImage')
                    ? _thumb(
                        context,
                        pick(m, ['typeImage']).isEmpty
                            ? ''
                            : '/uploads/terminal-types/${pick(m, [
                                    'typeImage'
                                  ])}')
                    : null,
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, style: TextStyle(color: p.mut, fontSize: 13)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trail.isNotEmpty || tag.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (trail.isNotEmpty)
                  Text(trail,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                if (tag.isNotEmpty) Tag(tag, kindOf(tag)),
              ],
            ),
          if (widget.rowActions != null) widget.rowActions!(context, m),
        ]),
        onTap: widget.onTapItem != null
            ? () => widget.onTapItem!(context, m)
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => dp != null
                        ? DetailPage(t, dp)
                        : Scaffold(
                            appBar: AppBar(title: Text(t)),
                            body: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [AppCard(child: DataView(m))]),
                          ),
                  ),
                ),
      ),
    );
  }
}
