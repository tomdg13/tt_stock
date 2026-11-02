import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();

  static const _kPhone = 'bio_phone';
  static const _kPin = 'bio_pin';
  static const _kEnabled = 'bio_enabled';

  static void _log(String m) => debugPrint('BIO: $m');

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();
      _log('supported=$supported canCheck=$canCheck types=$types');
      return supported && canCheck && types.isNotEmpty;
    } catch (e) {
      _log('isAvailable ERROR: $e');
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      final v = await _storage.read(key: _kEnabled);
      _log('isEnabled raw=$v');
      return v == 'true';
    } catch (e) {
      _log('isEnabled ERROR: $e');
      return false;
    }
  }

  static Future<void> enable(String phone, String pin) async {
    try {
      _log('enable phone="$phone" pinLen=${pin.length}');
      await _storage.write(key: _kPhone, value: phone);
      await _storage.write(key: _kPin, value: pin);
      await _storage.write(key: _kEnabled, value: 'true');
      _log('enable saved OK');
    } catch (e) {
      _log('enable ERROR: $e');
    }
  }

  static Future<void> disable() async {
    await _storage.delete(key: _kPhone);
    await _storage.delete(key: _kPin);
    await _storage.write(key: _kEnabled, value: 'false');
    _log('disabled');
  }

  static Future<({String phone, String pin})?> authenticateAndGetCredentials() async {
    try {
      _log('authenticate() start');
      final ok = await _auth.authenticate(
        localizedReason: 'ວາງນິ້ວມືເພື່ອເຂົ້າສູ່ລະບົບ',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      _log('authenticate() result=$ok');
      if (!ok) return null;
      final phone = await _storage.read(key: _kPhone);
      final pin = await _storage.read(key: _kPin);
      _log('stored phone="$phone" pinLen=${pin?.length}');
      if (phone == null || pin == null || phone.isEmpty || pin.isEmpty) {
        _log('credentials missing -> enable again');
        return null;
      }
      return (phone: phone, pin: pin);
    } catch (e) {
      _log('authenticate ERROR: $e');
      return null;
    }
  }
}
