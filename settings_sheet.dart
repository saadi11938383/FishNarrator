import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/studio_models.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class SettingsSheet extends StatefulWidget {
  final StudioController controller;

  const SettingsSheet({super.key, required this.controller});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final TextEditingController _keyCtrl = TextEditingController();
  bool _checking = false;
  bool _obscure = true;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    setState(() {
      _checking = true;
      _statusMessage = 'Verifying key with OpenRouter…';
      _isError = false;
    });
    try {
      final res = await widget.controller.saveAndCheckKey(_keyCtrl.text);
      _keyCtrl.clear();
      setState(() {
        _statusMessage = _formatAccount(res);
        _isError = false;
      });
    } on AppError catch (e) {
      setState(() {
        _statusMessage = e.message;
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _checkExisting() async {
    setState(() {
      _checking = true;
      _statusMessage = 'Checking daily allowance…';
      _isError = false;
    });
    try {
      final res = await widget.controller.checkCurrentAccount();
      setState(() {
        _statusMessage = _formatAccount(res);
        _isError = false;
      });
    } on AppError catch (e) {
      setState(() {
        _statusMessage = e.message;
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _formatAccount(AccountStatus status) {
    if (!status.configured) return 'No OpenRouter key saved yet.';
    final free = status.freeRequests;
    if (free != null) {
      final used = free['used'] ?? free['requests_used'];
      final limit = free['limit'] ?? free['requests_limit'];
      if (used != null && limit != null) {
        return 'Connected · Daily free requests: $used / $limit';
      }
      return 'Connected · Free quota info: $free';
    }
    return 'Connected · ${status.note.isNotEmpty ? status.note : "Key verified."}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final configured = widget.controller.isConfigured;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: StudioColors.tileBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.link, color: StudioColors.forest),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'OpenRouter connection',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Your key connects the studio to free speech models. It is stored securely on this device.',
            style: TextStyle(fontSize: 13, color: StudioColors.muted),
          ),
          const SizedBox(height: 14),
          const Text(
            'OpenRouter API key',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: configured
                  ? 'Enter a new key to replace the saved one'
                  : 'sk-or-v1-…',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://openrouter.ai/settings/keys'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Create a key'),
                style: TextButton.styleFrom(
                  foregroundColor: StudioColors.forest,
                  padding: EdgeInsets.zero,
                ),
              ),
              if (configured)
                TextButton(
                  onPressed: _checking ? null : _checkExisting,
                  style: TextButton.styleFrom(
                    foregroundColor: StudioColors.forest,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Check quota'),
                ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 12,
                color: _isError ? StudioColors.errorInk : StudioColors.forest,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (configured)
                TextButton(
                  onPressed: _checking
                      ? null
                      : () async {
                          await widget.controller.disconnectKey();
                          if (mounted) {
                            setState(() {
                              _statusMessage = 'Disconnected.';
                              _isError = false;
                            });
                          }
                        },
                  style: TextButton.styleFrom(foregroundColor: StudioColors.errorInk),
                  child: const Text('Remove key'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _checking ? null : _saveKey,
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.lime,
                  foregroundColor: StudioColors.limeInk,
                  side: const BorderSide(color: StudioColors.limeBorder),
                ),
                child: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Verify & Save',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
