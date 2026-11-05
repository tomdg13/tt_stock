import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets.dart';

/// Builds an .xlsx of one PO (header block + item table + total) and opens the share sheet.
Future<void> exportPoExcel(
  BuildContext context,
  String po,
  String grn,
  String branch,
  String date,
  String currency,
  List<Map<String, dynamic>> items,
) async {
  void toast(String t) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }

  double n(dynamic v) =>
      double.tryParse('$v'.replaceAll(',', '').trim()) ?? 0;

  try {
    final first = items.isEmpty ? <String, dynamic>{} : items.first;
    final ex = xl.Excel.createExcel();
    ex.rename('Sheet1', 'PO');
    final sheet = ex['PO'];
    final bold = xl.CellStyle(bold: true);

    xl.TextCellValue t(String s) => xl.TextCellValue(s);
    xl.DoubleCellValue d(double v) => xl.DoubleCellValue(v);
    var row = 0;
    void add(List<xl.CellValue?> cells) {
      sheet.appendRow(cells);
      row++;
    }

    void boldRow(int r, int cols) {
      for (var c = 0; c < cols; c++) {
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .cellStyle = bold;
      }
    }

    var sum = 0.0;
    final lines = <List<xl.CellValue?>>[];
    var i = 0;
    for (final m in items) {
      i++;
      final qty = n(pick(m, ['qtyChange', 'qty', 'quantity', 'delta']));
      final cost = n(pick(m, ['unitCost']));
      final aStr = pick(m, ['amount']);
      final amt = aStr.isNotEmpty ? n(aStr) : qty * cost;
      sum += amt;
      lines.add([
        xl.IntCellValue(i),
        t(pick(m, ['partNo'])),
        t(pick(m, ['productName', 'name', 'productId'])),
        d(qty),
        d(cost),
        d(amt),
      ]);
    }
    final freight = n(pick(first, ['freightCost']));
    final tStr = pick(first, ['totalAmount']);
    final invoiceTotal = tStr.isNotEmpty ? n(tStr) : sum + freight;

    add([t('PO'), t(po)]);
    add([t('GRN'), t(grn)]);
    add([t('Branch'), t(branch)]);
    add([t('Date'), t(date)]);
    add([t('Currency'), t(currency)]);
    add([t('Items total'), d(sum)]);
    add([t('Freight'), d(freight)]);
    add([t('Invoice total'), d(invoiceTotal)]);
    boldRow(0, 1);
    add([t('')]);

    final head = row;
    add([
      t('No'),
      t('Part no'),
      t('Name'),
      t('Qty'),
      t('Unit cost'),
      t('Amount'),
    ]);
    boldRow(head, 6);
    for (final l in lines) {
      add(l);
    }
    final tot = row;
    add([t(''), t(''), t('Total'), null, null, d(sum)]);
    boldRow(tot, 6);

    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 30);
    sheet.setColumnWidth(2, 46);
    sheet.setColumnWidth(3, 10);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 16);

    final bytes = ex.encode();
    if (bytes == null) {
      toast('Excel error');
      return;
    }
    final dir = await getTemporaryDirectory();
    final safe = (po.isEmpty ? grn : po).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/PO_$safe.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [
        XFile(file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
      subject: 'PO $po',
    );
  } catch (e) {
    debugPrint('[PO] export excel failed: $e');
    toast('Export failed: $e');
  }
}
