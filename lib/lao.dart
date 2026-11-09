import 'package:flutter/material.dart';

// Labels copied from the TT Stock demo.
const reasons = {
  'sale': 'ຂາຍ',
  'internal_use': 'ໃຊ້ພາຍໃນ',
  'damaged': 'ເສຍຫາຍ',
  'expired': 'ໝົດອາຍຸ',
  'return_supplier': 'ສົ່ງຄືນຜູ້ສະໜອງ',
  'other': 'ອື່ນໆ',
};

const Map<String, List<String>> moveTypes = {
  'purchase_in': ['ຊື້ເຂົ້າ', 'in'],
  'receive': ['ຮັບເຂົ້າ', 'in'],
  'issue_out': ['ເອົາອອກ', 'out'],
  'issue': ['ເອົາອອກ', 'out'],
  'transfer_out': ['ໂອນອອກ', 'tr'],
  'transfer_in': ['ໂອນເຂົ້າ', 'in'],
  'opening': ['ຍອດຍົກມາ', ''],
};

const Map<String, List<String>> transferStatus = {
  'in_transit': ['ລະຫວ່າງທາງ', 'tr'],
  'received': ['ຮັບແລ້ວ', 'in'],
  'cancelled': ['ຍົກເລີກ', 'out'],
  'canceled': ['ຍົກເລີກ', 'out'],
};

const roleNames = {
  'admin': 'ຜູ້ດູແລລະບົບ',
  'manager': 'ຜູ້ຈັດການສາຂາ',
  'warehouse': 'ພະນັກງານຄັງ',
};

class MenuItemDef {
  final String key, label;
  final IconData icon;
  final List<String> need; // any-of permissions; empty = always shown
  const MenuItemDef(this.key, this.label, this.icon, [this.need = const []]);
}

class MenuGroup {
  final String? title;
  final List<MenuItemDef> items;
  const MenuGroup(this.title, this.items);
}

// Same groups and permission rules as the demo's side menu.
const menuGroups = <MenuGroup>[
  MenuGroup(null, [
    MenuItemDef('dash', 'ພາບລວມ', Icons.dashboard_outlined, ['REPORT_VIEW']),
  ]),
  MenuGroup('ສະຕັອກ (Stock)', [
    MenuItemDef('stock', 'ສະຕັອກ', Icons.inventory_2_outlined, ['STOCK_VIEW']),
    MenuItemDef('bins', 'ບ່ອນເກັບ', Icons.warehouse_outlined, ['STOCK_VIEW']),
  ]),
  MenuGroup('ທຸລະກຳ (Transaction)', [
    MenuItemDef('recv', 'ຮັບເຂົ້າ', Icons.download_outlined, ['RECEIVE']),
    MenuItemDef('issue', 'ເອົາອອກ', Icons.upload_outlined, ['ISSUE']),
    MenuItemDef('trf', 'ໂອນສາຂາ', Icons.swap_horiz, ['TRANSFER_SEND', 'TRANSFER_RECEIVE']),
    MenuItemDef('req', 'ຂໍອາໄຫຼ່', Icons.move_to_inbox_outlined, ['REQUEST_SEND', 'REQUEST_APPROVE']),
    MenuItemDef('hist', 'ປະຫວັດ', Icons.history, ['REPORT_VIEW']),
  ]),
  MenuGroup('ຈັດຊື້ (Purchasing)', [
    MenuItemDef('plans', 'ແຜນຈັດຊື້', Icons.assignment_outlined, ['PO_MANAGE']),
    MenuItemDef('vendors', 'Vendor', Icons.local_shipping_outlined, ['PO_MANAGE']),
  ]),
  MenuGroup('ສິນຄ້າ (Product)', [
    MenuItemDef('prod', 'ສິນຄ້າ', Icons.sell_outlined, ['STOCK_VIEW']),
    MenuItemDef('brand', 'BRAND', Icons.business_outlined, ['PRODUCT_MANAGE']),
    MenuItemDef('model', 'MODEL', Icons.build_outlined, ['PRODUCT_MANAGE']),
    MenuItemDef('ser', 'Serial', Icons.qr_code_2, ['STOCK_VIEW']),
  ]),
  MenuGroup('ຕູ້ ATM (ATM)', [
    MenuItemDef('atms', 'ຕູ້ ATM', Icons.atm, ['STOCK_VIEW', 'ATM_MANAGE']),
    MenuItemDef('terms', 'Terminal', Icons.memory, ['STOCK_VIEW', 'ATM_MANAGE']),
    MenuItemDef('actrep', 'Activity Report', Icons.fact_check_outlined, ['STOCK_VIEW', 'REPORT_VIEW', 'ATM_MANAGE']),
    MenuItemDef('ttypes', 'ປະເພດ Terminal', Icons.category_outlined, ['STOCK_VIEW']),
  ]),
  MenuGroup('ຜູ້ໃຊ້ ແລະ ສາຂາ (Admin)', [
    MenuItemDef('users', 'ຜູ້ໃຊ້', Icons.group_outlined, ['USER_MANAGE']),
    MenuItemDef('roles', 'ບົດບາດ (Role)', Icons.badge_outlined),
    MenuItemDef('funcs', 'ຟັງຊັນ (Function)', Icons.key_outlined, ['ROLE_MANAGE']),
    MenuItemDef('branches', 'ສາຂາ', Icons.apartment_outlined),
  ]),
];

