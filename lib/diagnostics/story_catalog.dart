/// Stable identifiers are used in local story links. Fixtures never acquire real
/// controllers, permissions, microphones, model weights, or stored transcripts.
enum StoryFamily {
  indicator,
  settings,
  shortcut,
  models,
  output,
  onboarding,
  history,
  meetings,
  capture,
  voiceFilter,
  updates
}

class AppStory {
  final String id, group, title, state;
  final StoryFamily family;
  const AppStory(this.id, this.group, this.title, this.family, this.state);
  Uri get link => Uri(scheme: 'aurascribe', host: 'story', pathSegments: [id]);
  static AppStory? fromLink(String value) {
    if (!RegExp(r'^aurascribe://story/[a-z0-9-]+$').hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'aurascribe' ||
        uri.host != 'story' ||
        uri.pathSegments.length != 1 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return byId(uri.pathSegments.single);
  }

  static AppStory? byId(String id) {
    for (final story in appStories) {
      if (story.id == id) return story;
    }
    return null;
  }
}

const appStories = <AppStory>[
  AppStory('hud-ready', 'Indicators', 'Ready', StoryFamily.indicator, 'ready'),
  AppStory('hud-listening', 'Indicators', 'Listening', StoryFamily.indicator,
      'recording'),
  AppStory('hud-preparing', 'Indicators', 'Preparing', StoryFamily.indicator,
      'preparing'),
  AppStory('hud-transcribing', 'Indicators', 'Transcribing',
      StoryFamily.indicator, 'transcribing'),
  AppStory('hud-cleanup', 'Indicators', 'Grammar cleanup',
      StoryFamily.indicator, 'cleanup'),
  AppStory('hud-error', 'Indicators', 'Failure notice', StoryFamily.indicator,
      'error'),
  AppStory('hud-live-text', 'Indicators', 'Live transcript',
      StoryFamily.indicator, 'live'),
  AppStory('general', 'Settings', 'General', StoryFamily.settings, 'general'),
  AppStory('general-permissions', 'Settings', 'Missing permissions',
      StoryFamily.settings, 'permissions'),
  AppStory('general-microphone', 'Settings', 'Microphone level',
      StoryFamily.settings, 'microphone'),
  AppStory('general-no-microphone', 'Settings', 'Microphone unavailable',
      StoryFamily.settings, 'missing'),
  AppStory('general-audio', 'Settings', 'Audio ducking', StoryFamily.settings,
      'audio'),
  AppStory(
      'general-memory', 'Settings', 'Memory', StoryFamily.settings, 'memory'),
  AppStory('shortcut-left', 'Shortcuts', 'Left Option', StoryFamily.shortcut,
      'left'),
  AppStory('shortcut-right', 'Shortcuts', 'Right Option', StoryFamily.shortcut,
      'right'),
  AppStory('shortcut-recording', 'Shortcuts', 'Recording a shortcut',
      StoryFamily.shortcut, 'recording'),
  AppStory('shortcut-conflict', 'Shortcuts', 'Shortcut conflict',
      StoryFamily.shortcut, 'conflict'),
  AppStory('shortcut-saved', 'Shortcuts', 'Shortcut saved',
      StoryFamily.shortcut, 'saved'),
  AppStory(
      'models', 'Speech models', 'Model picker', StoryFamily.models, 'picker'),
  AppStory('models-downloading', 'Speech models', 'Downloading',
      StoryFamily.models, 'downloading'),
  AppStory('models-failed', 'Speech models', 'Download failed',
      StoryFamily.models, 'failed'),
  AppStory('models-installed', 'Speech models', 'Downloaded models',
      StoryFamily.models, 'installed'),
  AppStory('models-language', 'Speech models', 'Language fallback',
      StoryFamily.models, 'language'),
  AppStory('models-custom', 'Speech models', 'Custom model', StoryFamily.models,
      'custom'),
  AppStory('output', 'Output', 'Pipeline steps', StoryFamily.output, 'steps'),
  AppStory(
      'output-empty', 'Output', 'Empty pipeline', StoryFamily.output, 'empty'),
  AppStory('output-app', 'Output', 'Per-app rule', StoryFamily.output, 'app'),
  AppStory('output-preview', 'Output', 'Output preview', StoryFamily.output,
      'preview'),
  AppStory('output-unavailable', 'Output', 'Provider unavailable',
      StoryFamily.output, 'unavailable'),
  AppStory(
      'onboarding', 'Onboarding', 'Welcome', StoryFamily.onboarding, 'welcome'),
  AppStory('onboarding-permissions', 'Onboarding', 'Permissions',
      StoryFamily.onboarding, 'permissions'),
  AppStory('onboarding-denied', 'Onboarding', 'Permission denied',
      StoryFamily.onboarding, 'denied'),
  AppStory('onboarding-download', 'Onboarding', 'Downloading a model',
      StoryFamily.onboarding, 'downloading'),
  AppStory('onboarding-practice', 'Onboarding', 'Try dictation',
      StoryFamily.onboarding, 'practice'),
  AppStory('onboarding-ready', 'Onboarding', 'Ready to dictate',
      StoryFamily.onboarding, 'ready'),
  AppStory(
      'history', 'History', 'Saved dictations', StoryFamily.history, 'saved'),
  AppStory('history-empty', 'History', 'Empty history', StoryFamily.history,
      'empty'),
  AppStory('history-versions', 'History', 'Earlier versions',
      StoryFamily.history, 'versions'),
  AppStory('history-audio', 'History', 'Saved recording', StoryFamily.history,
      'audio'),
  AppStory('history-retention', 'History', 'History retention',
      StoryFamily.history, 'retention'),
  AppStory('history-delete', 'History', 'Delete confirmation',
      StoryFamily.history, 'delete'),
  AppStory(
      'meetings', 'Meetings', 'Saved meetings', StoryFamily.meetings, 'saved'),
  AppStory('meetings-empty', 'Meetings', 'Empty meetings', StoryFamily.meetings,
      'empty'),
  AppStory('meetings-recording', 'Meetings', 'Recording', StoryFamily.meetings,
      'recording'),
  AppStory('meetings-transcribing', 'Meetings', 'Transcribing',
      StoryFamily.meetings, 'transcribing'),
  AppStory('meetings-chapters', 'Meetings', 'Live chapters',
      StoryFamily.meetings, 'chapters'),
  AppStory('meetings-notes', 'Meetings', 'Meeting notes', StoryFamily.meetings,
      'notes'),
  AppStory(
      'meetings-rename', 'Meetings', 'Rename', StoryFamily.meetings, 'rename'),
  AppStory('meetings-failed', 'Meetings', 'Interrupted transcription',
      StoryFamily.meetings, 'failed'),
  AppStory('meetings-browser', 'Meetings', 'Browser-tab naming',
      StoryFamily.meetings, 'browser'),
  AppStory('meetings-permission', 'Meetings', 'System audio permission',
      StoryFamily.meetings, 'permission'),
  AppStory('capture', 'Capture & annotate', 'Annotation tools',
      StoryFamily.capture, 'draw'),
  AppStory('capture-empty', 'Capture & annotate', 'Empty captures',
      StoryFamily.capture, 'empty'),
  AppStory('capture-permission', 'Capture & annotate',
      'Screen recording permission', StoryFamily.capture, 'permission'),
  AppStory('capture-recording', 'Capture & annotate', 'Screen recording',
      StoryFamily.capture, 'recording'),
  AppStory('capture-replay', 'Capture & annotate', 'Replay buffer',
      StoryFamily.capture, 'replay'),
  AppStory('voice-filter', 'Voice filter', 'Voice filter',
      StoryFamily.voiceFilter, 'active'),
  AppStory('voice-filter-muted', 'Voice filter', 'Muted',
      StoryFamily.voiceFilter, 'muted'),
  AppStory('voice-filter-driver', 'Voice filter',
      'Virtual microphone unavailable', StoryFamily.voiceFilter, 'driver'),
  AppStory('updates-checking', 'Updates', 'Checking for updates',
      StoryFamily.updates, 'checking'),
  AppStory('updates-downloading', 'Updates', 'Downloading update',
      StoryFamily.updates, 'downloading'),
  AppStory(
      'updates-ready', 'Updates', 'Update ready', StoryFamily.updates, 'ready'),
  AppStory('updates-failed', 'Updates', 'Update failed', StoryFamily.updates,
      'failed'),
];
