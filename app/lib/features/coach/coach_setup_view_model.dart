// Coach setup and consent. The user picks an engine; a cloud engine then
// needs, before anything can leave the phone:
//
//   * an API key (pasted here, or already stored),
//   * the 18+ confirmation,
//   * for Gemini, "My key is on a paid project" (free keys train and allow
//     human review),
//   * and the affirmative "I agree — turn on …" tap, which stores the
//     consent time and version.
//
// Consent covers one provider and one mode: switching provider, or a cloud
// engine from "General only" to "Use my data", asks again. The key is kept
// in memory only until the agree tap stores it; it is never shown again.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../domain/coach/coach_contracts.dart';
import 'coach_providers.dart';

class CoachSetupState {
  const CoachSetupState({
    required this.saved,
    required this.keys,
    required this.engine,
    required this.model,
    required this.mode,
    this.keyDraft = '',
    this.adult = false,
    this.paid = false,
    this.busy = false,
    this.keyTail = const {},
    this.replacingKey = false,
  });

  /// What is stored now.
  final CoachSettings saved;

  /// Which cloud providers have a stored key.
  final Map<CoachProvider, bool> keys;

  /// The engine, model and mode chosen on this screen.
  final CoachProvider engine;
  final String? model;
  final CoachMode mode;

  /// The key being pasted (memory only; never shown back).
  final String keyDraft;
  final bool adult;
  final bool paid;
  final bool busy;

  /// Last four characters of a key stored in this session ("••••1234").
  final Map<CoachProvider, String> keyTail;

  /// The user asked to paste a new key over a stored one.
  final bool replacingKey;

  bool get cloud => engine != CoachProvider.offline;
  bool get hasKey => keys[engine] ?? false;

  /// The stored consent covers what is chosen here.
  bool get consented =>
      saved.provider == engine &&
      cloud &&
      saved.hasConsent &&
      (saved.consentVersion ?? 0) >= CoachCopy.consentVersion &&
      (saved.mode == mode || mode == CoachMode.generalOnly);

  /// The engine in use (stored), for the "In use" badge.
  CoachProvider get inUse =>
      saved.provider == CoachProvider.offline || saved.hasConsent
      ? saved.provider
      : CoachProvider.offline;

  /// Null when the draft is fine (or empty); else why it is not a key.
  String? get keyError =>
      keyDraft.trim().isEmpty ? null : keyProblem(engine, keyDraft);

  bool get draftOk => keyDraft.trim().isNotEmpty && keyError == null;

  /// A key will be there after the agree tap.
  bool get keyReady => draftOk || (hasKey && !replacingKey);

  /// Every gate for the agree button.
  bool get canAgree =>
      cloud &&
      !busy &&
      keyReady &&
      adult &&
      (engine != CoachProvider.gemini || paid);

  /// What still blocks the agree button, in words.
  List<String> get missing => [
    if (!keyReady) 'your API key',
    if (!adult) 'the 18+ box',
    if (engine == CoachProvider.gemini && !paid) 'the paid-project box',
  ];

  CoachSetupState copyWith({
    CoachSettings? saved,
    Map<CoachProvider, bool>? keys,
    CoachProvider? engine,
    String? model,
    CoachMode? mode,
    String? keyDraft,
    bool? adult,
    bool? paid,
    bool? busy,
    Map<CoachProvider, String>? keyTail,
    bool? replacingKey,
  }) => CoachSetupState(
    saved: saved ?? this.saved,
    keys: keys ?? this.keys,
    engine: engine ?? this.engine,
    model: model ?? this.model,
    mode: mode ?? this.mode,
    keyDraft: keyDraft ?? this.keyDraft,
    adult: adult ?? this.adult,
    paid: paid ?? this.paid,
    busy: busy ?? this.busy,
    keyTail: keyTail ?? this.keyTail,
    replacingKey: replacingKey ?? this.replacingKey,
  );
}

/// Why [key] cannot be a key for [p] (shape only; the provider decides the
/// rest on the first question), or null.
String? keyProblem(CoachProvider p, String key) {
  final k = key.trim();
  if (k.isEmpty) return 'Paste your key.';
  if (k.contains(RegExp(r'\s'))) return 'A key has no spaces.';
  switch (p) {
    case CoachProvider.claude:
      if (!k.startsWith('sk-ant-')) {
        return 'Anthropic keys start with “sk-ant-”.';
      }
      if (k.length < 24) return 'This key looks too short.';
    case CoachProvider.gemini:
      if (!k.startsWith('AIza')) return 'Gemini API keys start with “AIza”.';
      if (k.length < 30) return 'This key looks too short.';
    case CoachProvider.offline:
      return null;
  }
  return null;
}

