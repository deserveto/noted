/// Per-user preferences. Keys deliberately match the server preference contract.
class SettingsModel {
  const SettingsModel({
    this.theme = 'light',
    this.textSize = 16.0,
    this.density = 'comfortable',
    this.reduceMotion = false,
    this.defaultCat = 'Personal',
    this.defaultColor = 'auto',
    this.spellcheck = true,
    this.wordCount = true,
    this.defaultView = 'grid',
    this.defaultSort = 'Last edited',
    this.weekStart = 'mon',
    this.calendarDots = true,
    this.aiEnabled = true,
    this.aiSources = true,
    this.aiLength = 'balanced',
    this.aiTone = 'friendly',
    this.aiHistory = true,
    this.requests = 'everyone',
    this.livePerm = 'edit',
    this.presence = true,
    this.reshare = false,
    this.nLive = true,
    this.nRequests = true,
    this.nCopies = true,
    this.nRecap = false,
    this.quietHours = false,
    this.appLock = false,
    this.analytics = false,
  });

  final String theme;
  final double textSize;
  final String density;
  final bool reduceMotion;
  final String defaultCat;
  final String defaultColor;
  final bool spellcheck;
  final bool wordCount;
  final String defaultView;
  final String defaultSort;
  final String weekStart;
  final bool calendarDots;
  final bool aiEnabled;
  final bool aiSources;
  final String aiLength;
  final String aiTone;
  final bool aiHistory;
  final String requests;
  final String livePerm;
  final bool presence;
  final bool reshare;
  final bool nLive;
  final bool nRequests;
  final bool nCopies;
  final bool nRecap;
  final bool quietHours;
  final bool appLock;
  final bool analytics;

  factory SettingsModel.fromMap(Map<String, dynamic> map) {
    return SettingsModel(
      theme:
          (map['theme'] is String ? map['theme'] as String : null) ?? 'light',
      textSize: ((map['textSize'] as num?)?.toDouble()) ?? 16.0,
      density: (map['density'] is String ? map['density'] as String : null) ??
          'comfortable',
      reduceMotion:
          (map['reduceMotion'] is bool ? map['reduceMotion'] as bool : null) ??
              false,
      defaultCat:
          (map['defaultCat'] is String ? map['defaultCat'] as String : null) ??
              'Personal',
      defaultColor: (map['defaultColor'] is String
              ? map['defaultColor'] as String
              : null) ??
          'auto',
      spellcheck:
          (map['spellcheck'] is bool ? map['spellcheck'] as bool : null) ??
              true,
      wordCount:
          (map['wordCount'] is bool ? map['wordCount'] as bool : null) ?? true,
      defaultView: (map['defaultView'] is String
              ? map['defaultView'] as String
              : null) ??
          'grid',
      defaultSort: (map['defaultSort'] is String
              ? map['defaultSort'] as String
              : null) ??
          'Last edited',
      weekStart:
          (map['weekStart'] is String ? map['weekStart'] as String : null) ??
              'mon',
      calendarDots:
          (map['calendarDots'] is bool ? map['calendarDots'] as bool : null) ??
              true,
      aiEnabled:
          (map['aiEnabled'] is bool ? map['aiEnabled'] as bool : null) ?? true,
      aiSources:
          (map['aiSources'] is bool ? map['aiSources'] as bool : null) ?? true,
      aiLength:
          (map['aiLength'] is String ? map['aiLength'] as String : null) ??
              'balanced',
      aiTone: (map['aiTone'] is String ? map['aiTone'] as String : null) ??
          'friendly',
      aiHistory:
          (map['aiHistory'] is bool ? map['aiHistory'] as bool : null) ?? true,
      requests:
          (map['requests'] is String ? map['requests'] as String : null) ??
              'everyone',
      livePerm:
          (map['livePerm'] is String ? map['livePerm'] as String : null) ??
              'edit',
      presence:
          (map['presence'] is bool ? map['presence'] as bool : null) ?? true,
      reshare:
          (map['reshare'] is bool ? map['reshare'] as bool : null) ?? false,
      nLive: (map['nLive'] is bool ? map['nLive'] as bool : null) ?? true,
      nRequests:
          (map['nRequests'] is bool ? map['nRequests'] as bool : null) ?? true,
      nCopies: (map['nCopies'] is bool ? map['nCopies'] as bool : null) ?? true,
      nRecap: (map['nRecap'] is bool ? map['nRecap'] as bool : null) ?? false,
      quietHours:
          (map['quietHours'] is bool ? map['quietHours'] as bool : null) ??
              false,
      appLock:
          (map['appLock'] is bool ? map['appLock'] as bool : null) ?? false,
      analytics:
          (map['analytics'] is bool ? map['analytics'] as bool : null) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'theme': theme,
        'textSize': textSize,
        'density': density,
        'reduceMotion': reduceMotion,
        'defaultCat': defaultCat,
        'defaultColor': defaultColor,
        'spellcheck': spellcheck,
        'wordCount': wordCount,
        'defaultView': defaultView,
        'defaultSort': defaultSort,
        'weekStart': weekStart,
        'calendarDots': calendarDots,
        'aiEnabled': aiEnabled,
        'aiSources': aiSources,
        'aiLength': aiLength,
        'aiTone': aiTone,
        'aiHistory': aiHistory,
        'requests': requests,
        'livePerm': livePerm,
        'presence': presence,
        'reshare': reshare,
        'nLive': nLive,
        'nRequests': nRequests,
        'nCopies': nCopies,
        'nRecap': nRecap,
        'quietHours': quietHours,
        'appLock': appLock,
        'analytics': analytics,
      };

  SettingsModel merge(Map<String, dynamic> changes) =>
      SettingsModel.fromMap({...toMap(), ...changes});
}
