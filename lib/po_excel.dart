import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'file_download.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class XlFormula {
  final String f;
  final double v;
  const XlFormula(this.f, this.v);
}

class XlImage {
  final int row;
  final int col;
  final String key;
  final Uint8List bytes;
  final int w;
  final int h;
  const XlImage({
    required this.row,
    required this.col,
    required this.key,
    required this.bytes,
    required this.w,
    required this.h,
  });
}

String _typesXml(bool pics) {
  final jpg = pics ? '<Default Extension="jpg" ContentType="image/jpeg"/>' : '';
  final drw = pics
      ? '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'
      : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>$jpg<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>$drw</Types>';
}

const _rels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';

const _workbook =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="PO" sheetId="1" r:id="rId1"/></sheets></workbook>';

const _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';

const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Phetsarath OT"/></font><font><b/><sz val="11"/><name val="Phetsarath OT"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="4" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>';

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
  Set<int> hiddenCols = const {},
  List<XlImage> images = const [],
  Map<int, double> rowHeights = const {},
  String? pageHeader,
  String? pageFooter,
}) async {
  final pics = images.isNotEmpty;
  debugPrint(
      '[XLSX] sharePoXlsx file=$fileName rows=${rows.length} images=${images.length}');
  final sb = StringBuffer();
  sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  sb.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
  if (pageHeader != null || pageFooter != null) {
    sb.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
  }
  if (widths.isNotEmpty) {
    sb.write('<cols>');
    for (var i = 0; i < widths.length; i++) {
      final hid = hiddenCols.contains(i) ? ' hidden="1"' : '';
      sb.write(
          '<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"$hid/>');
    }
    sb.write('</cols>');
  }
  sb.write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    final ht = rowHeights[r];
    final ha = ht == null ? '' : ' ht="$ht" customHeight="1"';
    sb.write('<row r="${r + 1}"$ha>');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final ref = '${_col(c)}${r + 1}';
      final bold = boldRows.contains(r);
      if (v is XlFormula) {
        sb.write(
            '<c r="$ref" s="${bold ? 3 : 2}"><f>${_esc(v.f)}</f><v>${v.v}</v></c>');
      } else if (v is num) {
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
  sb.write('</sheetData>');
  if (pageHeader != null || pageFooter != null) {
    sb.write(
        '<pageMargins left="0.4" right="0.4" top="0.9" bottom="0.9" header="0.4" footer="0.4"/>');
    sb.write(
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>');
    sb.write('<headerFooter>');
    if (pageHeader != null) {
      sb.write('<oddHeader>${_esc(pageHeader)}</oddHeader>');
    }
    if (pageFooter != null) {
      sb.write('<oddFooter>${_esc(pageFooter)}</oddFooter>');
    }
    sb.write('</headerFooter>');
  }
  if (pics) sb.write('<drawing r:id="rId1"/>');
  sb.write('</worksheet>');

  final arc = Archive();
  void add(String name, String text) {
    final b = utf8.encode(text);
    arc.addFile(ArchiveFile(name, b.length, b));
  }

  add('[Content_Types].xml', _typesXml(pics));
  add('_rels/.rels', _rels);
  add('xl/workbook.xml', _workbook);
  add('xl/_rels/workbook.xml.rels', _workbookRels);
  add('xl/styles.xml', _styles);
  add('xl/worksheets/sheet1.xml', sb.toString());

  if (pics) {
    final keyIdx = <String, int>{};
    final media = <Uint8List>[];
    final dr = StringBuffer();
    dr.write(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    for (var i = 0; i < images.length; i++) {
      final im = images[i];
      final idx = keyIdx.putIfAbsent(im.key, () {
        media.add(im.bytes);
        return media.length;
      });
      final cx = im.w * 9525;
      final cy = im.h * 9525;
      dr.write(
          '<xdr:oneCellAnchor><xdr:from><xdr:col>${im.col}</xdr:col><xdr:colOff>38100</xdr:colOff><xdr:row>${im.row}</xdr:row><xdr:rowOff>38100</xdr:rowOff></xdr:from><xdr:ext cx="$cx" cy="$cy"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${i + 2}" name="Picture ${i + 1}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId$idx"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>');
    }
    dr.write('</xdr:wsDr>');
    add('xl/drawings/drawing1.xml', dr.toString());

    final dRels = StringBuffer();
    dRels.write(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < media.length; i++) {
      dRels.write(
          '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${i + 1}.jpg"/>');
      arc.addFile(
          ArchiveFile('xl/media/image${i + 1}.jpg', media[i].length, media[i]));
    }
    dRels.write('</Relationships>');
    add('xl/drawings/_rels/drawing1.xml.rels', dRels.toString());
    add('xl/worksheets/_rels/sheet1.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>');
  }

  final dynamic out = ZipEncoder().encode(arc);
  final bytes = Uint8List.fromList(List<int>.from(out as Iterable));
  final partNames = <String>[];
  for (final f in arc) {
    partNames.add(f.name);
  }
  debugPrint('[XLSX] zip bytes=${bytes.length} parts=${partNames.join(', ')}');

  const xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (kIsWeb) {
    await downloadBytes(bytes, fileName, xlsxMime);
    debugPrint('[XLSX] web download $fileName size=${bytes.length}');
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  debugPrint('[XLSX] saved ${file.path} size=${await file.length()}');
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    ],
    text: fileName,
  ));
}
