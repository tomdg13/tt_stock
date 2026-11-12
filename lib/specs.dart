import 'product_usage.dart';
// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart';
import 'product_images.dart';
import 'widgets.dart';
import 'stock_request.dart';

String _id(Row_ r) => pick(r, ['id']);

const _planStatuses = [
  'draft',
  'ordered',
  'partial',
  'done',
  'closed',
  'cancelled'
];

Future<void> _branchAccess(BuildContext c, Row_ row) async {
  try {
    final id = row['id'];
    if ('${row['isHq']}' == '1') {
      toastMsg(c, 'Head Office ເບິ່ງ ແລະ ຂໍອາໄຫຼ່ໄດ້ທຸກສາຂາ ບໍ່ຕ້ອງຕິກ');
      return;
    }
    final cur = await Api.get('/branches/$id/branch-perms');
    final see =
        cur is Map && cur['seeIds'] is List ? cur['seeIds'] as List : [];
    final req =
        cur is Map && cur['reqIds'] is List ? cur['reqIds'] as List : [];
    final list = asList(await Api.get('/branches'));
    final all = <MapEntry<dynamic, String>>[
      for (final b in list)
        if (('${b['id']}' == '$id') == false)
          MapEntry(b['id'], pick(b, ['name']))
    ];
    final hq = <String>{
      for (final b in list)
        if ('${b['isHq']}' == '1') '${b['id']}'
    };
    if (c.mounted == false) return;
    final res = await pickBranchPerms(
        c, pick(row, ['name', 'code']), all, hq, see, req);
    if (res == null) return;
    await Api.put('/branches/$id/branch-perms',
        {'seeIds': res.seeIds, 'reqIds': res.reqIds});
    if (c.mounted) toastMsg(c, 'ບັນທຶກແລ້ວ');
  } catch (e) {
    if (c.mounted) toastMsg(c, '$e');
  }
}

Future<void> _userPerms(BuildContext c, Row_ row) async {
  try {
    final all = await loadOptions('/functions', 'id', ['name']);
    final dynamic cur = row['perms'] ?? row['permissions'] ?? [];
    final ids = [
      for (final x in (cur is List ? cur : []))
        x is Map ? (x['funcCode'] ?? x['id']) : x
    ];
    if (!c.mounted) return;
    final res = await pickMulti(c, 'ສິດສະເພາະຜູ້ໃຊ້', all, ids);
    if (res == null) return;
    await Api.put('/users/${row['id']}/permissions', {'perms': res});
    if (c.mounted) toastMsg(c, 'ບັນທຶກແລ້ວ');
  } catch (e) {
    if (c.mounted) toastMsg(c, '$e');
  }
}

Future<void> _userResetPerms(BuildContext c, Row_ row) async {
  try {
    await Api.put('/users/${row['id']}/permissions', {'perms': null});
    if (c.mounted) toastMsg(c, 'ກັບໄປໃຊ້ສິດຕາມບົດບາດແລ້ວ');
  } catch (e) {
    if (c.mounted) toastMsg(c, '$e');
  }
}

Future<void> _planStatus(BuildContext c, Row_ row) async {
  final v =
      await pickOne(c, 'ປ່ຽນສະຖານະແຜນ', _planStatuses, pick(row, ['status']));
  if (v == null) return;
  try {
    await Api.put('/plans/${row['id']}/status', {'status': v});
    if (c.mounted) toastMsg(c, 'ປ່ຽນສະຖານະແລ້ວ');
  } catch (e) {
    if (c.mounted) toastMsg(c, '$e');
  }
}

