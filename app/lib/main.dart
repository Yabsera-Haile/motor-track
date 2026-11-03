import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/repo.dart';
import 'theme.dart';
import 'ui/join_screen.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.isConfigured) {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabasePublishableKey);
  }
  runApp(const MotorTrackApp());
}

class MotorTrackApp extends StatelessWidget {
  const MotorTrackApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Motor Track',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: Config.isConfigured ? const Gate() : const _NotConfigured(),
  );
}

/// Signs the phone in, then shows Join or the app.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  final repo = Repo(Supabase.instance.client);
  late Future<void> _starting = _start();
  bool _joined = false;

  Future<void> _start() async {
    _joined = await repo.start() != null;
    if (_joined) await _enter();
  }

  Future<void> _enter() async {
    repo.subscribe();
    await repo.load();
  }

  @override
  void dispose() {
    repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _starting,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snap.hasError) {
        return _StartFailed(onRetry: () => setState(() => _starting = _start()));
      }
      if (!_joined) {
        return JoinScreen(
          repo: repo,
          onJoined: () async {
            await _enter();
            setState(() => _joined = true);
          },
        );
      }
      return AppShell(repo: repo);
    },
  );
}

class _StartFailed extends StatelessWidget {
  const _StartFailed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Palette.ink2),
            const SizedBox(height: 12),
            const Text("Can't reach the server", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Check your internet connection.', style: TextStyle(color: Palette.ink2)),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    ),
  );
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'This build has no server settings.\nRun with --dart-define-from-file=env/local.json',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
