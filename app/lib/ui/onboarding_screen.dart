import 'package:flutter/material.dart';

import '../prefs.dart';
import '../reader/reader_service.dart';
import '../theme.dart';

/// First launch: two intro pages, then one page per permission, each saying
/// why before Android asks. Permission pages only appear on Android.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Page { welcome, automatic, notifications, sms, battery }

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final _pager = PageController();
  int _index = 0;
  bool _busy = false;
  bool _smsRefused = false;

  // The battery page only matters on a Reader phone, so it appears once SMS is allowed.
  late List<_Page> _pages = [
    _Page.welcome,
    _Page.automatic,
    if (ReaderService.supported) ...[_Page.notifications, _Page.sms],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pager.dispose();
    super.dispose();
  }

  // Back from Android settings (battery prompt): move on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pages[_index] == _Page.battery && _busy) {
      _busy = false;
      _finish();
    }
  }

  void _next() {
    if (_index == _pages.length - 1) return _finish();
    _pager.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _finish() {
    AppPrefs.onboardingDone = true;
    widget.onDone();
  }

  Future<void> _allowNotifications() async {
    setState(() => _busy = true);
    try {
      await ReaderService.requestNotificationPermission();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _next();
  }

  Future<void> _allowSms() async {
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await ReaderService.requestSmsPermission();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!ok) {
      setState(() => _smsRefused = true);
      return;
    }
    AppPrefs.readerWanted = true;
    if (await ReaderService.isIgnoringBatteryOptimizations()) return _finish();
    setState(() => _pages = [..._pages, _Page.battery]);
    _next();
  }

  void _notThisPhone() {
    AppPrefs.readerWanted = false;
    _finish();
  }

  Future<void> _allowBattery() async {
    // Android shows its own dialog; we carry on when the app comes back.
    _busy = true;
    await ReaderService.requestIgnoreBatteryOptimizations();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= _index ? Palette.ink : Palette.control,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pager,
              // Permission pages move on through their buttons, not by swiping past them.
              physics: _pages[_index].index >= _Page.notifications.index
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              children: [for (final p in _pages) _page(p)],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _page(_Page p) => switch (p) {
    _Page.welcome => _Layout(
      icon: Icons.two_wheeler,
      title: 'Every bike\'s rent in one place',
      text:
          'See who has paid today, who still owes and how much has been collected. '
          'Everyone on the team sees the same numbers, live.',
      primary: ('Next', _next),
    ),
    _Page.automatic => _Layout(
      icon: Icons.mark_email_read_outlined,
      title: 'Payments record themselves',
      text:
          'The phone that receives MoMo reads the M-Money messages and marks drivers as paid. '
          'If someone is late or short, everyone gets an alert, and you can text the driver in English and Kinyarwanda.',
      primary: (ReaderService.supported ? 'Next' : 'Get started', _next),
    ),
    _Page.notifications => _Layout(
      icon: Icons.notifications_active_outlined,
      title: 'Turn on alerts',
      text:
          'Get a notification at 20:00 if a driver hasn\'t paid, the next morning if a day was missed, '
          'and when someone pays more than expected.',
      primary: ('Allow notifications', _allowNotifications),
      secondary: ('Not now', _next),
      busy: _busy,
    ),
    _Page.sms => _Layout(
      icon: Icons.sms_outlined,
      title: 'Is this the MoMo phone?',
      text:
          'If drivers pay into a MoMo number on this phone, Motor Track can read the M-Money messages and record '
          'their payments automatically. Only payments from registered drivers are shared. Your other messages stay on this phone.',
      primary: ('Yes, read M-Money messages', _allowSms),
      secondary: ('No, not this phone', _notThisPhone),
      busy: _busy,
      warning: _smsRefused
          ? 'Android didn\'t allow it. Open App info, tap ⋮ at the top right and choose "Allow restricted settings" '
                'if you see it, then go to Permissions → SMS → Allow. Or skip for now and set up the Reader later in Settings.'
          : null,
      extra: _smsRefused
          ? OutlinedButton(onPressed: ReaderService.openAppSettings, child: const Text('Open App info'))
          : null,
    ),
    _Page.battery => _Layout(
      icon: Icons.battery_charging_full,
      title: 'Keep the Reader running',
      text:
          'Phones like Tecno, Infinix and Samsung stop apps in the background to save battery. '
          'Allow Motor Track to keep checking for M-Money messages, even when it\'s closed.',
      primary: ('Allow', _allowBattery),
      secondary: ('Not now', _finish),
    ),
  };
}

class _Layout extends StatelessWidget {
  const _Layout({
    required this.icon,
    required this.title,
    required this.text,
    required this.primary,
    this.secondary,
    this.busy = false,
    this.warning,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String text;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;
  final bool busy;
  final String? warning;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(20)),
                  child: Icon(icon, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.3),
                ),
                const SizedBox(height: 12),
                Text(text, style: const TextStyle(fontSize: 16, color: Palette.ink2, height: 1.5)),
                if (warning != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Palette.warnBg, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      warning!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Palette.warn,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (extra != null) ...[const SizedBox(height: 12), extra!],
              ],
            ),
          ),
        ),
        FilledButton(
          onPressed: busy ? null : primary.$2,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                )
              : Text(primary.$1),
        ),
        if (secondary != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : secondary!.$2,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Palette.ink2),
            child: Text(secondary!.$1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ] else
          const SizedBox(height: 56),
      ],
    ),
  );
}