class CoachSetupViewModel extends AsyncNotifier<CoachSetupState> {
  @override
  Future<CoachSetupState> build() async {
    final repo = ref.watch(coachRepositoryProvider);
    final s = await repo.settings();
    final keys = {
      for (final p in CoachProvider.values)
        if (p != CoachProvider.offline) p: await repo.hasApiKey(p),
    };
    return CoachSetupState(
      saved: s,
      keys: keys,
      engine: s.provider,
      model: s.model ?? CoachCopy.defaultModel(s.provider),
      mode: s.mode,
      adult: s.adultConfirmed,
    );
  }

  CoachRepository get _repo => ref.read(coachRepositoryProvider);

  void _set(CoachSetupState Function(CoachSetupState s) f) {
    final s = state.value;
    if (s != null) state = AsyncData(f(s));
  }

  void chooseEngine(CoachProvider p) => _set(
    (s) => s.engine == p
        ? s
        : s.copyWith(
            engine: p,
            model: s.saved.provider == p && s.saved.model != null
                ? s.saved.model
                : CoachCopy.defaultModel(p),
            mode: s.saved.provider == p ? s.saved.mode : CoachMode.useMyData,
            keyDraft: '',
            paid: false,
            replacingKey: false,
          ),
  );

  void setModel(String id) => _set((s) => s.copyWith(model: id));
  void setMode(CoachMode m) => _set((s) => s.copyWith(mode: m));
  void setKeyDraft(String k) => _set((s) => s.copyWith(keyDraft: k));
  void setAdult(bool v) => _set((s) => s.copyWith(adult: v));
  void setPaid(bool v) => _set((s) => s.copyWith(paid: v));
  void replaceKey() =>
      _set((s) => s.copyWith(replacingKey: true, keyDraft: ''));

  /// The agree tap. Stores the key (if one was pasted), then the provider,
  /// model, mode and consent in one save. Returns false when a gate is open.
  Future<bool> agree() async {
    final s = state.value;
    if (s == null || !s.canAgree) return false;
    state = AsyncData(s.copyWith(busy: true));
    try {
      var tail = s.keyTail;
      if (s.draftOk) {
        final key = s.keyDraft.trim();
        await _repo.saveApiKey(s.engine, key);
        tail = {...tail, s.engine: key.substring(key.length - 4)};
      }
      final next = s.saved.copyWith(
        enabled: true,
        provider: s.engine,
        model: s.model,
        mode: s.mode,
        consentAt: ref.read(clockProvider)(),
        consentVersion: CoachCopy.consentVersion,
        adultConfirmed: true,
      );
      await _repo.saveSettings(next);
      if (!ref.mounted) return true;
      state = AsyncData(
        s.copyWith(
          saved: next,
          keys: {...s.keys, s.engine: true},
          keyTail: tail,
          keyDraft: '',
          busy: false,
          replacingKey: false,
        ),
      );
      ref.invalidate(coachConfigProvider);
      return true;
    } catch (_) {
      if (ref.mounted) state = AsyncData(s.copyWith(busy: false));
      return false;
    }
  }

  /// Saves a change that needs no new consent: another model of the engine
  /// in use, or narrowing to "General only".
  Future<bool> saveChanges() async {
    final s = state.value;
    if (s == null || !s.consented) return false;
    final next = s.saved.copyWith(model: s.model, mode: s.mode);
    await _repo.saveSettings(next);
    if (!ref.mounted) return true;
    state = AsyncData(s.copyWith(saved: next));
    ref.invalidate(coachConfigProvider);
    return true;
  }

  /// Turns the cloud engine off and deletes the key (or switches an
  /// unconsented setup back to on-device).
  Future<bool> withdraw() async {
    final s = state.value;
    if (s == null) return false;
    state = AsyncData(s.copyWith(busy: true));
    try {
      final next = await withdrawCloud(_repo);
      if (!ref.mounted) return true;
      state = AsyncData(
        CoachSetupState(
          saved: next,
          keys: {for (final p in s.keys.keys) p: false},
          engine: CoachProvider.offline,
          model: null,
          mode: next.mode,
          adult: next.adultConfirmed,
        ),
      );
      ref.invalidate(coachConfigProvider);
      return true;
    } catch (_) {
      if (ref.mounted) {
        ref.invalidateSelf();
        ref.invalidate(coachConfigProvider);
      }
      return false;
    }
  }
}

final coachSetupProvider =
    AsyncNotifierProvider.autoDispose<CoachSetupViewModel, CoachSetupState>(
      CoachSetupViewModel.new,
      retry: noRetry,
    );
