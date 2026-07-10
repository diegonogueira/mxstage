import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../palette.dart';

/// A tappable list of the mixer's return buses, labelled by name when the
/// mixer provides one. Shared by the connect flow and the in-mix switcher.
///
/// [excludeBus], when set, hides that bus from the list — used in Stage mode to
/// keep the designated Live (broadcast) bus out of a musician's reach.
///
/// [onLive], when set, adds a distinct PIN-gated "Live" entry at the top of the
/// list (the way one enters the transmission mix). [onLiveEdit], when also set,
/// adds a small button on that entry to re-designate which bus is the Live bus.
class BusPickerList extends StatelessWidget {
  final MixerClient client;
  final ValueChanged<int> onPick;
  final bool shrinkWrap;
  final int? excludeBus;
  final VoidCallback? onLive;
  final VoidCallback? onLiveEdit;

  const BusPickerList({
    super.key,
    required this.client,
    required this.onPick,
    this.shrinkWrap = false,
    this.excludeBus,
    this.onLive,
    this.onLiveEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        // Bus numbers to show (1-based), minus the excluded one.
        final buses = [
          for (var i = 0; i < client.busNames.length; i++)
            if (i + 1 != excludeBus) i + 1,
        ];
        final hasLive = onLive != null;
        return ListView.builder(
          shrinkWrap: shrinkWrap,
          itemCount: buses.length + (hasLive ? 1 : 0),
          itemBuilder: (context, index) {
            if (hasLive && index == 0) {
              return _LiveEntryTile(onTap: onLive!, onEdit: onLiveEdit);
            }
            final bus = buses[index - (hasLive ? 1 : 0)];
            final name = client.busNames[bus - 1];
            final hasName = name != null && name.isNotEmpty;
            final selected = bus == client.busIndex;
            return ListTile(
              dense: true,
              leading: Text(
                bus.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: selected ? AppColors.blue : Colors.white38,
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
                      color: AppColors.blue, size: 20)
                  : null,
              onTap: () => onPick(bus),
            );
          },
        );
      },
    );
  }
}

/// Bottom-sheet bus switcher used from inside the mix screen. [title]/[subtitle],
/// [icon] and [accent] adapt to the current mode; [excludeBus] hides the Live
/// bus in Stage. [onPicked] overrides the default `client.setBus`.
Future<void> showBusPicker(
  BuildContext context,
  MixerClient client, {
  ValueChanged<int>? onPicked,
  int? excludeBus,
  VoidCallback? onLive,
  VoidCallback? onLiveEdit,
  String title = 'Meu bus de retorno',
  String subtitle = 'Trocar de bus desliga o Auto-Mix por segurança.',
  IconData icon = Icons.headphones,
  Color accent = AppColors.blue,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
          Flexible(
            child: BusPickerList(
              client: client,
              shrinkWrap: true,
              excludeBus: excludeBus,
              onLive: onLive == null
                  ? null
                  : () {
                      Navigator.of(sheetCtx).pop();
                      onLive();
                    },
              onLiveEdit: onLiveEdit == null
                  ? null
                  : () {
                      Navigator.of(sheetCtx).pop();
                      onLiveEdit();
                    },
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

/// Distinct PIN-gated entry for the transmission mix, shown atop the bus list.
///
/// The whole tile enters Live; [onEdit], when set, adds a small button to
/// re-designate which bus is the Live (broadcast) bus. Colour comes from the
/// ListTile's own `tileColor`/`shape` so ink splashes stay visible (a wrapping
/// coloured Container would make them invisible and trip a framework warning).
class _LiveEntryTile extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _LiveEntryTile({required this.onTap, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: ListTile(
        dense: true,
        tileColor: AppColors.red.withAlpha(18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.red.withAlpha(90)),
        ),
        leading: const Icon(Icons.podcasts, color: AppColors.red),
        title: const Text(
          'Live',
          style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Mix da transmissão — pede senha',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.tune, color: AppColors.red, size: 18),
                tooltip: 'Trocar o bus da Live',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
              ),
            const Icon(Icons.lock_outline, color: AppColors.red, size: 18),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
