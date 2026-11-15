/// A call name derived only from a microphone-active browser's visible page.
/// Full URLs, query strings, and fragment tokens are never persisted.
class BrowserCall {
  final String application, service, title, host;
  const BrowserCall(
      {required this.application,
      required this.service,
      required this.title,
      required this.host});

  static const browserIds = {
    'com.apple.Safari',
    'com.apple.SafariTechnologyPreview',
    'com.google.Chrome',
    'com.google.Chrome.beta',
    'com.google.Chrome.dev',
    'com.google.Chrome.canary',
    'org.chromium.Chromium',
    'com.brave.Browser',
    'com.brave.Browser.beta',
    'com.brave.Browser.nightly',
    'com.microsoft.edgemac',
    'com.microsoft.edgemac.Beta',
    'com.microsoft.edgemac.Dev',
    'com.microsoft.edgemac.Canary',
    'company.thebrowser.Browser',
    'com.vivaldi.Vivaldi',
    'com.operasoftware.Opera',
    'org.mozilla.firefox',
    'org.mozilla.firefoxdeveloperedition',
    'app.zen-browser.zen',
  };
  static const sites = {
    'meet.google.com': 'Google Meet',
    'banshee.app': 'Banshee',
    'web.whatsapp.com': 'WhatsApp',
    'app.v2.gather.town': 'Gather',
    'app.gather.town': 'Gather',
    'voice.google.com': 'Google Voice',
    'messenger.com': 'Messenger',
    'teams.live.com': 'Teams',
    'teams.microsoft.com': 'Teams',
    'facetime.apple.com': 'FaceTime',
    'web.groupme.com': 'GroupMe',
  };
  static BrowserCall? fromPage(String application, Map<dynamic, dynamic> page) {
    if (!browserIds.contains(application)) return null;
    final url = Uri.tryParse(page['url'] as String? ?? '');
    final rawTitle = page['title'] as String? ?? '';
    var host = url?.host
            .toLowerCase()
            .replaceFirst(RegExp(r'\.$'), '')
            .replaceFirst(RegExp(r'^www\.'), '') ??
        '';
    var service =
        (url?.scheme == 'https' || url?.scheme == 'http') ? sites[host] : null;
    if (host == 'meet.google.com' &&
        (url!.path.replaceAll('/', '').isEmpty ||
            const ['/landing', '/new', '/about']
                .any((p) => url.path == p || url.path.startsWith('$p/')))) {
      return null;
    }
    var title = rawTitle.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    for (final suffix in const [
      ' - Audio playing - Brave',
      ' - Brave Browser',
      ' - Google Chrome',
      ' — Mozilla Firefox',
      ' - Microsoft Edge',
      ' - Safari',
      ' - Arc',
      ' - Vivaldi',
      ' - Brave'
    ]) {
      if (title.endsWith(suffix)) {
        title = title.substring(0, title.length - suffix.length).trim();
      }
    }
    // AX window titles still identify Meet when a background browser hides URLs.
    final meetPrefix = RegExp(r'^Meet\s[-–—]\s+');
    if (service == null && host.isEmpty && meetPrefix.hasMatch(title)) {
      host = 'meet.google.com';
      service = 'Google Meet';
    }
    if (service == null) return null;
    if (service == 'Google Meet') title = title.replaceFirst(meetPrefix, '');
    for (final suffix in [
      ' - $service',
      ' | $service',
      ' – $service',
      ' — $service'
    ]) {
      if (title.endsWith(suffix)) {
        title = title.substring(0, title.length - suffix.length).trim();
      }
    }
    if (title.isEmpty ||
        title.toLowerCase() == service.toLowerCase() ||
        (service == 'Google Meet' &&
            RegExp(r'^[a-z]{3}-[a-z]{4}-[a-z]{3}$').hasMatch(title))) {
      title = '$service meeting';
    }
    return BrowserCall(
        application: application,
        service: service,
        title: String.fromCharCodes(title.runes.take(160)),
        host: host);
  }

  Map<String, String> toMetadata() => {
        'application': application,
        'service': service,
        'host': host,
      };
}

/// Bridges temporary AX/Automation failures, without leaking names across apps.
class BrowserCallCache {
  final _entries = <String, ({BrowserCall call, DateTime seen})>{};
  void retainApplications(Set<String> active) =>
      _entries.removeWhere((id, _) => !active.contains(id));
  BrowserCall? update(String id, Map<dynamic, dynamic> page, DateTime now) {
    final call = BrowserCall.fromPage(id, page);
    if (call != null) {
      _entries[id] = (call: call, seen: now);
      return call;
    }
    if ((page['url'] as String? ?? '').isNotEmpty ||
        (page['title'] as String? ?? '').isNotEmpty) {
      _entries.remove(id);
      return null;
    }
    final previous = _entries[id];
    if (previous != null &&
        now.difference(previous.seen) <= const Duration(seconds: 60)) {
      return previous.call;
    }
    _entries.remove(id);
    return null;
  }
}
