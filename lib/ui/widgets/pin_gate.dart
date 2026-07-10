import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_mode.dart';
import '../palette.dart';

/// Portão de PIN. Retorna `true` se o usuário digitou [kLivePin] corretamente,
/// `false` se cancelou.
///
/// Prevenção de acidente/curiosidade — não é segurança forte (ver plano).
/// Reutilizável pelo futuro portão de provisionamento por device.
Future<bool> showPinGate(
  BuildContext context, {
  String title = 'Modo Live',
  String subtitle = 'Digite o PIN para liberar o controle da transmissão.',
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _PinSheet(title: title, subtitle: subtitle),
    ),
  );
  return ok ?? false;
}

class _PinSheet extends StatefulWidget {
  final String title;
  final String subtitle;

  const _PinSheet({required this.title, required this.subtitle});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _error = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == kLivePin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = true);
      _controller.clear();
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, color: AppColors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 12,
                fontWeight: FontWeight.w600,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                errorText: _error ? 'PIN incorreto' : null,
              ),
              onChanged: (v) {
                if (_error) setState(() => _error = false);
                if (v.length == 4) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Liberar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
