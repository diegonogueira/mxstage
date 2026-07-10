import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';

/// A tappable list of the mixer's return buses, labelled by name when the
/// mixer provides one. Shared by the connect flow and the in-mix switcher.
class BusPickerList extends StatelessWidget {
  final MixerClient client;
  final ValueChanged<int> onPick;
  final bool shrinkWrap;

  const BusPickerList({
    super.key,
    required this.client,
    required this.onPick,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        return ListView.builder(
          shrinkWrap: shrinkWrap,
          itemCount: client.busNames.length,
          itemBuilder: (context, i) {
            final bus = i + 1;
            final name = client.busNames[i];
            final hasName = name != null && name.isNotEmpty;
            final selected = bus == client.busIndex;
            return ListTile(
              dense: true,
              leading: Text(
                bus.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: selected ? const Color(0xFF2AAF8E) : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              title: Text(
                hasName ? name : 'Bus $bus',
                style: TextStyle(
                  color: hasName ? Colors.white : Colors.white38,
                  fontStyle: hasName ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_circle,
                      color: Color(0xFF2AAF8E), size: 20)
                  : null,
              onTap: () => onPick(bus),
            );
          },
        );
      },
    );
  }
}

/// Bottom-sheet bus switcher used from inside the mix screen.
Future<void> showBusPicker(
  BuildContext context,
  MixerClient client, {
  ValueChanged<int>? onPicked,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(Icons.headphones, color: Color(0xFF2AAF8E), size: 20),
                SizedBox(width: 8),
                Text(
                  'Meu bus de retorno',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Trocar de bus desliga o Auto-Mix por segurança.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
          Flexible(
            child: BusPickerList(
              client: client,
              shrinkWrap: true,
              onPick: (bus) {
                Navigator.of(sheetCtx).pop();
                if (onPicked != null) {
                  onPicked(bus);
                } else {
                  client.setBus(bus);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
