// Take a photo of the ATM number -> read the digits on the phone (ML Kit) -> open that ATM.
// Needs:  flutter pub add google_mlkit_text_recognition   (image_picker is already in the project)
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'crud.dart';
import 'widgets.dart';
import 'screens.dart' show AtmIssueHub;

Future<dynamic> _tryGet(String path) async {
  try {
    return await Api.get(path);
  } catch (_) {
    return null;
  }
}

/// digit strings that could be an ATM id, best guesses first (8 digits, then the rest)
List<String> _candidates(String text) {
  final out = <String>[];
  void add(String s) {
    if (s.length >= 6 && s.length <= 12 && !out.contains(s)) out.add(s);
  }

  for (final m in RegExp(r'\d{6,12}').allMatches(text)) {
    add(m.group(0)!);
  }
  for (final line in text.split('\n')) {
    add(line.replaceAll(RegExp(r'[^0-9]'), ''));
  }
  // a leading 0 is often dropped by OCR (3002003 -> 03002003)
  for (final s in List<String>.from(out)) {
    if (s.length == 7) add('0$s');
  }
  out.sort((a, b) => (b.length == 8 ? 1 : 0).compareTo(a.length == 8 ? 1 : 0));
  return out.take(8).toList();
}

Future<void> openAtmFromPhoto(BuildContext context) async {
  final shot = await ImagePicker()
      .pickImage(source: ImageSource.camera, imageQuality: 90);
  if (shot == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
      content: Text('ກຳລັງອ່ານເລກຈາກຮູບ…'), duration: Duration(seconds: 2)));

  var text = '';
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final r = await rec.processImage(InputImage.fromFilePath(shot.path));
    text = r.text;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('ອ່ານຮູບບໍ່ໄດ້: $e')));
    return;
  } finally {
    await rec.close();
  }
  if (!context.mounted) return;

  final cands = _candidates(text);
  for (final c in cands) {
    final a = await _tryGet('/atms/${Uri.encodeComponent(c)}');
    if (a is Map) {
      final id = pick(Map<String, dynamic>.from(a), ['atmId']);
      if (id.isNotEmpty) {
        if (!context.mounted) return;
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => AtmIssueHub(id)));
        return;
      }
    }
  }
  if (!context.mounted) return;
  final again = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('ບໍ່ພົບຕູ້ ATM'),
      content: Text(cands.isEmpty
          ? 'ບໍ່ເຫັນຕົວເລກໃນຮູບ. ຖ່າຍໃກ້ໆ ໃຫ້ເຫັນເລກຕູ້ຊັດເຈນ'
          : 'ອ່ານໄດ້: ${cands.join(', ')}\nແຕ່ບໍ່ກົງກັບຕູ້ໃດ'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false), child: const Text('ປິດ')),
        FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('ຖ່າຍໃໝ່')),
      ],
    ),
  );
  if (again == true && context.mounted) await openAtmFromPhoto(context);
}
