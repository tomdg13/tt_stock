import 'package:flutter/material.dart';
import 'plan_pdf.dart';

Future<void> pickPlanPdf(BuildContext context, Map<String, dynamic> plan,
    List<Map<String, dynamic>> items) async {
  final r = await showModalBottomSheet<int>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('ແຜ່ນສັງຊື້'),
          subtitle: const Text(
              'ຕາຕະລາງ: ຮູບ, ສະຕັອກ, ນັບຕົວຈິງ, ໃຊ້, ຕ້ອງຊື້, ຊື້ແຜນນີ້'),
          onTap: () => Navigator.pop(c, 1),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('ສັງຊື້'),
          subtitle: const Text('ໜັງສືສະເໜີ ມີຫົວຈົດໝາຍ LDB'),
          onTap: () => Navigator.pop(c, 2),
        ),
      ]),
    ),
  );
  if (r == 1) await exportPlanSheetPdf(plan, items);
  if (r == 2) await exportPlanPdf(plan, items);
}