/// Add / edit / delete definitions for every page that has write routes.
/// Field names are inferred from the route list; if the server rejects one,
/// the form's JSON switch lets you correct it without rebuilding the app.
CrudSpec? crudSpec(String key) {
  switch (key) {
    case 'branches':
      return CrudSpec(
        title: 'ສາຂາ',
        path: '/branches',
        idOf: _id,
        writePerm: 'BRANCH_MANAGE',
        searchable: false,
        titleKeys: const ['name'],
        subKeys: const ['code'],
        fields: const [
          FieldSpec('name', 'ຊື່ສາຂາ', required: true),
          FieldSpec('isHq', 'ສຳນັກງານໃຫຍ່ (HQ)',
              type: FT.bool, altKeys: ['hq']),
        ],
        actions: [
          RowAction(
              'ສິດເບິ່ງຂ້າມສາຂາ', Icons.visibility_outlined, _branchAccess,
              perm: 'BRANCH_MANAGE')
        ],
      );
    case 'ttypes':
      return CrudSpec(
        title: 'ປະເພດ Terminal',
        path: '/terminal-types',
        idOf: (r) => pick(r, ['typeId', 'id']),
        writePerm: 'PRODUCT_MANAGE',
        typeImage: true,
        searchable: false,
        titleKeys: const ['name', 'code'],
        subKeys: const ['code', 'id'],
        fields: const [
          FieldSpec('id', 'ID (ເຊັ່ນ 41, 44)',
              type: FT.number, required: true, onlyAdd: true),
          FieldSpec('name', 'ຊື່', required: true),
        ],
      );
    case 'brand':
      return CrudSpec(
        title: 'BRAND',
        path: '/brands',
        idOf: _id,
        writePerm: 'PRODUCT_MANAGE',
        searchable: false,
        titleKeys: const ['name'],
        fields: const [FieldSpec('name', 'ຊື່ BRAND', required: true)],
      );
    case 'model':
      return CrudSpec(
        title: 'MODEL',
        path: '/models',
        idOf: _id,
        writePerm: 'PRODUCT_MANAGE',
        searchable: false,
        titleKeys: const ['name'],
        subKeys: const ['brandName', 'legacyName'],
        fields: const [
          FieldSpec('brandId', 'BRAND',
              type: FT.select, required: true, optionsPath: '/brands'),
          FieldSpec('name', 'ຊື່ MODEL', required: true),
          FieldSpec('legacyName', 'ຊື່ເກົ່າ (legacy)'),
        ],
      );
    case 'bins':
      return CrudSpec(
        title: 'ບ່ອນເກັບ',
        path: '/bins',
        idOf: _id,
        writePerm: 'BIN_MANAGE',
        searchable: false,
        titleKeys: const ['code', 'name'],
        subKeys: const ['name'],
        fields: const [
          FieldSpec('code', 'ລະຫັດ', required: true),
          FieldSpec('name', 'ຊື່'),
        ],
      );
    case 'vendors':
      return CrudSpec(
        title: 'Vendor',
        path: '/vendors',
        idOf: _id,
        writePerm: 'PO_MANAGE',
        searchable: false,
        titleKeys: const ['name'],
        subKeys: const ['phone'],
        fields: const [
          FieldSpec('name', 'ຊື່ Vendor', required: true),
          FieldSpec('phone', 'ເບີໂທ'),
        ],
      );
    case 'funcs':
      return CrudSpec(
        title: 'ຟັງຊັນ',
        path: '/functions',
        idOf: (r) => pick(r, ['funcCode', 'id']),
        writePerm: 'ROLE_MANAGE',
        searchable: false,
        titleKeys: const ['funcCode', 'funcLabel'],
        subKeys: const ['description'],
        fields: const [
          FieldSpec('funcCode', 'ລະຫັດຟັງຊັນ',
              required: true, onlyAdd: true, altKeys: ['id']),
          FieldSpec('funcLabel', 'ຊື່ຟັງຊັນ', required: true),
          FieldSpec('description', 'ລາຍລະອຽດ'),
        ],
      );
    case 'prod':
      return CrudSpec(
        title: 'ສິນຄ້າ',
        path: '/products',
        idOf: _id,
        writePerm: 'PRODUCT_MANAGE',
        extraQuery: 'limit=100',
        titleKeys: const ['name', 'productName'],
        subKeys: const ['typeName', 'brandName', 'code'],
        trailKeys: const ['stock', 'qty'],
        detailPath: (r) => '/products/${_id(r)}',
        images: true,
        barcodes: true,
        fields: const [
          FieldSpec('name', 'ຊື່ສິນຄ້າ', required: true),
          FieldSpec('typeId', 'ປະເພດ',
              type: FT.select,
              required: true,
              optionsPath: '/terminal-types',
              optionValue: 'typeId',
              nameKey: 'typeName'),
          FieldSpec('brandId', 'BRAND',
              type: FT.select, required: true, optionsPath: '/brands'),
          FieldSpec('binId', 'ບ່ອນເກັບ',
              type: FT.select,
              optionsPath: '/bins',
              optionLabels: ['code', 'name']),
          FieldSpec('unit', 'ຫົວໜ່ວຍ'),
          FieldSpec('minQty', 'ຈຳນວນຕ່ຳສຸດ', type: FT.number),
          FieldSpec('cost', 'ຕົ້ນທຶນ (₭)', type: FT.number),
          FieldSpec('modelIds', 'MODEL ທີ່ແມັບ (ຕ້ອງເປັນ BRAND ດຽວກັນ)',
              type: FT.multi, optionsPath: '/models', altKeys: ['models']),
          FieldSpec('isActive', 'ເປີດໃຊ້',
              type: FT.bool, onlyEdit: true, altKeys: ['active']),
        ],
        actions: [
          RowAction('ຮູບພາບ', Icons.photo_library_outlined,
              (c, r) => openProductImages(c, r)),
          RowAction('ໃບສັ່ງຊື້ (PO)', Icons.receipt_long_outlined,
              (c, r) => openProductPOs(c, r)),
          RowAction('ໃຊ້ໃນ ATM', Icons.atm_outlined,
              (c, r) => openProductInstalls(c, r)),
        ],
      );
    case 'users':
      return CrudSpec(
        title: 'ຜູ້ໃຊ້',
        path: '/users',
        idOf: _id,
        writePerm: 'USER_MANAGE',
        searchable: false,
        titleKeys: const ['fullName', 'name', 'phone'],
        subKeys: const ['phone', 'branchName'],
        tagKeys: const ['roleName', 'role'],
        fields: const [
          FieldSpec('phone', 'ເບີໂທ', required: true, onlyAdd: true),
          FieldSpec('pin', 'PIN (4-6 ໂຕເລກ)', type: FT.pin, required: true),
          FieldSpec('fullName', 'ຊື່', required: true, altKeys: ['name']),
          FieldSpec('roleName', 'ບົດບາດ',
              type: FT.select,
              required: true,
              optionsPath: '/roles',
              optionValue: 'roleName',
              optionLabels: ['roleLabel', 'roleName'],
              altKeys: ['role']),
          FieldSpec('branchId', 'ສາຂາ',
              type: FT.select,
              optionsPath: '/branches',
              hideIf: ('roleName', 'admin'),
              requiredUnless: ('roleName', 'admin')),
          FieldSpec('isActive', 'ເປີດໃຊ້',
              type: FT.bool, onlyEdit: true, altKeys: ['active']),
        ],
        actions: [
          RowAction('ຕັ້ງສິດເອງ', Icons.tune, _userPerms, perm: 'USER_MANAGE'),
          RowAction('ໃຊ້ສິດຕາມບົດບາດ', Icons.restart_alt, _userResetPerms,
              perm: 'USER_MANAGE'),
        ],
      );
    case 'roles':
      return CrudSpec(
        title: 'ບົດບາດ',
        path: '/roles',
        idOf: (r) => pick(r, ['roleName', 'name']),
        writePerm: 'ROLE_MANAGE',
        searchable: false,
        titleKeys: const ['roleLabel', 'roleName'],
        subKeys: const ['roleName'],
        fields: const [
          FieldSpec('roleName', 'Code ບົດບາດ (a-z, 0-9, _)',
              required: true, altKeys: ['name']),
          FieldSpec('roleLabel', 'ຊື່ບົດບາດ', required: true),
          FieldSpec('scopeAllBranches', 'ເຫັນທຸກສາຂາ', type: FT.bool),
          FieldSpec('perms', 'ສິດການໃຊ້ງານແຕ່ລະໜ້າ',
              type: FT.matrix, altKeys: ['permissions']),
        ],
      );
    case 'plans':
      return CrudSpec(
        title: 'ແຜນຈັດຊື້',
        path: '/plans',
        idOf: _id,
        writePerm: 'PO_MANAGE',
        searchable: false,
        titleKeys: const ['planNo', 'name', 'id'],
        subKeys: const ['vendorName', 'brandName'],
        tagKeys: const ['status'],
        detailPath: (r) => '/plans/${_id(r)}',
        fields: const [
          FieldSpec('vendorId', 'Vendor',
              type: FT.select, required: true, optionsPath: '/vendors'),
          FieldSpec('brandId', 'BRAND',
              type: FT.select, required: true, optionsPath: '/brands'),
          FieldSpec('currency', 'ສະກຸນເງິນ',
              type: FT.select,
              required: true,
              options: {
                'LAK': 'LAK',
                'THB': 'THB',
                'USD': 'USD',
                'CNY': 'CNY'
              }),
          FieldSpec('destBranchId', 'ສາຂາປາຍທາງ',
              type: FT.select, optionsPath: '/branches', altKeys: ['branchId']),
          FieldSpec('note', 'ໝາຍເຫດ'),
        ],
        actions: [
          RowAction('ປ່ຽນສະຖານະ', Icons.flag_outlined, _planStatus,
              perm: 'PO_MANAGE')
        ],
      );
    case 'atms':
      return CrudSpec(
        title: 'ຕູ້ ATM',
        path: '/atms',
        idOf: (r) => pick(r, ['atmId']),
        writePerm: 'ATM_MANAGE',
        canDelete: false,
        extraQuery: 'limit=100',
        titleKeys: const ['atmId'],
        subKeys: const ['atmLocation', 'location', 'groupName', 'atmGroupId'],
        tagKeys: const ['atmStatus', 'status'],
        detailPath: (r) => '/atms/${Uri.encodeComponent(pick(r, ['atmId']))}',
        fields: const [
          FieldSpec('atmId', 'ATM ID', required: true, onlyAdd: true),
          FieldSpec('atmType', 'ຍີ່ຫໍ້ (NCR / GRG ...)'),
          FieldSpec('atmGroupId', 'ກຸ່ມ / ສາຂາ'),
          FieldSpec('atmLocation', 'ສະຖານທີ່', altKeys: ['location']),
          FieldSpec('atmIpAddr', 'IP', altKeys: ['ip', 'ipAddr']),
          FieldSpec('atmPortNum', 'Port', type: FT.number, altKeys: ['port']),
          FieldSpec('atmBranchId', 'Branch ID'),
          FieldSpec('serialAtm', 'Serial', altKeys: ['serial']),
          FieldSpec('atmStatus', 'ສະຖານະ', type: FT.select, altKeys: [
            'status'
          ], options: {
            'active': 'ໃຊ້ງານ',
            'warehouse': 'ໃນສາງ',
            'close': 'ປິດ',
            'waitLocation': 'ລໍຖ້າຕິດຕັ້ງ',
            'unactive': 'ບໍ່ໃຊ້',
            'move': 'ຍ້າຍ',
            'testing': 'ທົດສອບ',
          }),
          FieldSpec('atmVersion', 'ເວີຊັນ', altKeys: ['version']),
          FieldSpec('atmLat', 'Latitude'),
          FieldSpec('atmLong', 'Longitude'),
          FieldSpec('note', 'ໝາຍເຫດ'),
        ],
      );
    case 'terms':
      return CrudSpec(
        title: 'Terminal',
        path: '/terminals',
        idOf: (r) => pick(r, ['barcode']),
        writePerm: 'ATM_MANAGE',
        extraQuery: 'limit=100',
        titleKeys: const ['barcode'],
        subKeys: const ['typeName', 'atmId'],
        tagKeys: const ['state', 'status'],
        detailPath: (r) =>
            '/terminals/${Uri.encodeComponent(pick(r, ['barcode']))}',
        fields: const [
          FieldSpec('barcode', 'Barcode', required: true, onlyAdd: true),
          FieldSpec('typeId', 'ປະເພດ (ເວັ້ນວ່າງ = ຫາຈາກ prefix)',
              type: FT.select, optionsPath: '/terminal-types'),
        ],
      );
    case 'actrep':
      return CrudSpec(
        title: 'Activity',
        path: '/activities',
        listPath: '/activity-report',
        idOf: (r) => pick(r, ['id']),
        writePerm: 'ATM_MANAGE',
        canEdit: false,
        canDelete: false,
        titleKeys: const ['barcode'],
        subKeys: const ['atmId', 'user', 'createdAt'],
        tagKeys: const ['status'],
        fields: const [
          FieldSpec('barcode', 'Terminal barcode', required: true),
          FieldSpec('status', 'ສະຖານະ',
              type: FT.select,
              required: true,
              options: {'Ready': 'Ready', 'In Use': 'In Use', 'MA': 'MA'}),
          FieldSpec('atmId', 'ATM ID (ຈຳເປັນຖ້າ In Use)'),
        ],
      );
  }
  return null;
}
