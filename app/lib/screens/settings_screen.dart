import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient();
  final _urlController = TextEditingController();
  String? _name;
  String? _email;

  @override
  void initState() {
    super.initState();
    _api.baseUrl().then((url) {
      if (mounted) setState(() => _urlController.text = url);
    });
    AuthService.instance.name().then((n) {
      if (mounted) setState(() => _name = n);
    });
    AuthService.instance.email().then((e) {
      if (mounted) setState(() => _email = e);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Mark'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await AuthService.instance.setName(name);
    if (mounted) setState(() => _name = name);
    _snack('Name updated.');
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final fresh = TextEditingController();
    final confirm = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Current password'),
            ),
            TextField(
              controller: fresh,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    if (fresh.text.length < 6) {
      _snack('New password must be at least 6 characters.');
      return;
    }
    if (fresh.text != confirm.text) {
      _snack('New passwords do not match.');
      return;
    }
    final ok = await AuthService.instance
        .changePassword(current: current.text, newPassword: fresh.text);
    _snack(ok ? 'Password changed.' : 'Current password is incorrect.');
  }

  Future<void> _logOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'Your handles, flashcards and reminders stay on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.instance.logOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Account', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Name'),
                  subtitle: Text(_name ?? 'Not set'),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _editName,
                ),
                if (_email != null)
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Email'),
                    subtitle: Text(_email!),
                  ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  onTap: _changePassword,
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text(
                    'Log out',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: _logOut,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Backend', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              helperText:
                  'Android emulator: http://10.0.2.2:3000\nPhysical device: use your computer\'s LAN IP on port 3000',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await _api.setBaseUrl(_urlController.text.trim());
              _snack('Backend URL saved');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