String labelOf(String key) {
  for (final g in menuGroups) {
    for (final i in g.items) {
      if (i.key == key) return i.label;
    }
  }
  return key;
}

// Lao names of permission codes, copied from the demo (used on role/user permission pickers).
const permLabels = {
  'STOCK_VIEW': 'ເບິ່ງສະຕັອກ',
  'RECEIVE': 'ຮັບເຂົ້າ',
  'ISSUE': 'ເອົາອອກ',
  'TRANSFER_SEND': 'ສົ່ງໂອນ',
  'TRANSFER_RECEIVE': 'ຮັບເຄື່ອງໂອນ',
  'REQUEST_SEND': 'ຂໍອາໄຫຼ່ (ສົ່ງຄຳຂໍ)',
  'REQUEST_APPROVE': 'ຂໍອາໄຫຼ່ (ອະນຸມັດ)',
  'STOCK_COUNT': 'ນັບສະຕັອກ',
  'PO_MANAGE': 'ໃບສັ່ງຊື້ / ແຜນຈັດຊື້',
  'REPORT_VIEW': 'ເບິ່ງລາຍງານ/ປະຫວັດ',
  'USER_MANAGE': 'ຈັດການຜູ້ໃຊ້/ສິດ',
  'BRANCH_MANAGE': 'ຈັດການສາຂາ',
  'PRODUCT_MANAGE': 'ຈັດການສິນຄ້າ',
  'BIN_MANAGE': 'ຈັດການບ່ອນເກັບ',
  'SERIAL_MANAGE': 'ຈັດການ Serial',
  'ROLE_MANAGE': 'ຈັດການບົດບາດ/ຟັງຊັນ',
  'ATM_MANAGE': 'ຈັດການຕູ້ ATM / Terminal',
};

/// One row of the role permission table: which API permission codes the
/// View / Edit / Delete boxes switch. Empty list = not applicable.
class PermPage {
  final String label;
  final List<String> view, edit, del;
  const PermPage(this.label, {this.view = const [], this.edit = const [], this.del = const []});
}

const permPages = <PermPage>[
  PermPage('ພາບລວມ / ປະຫວັດ / ລາຍງານ', view: ['REPORT_VIEW']),
  PermPage('ສະຕັອກ / ສິນຄ້າ / Serial / ຕູ້ ATM', view: ['STOCK_VIEW']),
  PermPage('ຮັບເຂົ້າ', edit: ['RECEIVE']),
  PermPage('ເອົາອອກ', edit: ['ISSUE']),
  PermPage('ໂອນສາຂາ (ສົ່ງ / ຍົກເລີກ)', edit: ['TRANSFER_SEND']),
  PermPage('ໂອນສາຂາ (ຮັບເຄື່ອງ)', edit: ['TRANSFER_RECEIVE']),
  PermPage('ຂໍອາໄຫຼ່ (ສົ່ງຄຳຂໍ)', edit: ['REQUEST_SEND']),
  PermPage('ຂໍອາໄຫຼ່ (ອະນຸມັດ)', edit: ['REQUEST_APPROVE']),
  PermPage('ນັບສະຕັອກ', edit: ['STOCK_COUNT']),
  PermPage('ສິນຄ້າ / BRAND / MODEL / ປະເພດ', edit: ['PRODUCT_MANAGE'], del: ['PRODUCT_MANAGE']),
  PermPage('Serial', edit: ['SERIAL_MANAGE'], del: ['SERIAL_MANAGE']),
  PermPage('ບ່ອນເກັບ', edit: ['BIN_MANAGE'], del: ['BIN_MANAGE']),
  PermPage('ແຜນຈັດຊື້ / Vendor', view: ['PO_MANAGE'], edit: ['PO_MANAGE'], del: ['PO_MANAGE']),
  PermPage('ຕູ້ ATM / Terminal / ສ້ອມ', view: ['ATM_MANAGE'], edit: ['ATM_MANAGE'], del: ['ATM_MANAGE']),
  PermPage('ສາຂາ', view: ['BRANCH_MANAGE'], edit: ['BRANCH_MANAGE'], del: ['BRANCH_MANAGE']),
  PermPage('ຜູ້ໃຊ້', view: ['USER_MANAGE'], edit: ['USER_MANAGE'], del: ['USER_MANAGE']),
  PermPage('ບົດບາດ / ຟັງຊັນ', view: ['ROLE_MANAGE'], edit: ['ROLE_MANAGE'], del: ['ROLE_MANAGE']),
];
