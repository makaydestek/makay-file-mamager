import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makay_file_manager/services/ntlm.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('MD4 (RFC 1320 bilinen vektörleri)', () {
    test('bos dize', () {
      expect(_toHex(md4(utf8.encode(''))), '31d6cfe0d16ae931b73c59d7e0c089c0');
    });
    test('"a"', () {
      expect(_toHex(md4(utf8.encode('a'))), 'bde52cb31de33e46245e05fbdbd6fb24');
    });
    test('"abc"', () {
      expect(_toHex(md4(utf8.encode('abc'))), 'a448017aaf21d8525fc10ae87aa6729d');
    });
    test('"message digest"', () {
      expect(_toHex(md4(utf8.encode('message digest'))),
          'd9130a8164549fe818874806e1c7014b');
    });
    test('"abcdefghijklmnopqrstuvwxyz"', () {
      expect(_toHex(md4(utf8.encode('abcdefghijklmnopqrstuvwxyz'))),
          'd79e1c308aa5bbcdeea8ed63df412da9');
    });
    test('62 karakterlik alfabe + rakamlar', () {
      expect(
        _toHex(md4(utf8.encode(
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'))),
        '043f8582f241db351ce627e153e7f0e4',
      );
    });
    test('80 rakam ("1234567890" x8)', () {
      expect(
        _toHex(md4(utf8.encode('1234567890123456789012345678901234567890'
            '1234567890123456789012345678901234567890'))),
        'e33b4ddc9c38f2199c3e7b164fcc0536',
      );
    });
  });

  group('NTLM', () {
    test('NTLM parola özeti (MD4/UTF-16LE)', () {
      // Yaygın bilinen vektör: NT hash("Password")
      expect(_toHex(ntlmHash('Password')), 'a4f49c406510bdcab6824ee7c30fd852');
    });

    test('tip-1 mesaji yapisal dogrulama', () {
      final t1 = ntlmType1();
      expect(t1.length, 32);
      expect(_toHex(t1.sublist(0, 8)), '4e544c4d53535000'); // "NTLMSSP\0"
      final bd = ByteData.sublistView(t1);
      expect(bd.getUint32(8, Endian.little), 1); // tip
      expect(bd.getUint32(12, Endian.little) & 0x00000200, 0x00000200); // NTLM
    });

    test('SPNEGO NegTokenInit tip-1 mesajini sarar', () {
      final blob = spnegoNegTokenInit(ntlmType1());
      expect(blob.first, 0x60); // GSS-API
      // NTLM OID'si ve tip-1 mesaji içinde bulunur.
      expect(_toHex(blob).contains('060a2b060104018237020104'), isTrue);
      expect(_toHex(blob).contains('4e544c4d5353500001000000'), isTrue);
    });

    test('tip-2 challenge parser + tip-3 uretimi', () {
      // Mini sunucunun sabit challenge mesajı (smb_server.dart ile aynı).
      final challengeMsg = Uint8List.fromList([
        0x4e, 0x54, 0x4c, 0x4d, 0x53, 0x53, 0x50, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00,
        0x07, 0x82, 0x0a, 0x00,
        0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);
      final wrapped = Uint8List.fromList([
        0xa1, 0x2e, 0x30, 0x2c, 0xa0, 0x2a, 0x04, 0x28,
        ...challengeMsg,
      ]);
      final c = NtlmChallenge.parse(wrapped);
      expect(_toHex(c.serverChallenge), 'efcdab8967452301');
      expect(c.targetInfo, isEmpty);

      final t3 = ntlmType3(
        username: 'kullanici',
        domain: '',
        workstation: 'MAKAY',
        password: 'sifre',
        challenge: c,
      );
      expect(_toHex(t3.sublist(0, 8)), '4e544c4d53535000');
      final bd = ByteData.sublistView(t3);
      expect(bd.getUint32(8, Endian.little), 3); // tip
      // NTLMv2 yaniti: 16 bayt proof + blob (blob 0x0101 ile başlar).
      final ntLen = bd.getUint16(20, Endian.little);
      expect(ntLen, greaterThan(16 + 8 + 8 + 4)); // proof + minimal blob
      expect(t3[t3.length - 4], 0x00); // blob sonu: reserved
    });

    test('NTLMv2 MS-NLMP ornegi (4.2.4)', () {
      // Parola "Password", kullanici "User", alan "Domain".
      final ntHash = ntlmHash('Password');
      expect(_toHex(ntHash), 'a4f49c406510bdcab6824ee7c30fd852');

      // NTOWFv2 (yayınlanmış vektör): HMAC-MD5(NT-özet, UTF16("USER"+"Domain")).
      final key = ntlmV2Key(ntHash, 'User', 'Domain');
      expect(_toHex(key), '0c868a403bfd7a93a3001ef22ef02e3f');

      final serverChallenge = _hex('0123456789abcdef');
      // Resmi vektör hedef bilgisi: NbDomain "Domain", NbComputer "Server".
      final targetInfo = _hex(
        '02000c0044006f006d00610069006e00' // Domain
        '01000c00530065007200760065007200' // Server
        '00000000', // EOL
      );
      final clientChallenge = _hex('aaaaaaaaaaaaaaaa');
      // Vektör timestamp = 0 (1601-01-01).
      final time = DateTime.fromMicrosecondsSinceEpoch(
        -11644473600000000,
        isUtc: true,
      );
      final resp = ntlmV2Response(
        responseKey: key,
        serverChallenge: serverChallenge,
        targetInfo: targetInfo,
        time: time,
        clientChallenge: clientChallenge,
      );
      // MS-NLMP 4.2.4.2: NTProofStr
      expect(
        _toHex(resp.sublist(0, 16)),
        '68cd0ab851e51c96aabc927bebef6a1c',
      );
    });
  });
}
