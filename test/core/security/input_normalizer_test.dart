import 'package:brainw4llet/core/security/input_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String n(String s) => InputNormalizer.normalize(s);

  group('InputNormalizer v1', () {
    test('converte para minúsculas', () {
      expect(n('MARIA'), 'maria');
    });

    test('remove acentos e cedilha', () {
      expect(n('Ação Ônibus Pão Até Avô'), 'acao onibus pao ate avo');
      expect(n('ÇÃÕÉÍÚÜÀ'), 'caoeiuua');
    });

    test('formas compostas e decompostas são equivalentes', () {
      expect(n('Jose\u0301'), n('José'));
      expect(n('José'), 'jose');
    });

    test('remove espaços das extremidades e colapsa internos', () {
      expect(n('   Maria    José   da  Silva  '), 'maria jose da silva');
    });

    test('trata tabs, quebras de linha e espaços Unicode como espaço', () {
      expect(n('São\tPaulo\n\r'), 'sao paulo');
      expect(n('rio\u00A0de\u2003janeiro\u3000'), 'rio de janeiro');
    });

    test('remove caracteres invisíveis (zero-width, controle)', () {
      expect(n('jo\u200Bse\u200D'), 'jose');
      expect(n('\uFEFFrex'), 'rex');
      expect(n('a\uFEFFb'), 'ab');
      expect(n('a\u0001b'), 'ab');
      expect(n('a \u200B b'), 'a b');
    });

    test('unifica formas de compatibilidade (largura total, ligaduras)', () {
      expect(n('ＲＥＸ'), 'rex');
      expect(n('ﬁlho'), 'filho');
    });

    test('translitera letras sem decomposição Unicode', () {
      expect(n('Straße'), 'strasse');
      expect(n('Øresund Æble Œuvre'), 'oresund aeble oeuvre');
      expect(n('Łódź'), 'lodz');
      expect(n('İstanbul'), 'istanbul');
    });

    test('mantém dígitos e pontuação', () {
      expect(n('Rua 7 de Setembro, nº 42'), 'rua 7 de setembro, no 42');
    });

    test('é idempotente', () {
      const inputs = ['  Ação  ', 'Straße', 'ＲＥＸ', 'İstanbul', '한국어'];
      for (final s in inputs) {
        expect(n(n(s)), n(s), reason: 'entrada #${inputs.indexOf(s)}');
      }
    });

    test('preserva scripts não latinos em forma NFC', () {
      expect(n('한국어'), '한국어');
    });

    test('entrada só com espaços vira string vazia', () {
      expect(n(' \t\n\u200B '), '');
    });
  });
}
