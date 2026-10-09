import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_kantin/features/auth/domain/auth_validators.dart';

void main() {
  group('validateEmail', () {
    test('menolak kosong dan spasi saja', () {
      expect(validateEmail(null), 'Email wajib diisi.');
      expect(validateEmail('   '), 'Email wajib diisi.');
    });

    test('menolak format yang tidak valid', () {
      expect(validateEmail('kasir'), 'Format email tidak valid.');
      expect(validateEmail('kasir@kantin'), 'Format email tidak valid.');
      expect(validateEmail('kasir kantin@x.com'), 'Format email tidak valid.');
    });

    test('menerima email valid (spasi di tepi diabaikan)', () {
      expect(validateEmail('kasir@kantin.test'), isNull);
      expect(validateEmail('  kasir@kantin.test '), isNull);
    });
  });

  group('validatePassword', () {
    test('menolak kosong', () {
      expect(validatePassword(null), 'Kata sandi wajib diisi.');
      expect(validatePassword(''), 'Kata sandi wajib diisi.');
    });

    test('menerima isi apa pun, termasuk spasi', () {
      expect(validatePassword('rahasia-123'), isNull);
      expect(validatePassword(' '), isNull);
    });
  });
}
