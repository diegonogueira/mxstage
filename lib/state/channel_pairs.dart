import 'channel_mapper.dart';

/// Pares estéreo sugeridos pelo **nome** que o operador digitou: "Over L" /
/// "Over R", "Keys L" / "Keys R", ou dois canais vizinhos com o mesmo nome
/// ("PC" / "PC", "Coral" / "Coral"). Só canais vizinhos (ímpar + par seguinte,
/// como a X32 faz o link). Devolve pares `[a, b]` com `a < b`.
List<List<int>> namePairSuggestions(List<String> names) {
  String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final side = RegExp(r'^(.*?)[\s\-_]*(l|r|left|right|esq|dir)$');
  final out = <List<int>>[];
  for (var i = 0; i + 1 < names.length; i += 2) {
    final a = norm(names[i]), b = norm(names[i + 1]);
    if (ChannelMapper.isUnnamed(a) || ChannelMapper.isUnnamed(b)) continue;
    if (a == b) {
      out.add([i + 1, i + 2]);
      continue;
    }
    final ma = side.firstMatch(a), mb = side.firstMatch(b);
    if (ma == null || mb == null) continue;
    final sa = ma.group(2)!, sb = mb.group(2)!;
    final left = {'l', 'left', 'esq'}, right = {'r', 'right', 'dir'};
    if (ma.group(1)!.trim() == mb.group(1)!.trim() &&
        ma.group(1)!.trim().isNotEmpty &&
        left.contains(sa) &&
        right.contains(sb)) {
      out.add([i + 1, i + 2]);
    }
  }
  return out;
}
