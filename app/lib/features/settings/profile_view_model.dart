// Profile view-model: a draft of UserProfile, validated field by field, and
// the save (which recomputes every score in the repository).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/engine/engine.dart';
import '../../domain/models.dart';
import '../../app/platform_services.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.saved,
    this.birthYear = '',
    this.sex = Sex.unspecified,
    this.maxHr = '',
    this.weight = '',
    this.saving = false,
    this.justSaved = false,
  });

  factory ProfileDraft.from(UserProfile p) => ProfileDraft(
    saved: p,
    birthYear: p.birthYear?.toString() ?? '',
    sex: p.sex,
    maxHr: p.maxHrOverride?.round().toString() ?? '',
    weight: p.weightKg == null ? '' : _num(p.weightKg!),
  );

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  final UserProfile saved;
  final String birthYear, maxHr, weight;
  final Sex sex;
  final bool saving, justSaved;

  int? get birthYearValue => int.tryParse(birthYear.trim());
  double? get maxHrValue => double.tryParse(maxHr.trim());
  double? get weightValue =>
      double.tryParse(weight.trim().replaceAll(',', '.'));

  /// Null = valid (or empty).
  String? birthYearError(DateTime now) {
    if (birthYear.trim().isEmpty) return null;
    final y = birthYearValue;
    if (y == null || y < now.year - 100 || y > now.year - 18) {
      return 'Airlog is for adults. Enter a year between '
          '${now.year - 100} and ${now.year - 18}';
    }
    return null;
  }

  String? get maxHrError {
    if (maxHr.trim().isEmpty) return null;
    final v = maxHrValue;
    if (v == null || !v.isFinite || v < 100 || v > 240) {
      return 'Enter 100 to 240 bpm';
    }
    return null;
  }

  String? get weightError {
    if (weight.trim().isEmpty) return null;
    final v = weightValue;
    if (v == null || !v.isFinite || v < 30 || v > 300) {
      return 'Enter 30 to 300 kg';
    }
    return null;
  }

  bool valid(DateTime now) =>
      birthYearError(now) == null && maxHrError == null && weightError == null;

  UserProfile toProfile() => UserProfile(
    birthYear: birthYear.trim().isEmpty ? null : birthYearValue,
    sex: sex,
    maxHrOverride: maxHr.trim().isEmpty ? null : maxHrValue,
    weightKg: weight.trim().isEmpty ? null : weightValue,
  );

  bool get dirty {
    final a = toProfile(), b = saved;
    return a.birthYear != b.birthYear ||
        a.sex != b.sex ||
        a.maxHrOverride != b.maxHrOverride ||
        a.weightKg != b.weightKg;
  }

  /// The max HR zones would use with this draft (override or Tanaka).
  double predictedMaxHr(DateTime now) => Engine.maxHrFor(
    UserProfile(birthYear: birthYear.trim().isEmpty ? null : birthYearValue),
    now,
  );

  ProfileDraft copyWith({
    UserProfile? saved,
    String? birthYear,
    Sex? sex,
    String? maxHr,
    String? weight,
    bool? saving,
    bool? justSaved,
  }) => ProfileDraft(
    saved: saved ?? this.saved,
    birthYear: birthYear ?? this.birthYear,
    sex: sex ?? this.sex,
    maxHr: maxHr ?? this.maxHr,
    weight: weight ?? this.weight,
    saving: saving ?? this.saving,
    justSaved: justSaved ?? false,
  );
}

class ProfileController extends AsyncNotifier<ProfileDraft> {
  @override
  Future<ProfileDraft> build() async =>
      ProfileDraft.from(await ref.watch(healthRepositoryProvider).profile());

  void _edit(ProfileDraft Function(ProfileDraft d) f) {
    final d = state.value;
    if (d != null) state = AsyncData(f(d));
  }

  void setBirthYear(String v) => _edit((d) => d.copyWith(birthYear: v));
  void setSex(Sex v) => _edit((d) => d.copyWith(sex: v));
  void setMaxHr(String v) => _edit((d) => d.copyWith(maxHr: v));
  void setWeight(String v) => _edit((d) => d.copyWith(weight: v));

  /// Saves and recomputes every score. Returns false if invalid or failed.
  Future<bool> save() async {
    final d = state.value;
    final now = ref.read(clockProvider)();
    if (d == null || !d.valid(now) || d.saving) return false;
    state = AsyncData(d.copyWith(saving: true));
    final p = d.toProfile();
    try {
      await ref.read(healthRepositoryProvider).saveProfile(p);
    } catch (_) {
      if (ref.mounted) state = AsyncData(d.copyWith(saving: false));
      return false;
    }
    if (!ref.mounted) return true;
    state = AsyncData(d.copyWith(saved: p, saving: false, justSaved: true));
    return true;
  }
}

final profileControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfileController, ProfileDraft>(
      ProfileController.new,
      retry: noRetry,
    );
