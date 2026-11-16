import 'package:flutter/material.dart';
import 'theme.dart';

class StatusBarItem {
  final String key, label;
  final Color color;
  const StatusBarItem(this.key, this.label, this.color);
}

IconData _iconFor(String k) {
  switch (k) {
    case 'pending':
      return Icons.hourglass_top_outlined;
    case 'approved':
      return Icons.local_shipping_outlined;
    case 'received':
      return Icons.inventory_2_outlined;
    case 'rejected':
      return Icons.cancel_outlined;
    case 'cancelled':
    case 'canceled':
      return Icons.block;
    default:
      return Icons.circle_outlined;
  }
}

/// Row of status icons with red count badges (like an order-status strip).
/// Tap an icon to filter, tap again to clear.
class RequestStatusBar extends StatelessWidget {
  final List<StatusBarItem> items;
  final Map<String, int> counts;
  final String? selected;
  final void Function(String) onSelect;
  const RequestStatusBar(
      {super.key,
      required this.items,
      required this.counts,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final sel = selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('ສະຖານະຄຳຂໍ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (sel is String)
            TextButton(
                onPressed: () => onSelect(sel),
                child: const Text('ລ້າງຕົວກອງ')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          for (final it in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(it.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel == it.key
                                ? it.color.withValues(alpha: 0.18)
                                : Colors.transparent),
                        child: Icon(_iconFor(it.key),
                            size: 28,
                            color: sel == it.key ? it.color : p.mut),
                      ),
                      if ((counts[it.key] ?? 0) > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE91E63),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('${counts[it.key]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(it.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                sel == it.key ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
              ),
            ),
        ]),
        const Divider(),
      ]),
    );
  }
}
