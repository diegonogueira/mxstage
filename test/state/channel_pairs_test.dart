import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/state/channel_pairs.dart';

void main() {
  test('pares pelo nome (L/R ou nome igual, vizinhos ímpar+par)', () {
    final names = List.filled(32, '');
    names[6] = 'Over L';
    names[7] = 'Over R';
    names[12] = 'Keys L';
    names[13] = 'FX - SUB'; // não é par
    names[24] = 'Coral';
    names[25] = 'Coral';
    names[30] = 'PC';
    names[31] = 'PC';
    names[1] = 'Caixa cima'; // ch2+ch3 não são ímpar+par
    names[2] = 'Caixa cima';
    expect(namePairSuggestions(names), [
      [7, 8],
      [25, 26],
      [31, 32],
    ]);
  });
}
