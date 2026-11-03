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

class BranchPriceTable extends StatelessWidget {
  final List<BranchPriceRow> rows;
  final void Function(BranchPriceRow row)? onTap;

  const BranchPriceTable({super.key, required this.rows, this.onTap});

  String _fmt(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cellStyle = theme.textTheme.bodyMedium;

    final currencies = rows
        .map((r) => r.currency)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    final multi = currencies.length > 1;

    Widget line(String a, String b, String c, String d,
        {TextStyle? style, bool bold = false, VoidCallback? onTap}) {
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
              const Icon(Icons.chevron_right, size: 18)
            else
              const SizedBox(width: 18),
          ],
        ),
      );
      if (onTap == null) return content;
      return InkWell(onTap: onTap, child: content);
    }

    final groups = currencies.isEmpty ? [''] : currencies;

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
              onTap: onTap == null ? null : () => onTap!(r)),
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
