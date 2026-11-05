import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _types =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>';

const _rels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';

const _workbook =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="PO" sheetId="1" r:id="rId1"/></sheets></workbook>';

const _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';

const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="4" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>';

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

Future<void> sharePoXlsx({
  required String fileName,
  required List<List<Object>> rows,
  Set<int> boldRows = const {},
  List<double> widths = const [],
}) async {
  final sb = StringBuffer();
  sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  sb.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  if (widths.isNotEmpty) {
    sb.write('<cols>');
    for (var i = 0; i < widths.length; i++) {
      sb.write(
          '<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>');
    }
    sb.write('</cols>');
  }
  sb.write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sb.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final ref = '${_col(c)}${r + 1}';
      final bold = boldRows.contains(r);
      if (v is num) {
        final st = bold ? (v is int ? 1 : 3) : (v is int ? 0 : 2);
        sb.write('<c r="$ref" s="$st"><v>$v</v></c>');
      } else {
        final s = v.toString();
        if (s.isEmpty) continue;
        sb.write(
            '<c r="$ref" s="${bold ? 1 : 0}" t="inlineStr"><is><t xml:space="preserve">${_esc(s)}</t></is></c>');
      }
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');

  final arc = Archive();
  void add(String name, String text) {
    final b = utf8.encode(text);
    arc.addFile(ArchiveFile(name, b.length, b));
  }

  add('[Content_Types].xml', _types);
  add('_rels/.rels', _rels);
  add('xl/workbook.xml', _workbook);
  add('xl/_rels/workbook.xml.rels', _workbookRels);
  add('xl/styles.xml', _styles);
  add('xl/worksheets/sheet1.xml', sb.toString());

  final dynamic out = ZipEncoder().encode(arc);
  final bytes = Uint8List.fromList(List<int>.from(out as Iterable));

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    ],
    text: fileName,
  ));
}
