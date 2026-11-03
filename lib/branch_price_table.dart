import 'package:flutter/material.dart';

class BranchPriceRow {
  final String branchId;
  final String branch;
  final String currency;
  final double priceBuy;
  final double priceSale;
  final double total;

  const BranchPriceRow({
    this.branchId = '',
    required this.branch,
    required this.currency,
    required this.priceBuy,
    required this.priceSale,
    required this.total,
  });
}

/// One item line inside a PO (thumbnail, name, price x qty, amount, +qty).
class BranchLineItem {
  final String name;
  final String sub;
  final String amount;
  final String qty;
  final String imageUrl;

  const BranchLineItem({
    required this.name,
    required this.sub,
    required this.amount,
    this.qty = '',
    this.imageUrl = '',
  });
}

/// One PO under a branch.
class BranchPoItem {
  final String id;
  final String po;
  final String sub;
  final String amount;
  final List<BranchLineItem> lines;

  const BranchPoItem({
    this.id = '',
    required this.po,
    required this.sub,
    required this.amount,
    this.lines = const [],
  });
}

class BranchPriceTable extends StatefulWidget {
  final List<BranchPriceRow> rows;
  final List<BranchPoItem> Function(BranchPriceRow row)? children;

  const BranchPriceTable({super.key, required this.rows, this.children});

  @override
  State<BranchPriceTable> createState() => _BranchPriceTableState();
}

class _BranchPriceTableState extends State<BranchPriceTable> {
  final Set<String> _open = {};
  final Set<String> _openPo = {};

  String _key(BranchPriceRow r) => '${r.branchId}|${r.currency}';
  String _fmt(double v) => v.toStringAsFixed(2);

  void _toggle(BranchPriceRow r) {
    final k = _key(r);
    setState(() {
      if (_open.contains(k)) {
        _open.remove(k);
      } else {
        _open.add(k);
      }
    });
  }

  void _togglePo(String k) {
    setState(() {
      if (_openPo.contains(k)) {
        _openPo.remove(k);
      } else {
        _openPo.add(k);
      }
    });
  }

  Widget _thumb(ThemeData theme, String url) {
    final ph = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined,
          size: 20, color: theme.colorScheme.onSurfaceVariant),
    );
    if (url.isEmpty) return ph;
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (c) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(Icons.broken_image_outlined))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = widget.rows;
    final headStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cellStyle = theme.textTheme.bodyMedium;
    final subStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final currencies = rows
        .map((r) => r.currency)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    final multi = currencies.length > 1;

    Widget line(String a, String b, String c, String d,
        {TextStyle? style,
        bool bold = false,
        VoidCallback? onTap,
        bool open = false}) {
      final st = bold ? style?.copyWith(fontWeight: FontWeight.w700) : style;
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(a, style: st)),
            Expanded(
                flex: 2,
                child: Text(b, style: st, textAlign: TextAlign.right)),
            Expanded(
                flex: 2,
                child: Text(c, style: st, textAlign: TextAlign.right)),
            Expanded(
                flex: 2,
                child: Text(d, style: st, textAlign: TextAlign.right)),
            if (onTap != null)
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18)
            else
              const SizedBox(width: 18),
          ],
        ),
      );
      if (onTap == null) return content;
      return InkWell(onTap: onTap, child: content);
    }

    Widget lineItem(BranchLineItem l) => Padding(
          padding: const EdgeInsets.only(left: 36, right: 22, top: 6, bottom: 6),
          child: Row(
            children: [
              _thumb(theme, l.imageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cellStyle),
                    if (l.sub.isNotEmpty) Text(l.sub, style: subStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l.amount,
                      style: cellStyle?.copyWith(fontWeight: FontWeight.w600)),
                  if (l.qty.isNotEmpty) Text(l.qty, style: subStyle),
                ],
              ),
            ],
          ),
        );

    Widget child(BranchPoItem it) {
      final hasLines = it.lines.isNotEmpty;
      final k = '${it.id}|${it.po}';
      final isOpen = _openPo.contains(k);
      final head = Padding(
        padding: const EdgeInsets.only(left: 20, right: 4, top: 6, bottom: 6),
        child: Row(
          children: [
            Icon(Icons.subdirectory_arrow_right,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.po, style: cellStyle),
                  if (it.sub.isNotEmpty) Text(it.sub, style: subStyle),
                ],
              ),
            ),
            Text(it.amount,
                style: cellStyle?.copyWith(fontWeight: FontWeight.w600)),
            if (hasLines)
              Icon(isOpen ? Icons.expand_more : Icons.chevron_right, size: 18)
            else
              const SizedBox(width: 18),
          ],
        ),
      );
      return Column(
        children: [
          hasLines ? InkWell(onTap: () => _togglePo(k), child: head) : head,
          if (hasLines && isOpen)
            for (final l in it.lines) lineItem(l),
        ],
      );
    }

    final groups = currencies.isEmpty ? [''] : currencies;
    final cb = widget.children;

    return Column(
      children: [
        line('Branch', 'Price buy', 'Used', 'Total', style: headStyle),
        const Divider(height: 1),
        for (final r in rows) ...[
          line(
              multi && r.currency.isNotEmpty
                  ? '${r.branch} (${r.currency})'
                  : r.branch,
              _fmt(r.priceBuy),
              _fmt(r.priceSale),
              _fmt(r.total),
              style: cellStyle,
              onTap: cb == null ? null : () => _toggle(r),
              open: _open.contains(_key(r))),
          if (cb != null && _open.contains(_key(r)))
            Container(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              child: Column(
                children: () {
                  final items = cb(r);
                  if (items.isEmpty) {
                    return [
                      child(const BranchPoItem(po: '-', sub: '', amount: ''))
                    ];
                  }
                  return [for (final it in items) child(it)];
                }(),
              ),
            ),
          const Divider(height: 1),
        ],
        for (final g in groups)
          line(
              multi ? 'Total $g' : 'Total',
              _fmt(rows
                  .where((r) => currencies.isEmpty || r.currency == g)
                  .fold<double>(0, (s, r) => s + r.priceBuy)),
              _fmt(rows
                  .where((r) => currencies.isEmpty || r.currency == g)
                  .fold<double>(0, (s, r) => s + r.priceSale)),
              _fmt(rows
                  .where((r) => currencies.isEmpty || r.currency == g)
                  .fold<double>(0, (s, r) => s + r.total)),
              style: cellStyle,
              bold: true),
        if (currencies.length == 1)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 22),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(currencies.first, style: headStyle),
            ),
          ),
      ],
    );
  }
}
