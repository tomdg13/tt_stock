import 'package:flutter/material.dart';
import 'theme.dart';

/// Two navigation buttons for the product detail page:
///  - POs that contain this product
///  - ATMs where this product was installed
/// Shown as a card with two big tiles (icon above label), side by side.
class ProductUsageButtons extends StatelessWidget {
  const ProductUsageButtons({
    super.key,
    required this.onOpenPOs,
    required this.onOpenATMs,
    this.poCount,
    this.atmCount,
    this.poLabel = 'ໃບສັ່ງຊື້ (PO)',
    this.atmLabel = 'ໃຊ້ໃນ ATM',
  });

  final VoidCallback onOpenPOs;
  final VoidCallback onOpenATMs;

  /// Optional counts shown as a badge. Leave null to hide the badge.
  final int? poCount;
  final int? atmCount;

  final String poLabel;
  final String atmLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _NavButton(
              icon: Icons.receipt_long_outlined,
              label: poLabel,
              count: poCount,
              onTap: onOpenPOs,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _NavButton(
              icon: Icons.atm_outlined,
              label: atmLabel,
              count: atmCount,
              onTap: onOpenATMs,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary.withAlpha(20),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: count != null,
                label: Text('${count ?? ''}'),
                child: Icon(icon, color: primary, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Icon(Icons.chevron_right, color: primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
