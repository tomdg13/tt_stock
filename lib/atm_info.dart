import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
import 'theme.dart';
import 'widgets.dart';

/// ATM details: name, group id, IP, port, version, serial. [d] is the /atms/<id> response.
class AtmInfoCard extends StatelessWidget {
  final Map<String, dynamic> d;
  const AtmInfoCard(this.d, {super.key});

  Widget _row(String label, String value, Color mut) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 96,
            child: Text(label, style: TextStyle(color: mut, fontSize: 13))),
        Expanded(
          child: SelectableText(value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('ຊື່ຕູ້ ATM', pick(d, ['atmLocation', 'location', 'atmName']),
              p.mut),
          _row('Group ID', pick(d, ['atmGroupId', 'groupId']), p.mut),
          _row('IP', pick(d, ['atmIpAddr', 'ip']), p.mut),
          _row('Port', pick(d, ['atmPortNum', 'port']), p.mut),
          _row('ATM Version', pick(d, ['atmVersion', 'version']), p.mut),
          _row('Serial', pick(d, ['serialAtm', 'serial']), p.mut),
        ]),
      ),
    );
  }
}
