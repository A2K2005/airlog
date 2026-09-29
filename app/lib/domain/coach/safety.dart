// Deterministic input router. Runs BEFORE any model call: on a match the
// coach answers with fixed, calm copy, marked `safety: true`, with no
// network call and no tool call (research/06 §8.2 item 5).
//
//   * emergencies (chest pain, fainting, severe breathlessness, stroke
//     signs, a very high/low resting HR or racing heart with symptoms,
//     bleeding or pain in pregnancy) → emergency services;
//   * self-harm → crisis lines;
//   * medication, supplement or dosing questions → a pharmacist or doctor;
//   * eating-disorder signals → support and a doctor;
//   * pregnancy (no emergency signs) → a midwife or doctor;
//   * a user under 18 → the coach is for adults.
//
// Deliberately narrow: "why is my heart rate high?", "my chest strap
// disconnected", "does caffeine hurt my sleep?" or "how many calories did I
// burn?" are ordinary questions. The eval suite (test/evals) holds recall
// on red flags at 100% and false positives on benign questions at ≤ 2%.
// Pure Dart.

enum RedFlag {
  chestPain,
  fainting,
  breathless,
  stroke,
  selfHarm,
  heartRateWithSymptoms,
  pregnancy,

  /// Medication, supplement or dosing question (not an emergency).
  medication,

  /// Disordered-eating signal (not an emergency).
  eatingDisorder,

  /// Pregnancy question without emergency signs.
  pregnancyInfo,

  /// The user says they are under 18.
  minor,
}

class SafetyVerdict {
  const SafetyVerdict(this.flag, this.message);
  final RedFlag flag;
  final String message;

  /// Emergency / crisis copy (vs a calm clinician pointer).
  bool get urgent => switch (flag) {
    RedFlag.medication ||
    RedFlag.eatingDisorder ||
    RedFlag.pregnancyInfo ||
    RedFlag.minor => false,
    _ => true,
  };
}

abstract final class SafetyCheck {
  static final _chest = RegExp(
    r"chest (?:pain|pressure|tightness|is tight|feels tight|hurts|is hurting|"
    r"ache|aches|aching|discomfort|squeezing)|pain in (?:my|the) chest|"
    r"tight(?:ness)? in (?:my|the) chest|pressure in (?:my|the) chest|"
    r"crushing (?:chest|pain)|heart attack|pain (?:down|in) my (?:left )?arm "
    r"and (?:jaw|chest)",
  );
  static final _faint = RegExp(
    r"\b(?:faint(?:ed|ing)?|passed out|pass out|passing out|blacked out|"
    r"black out|lost consciousness|losing consciousness|syncope)\b",
  );
  static final _breath = RegExp(
    r"can(?:'|no)?t breathe|cannot breathe|struggling to breathe|"
    r"difficulty breathing|trouble breathing|hard to breathe|gasping for air|"
    r"can(?:'|no)?t (?:catch|get) my breath|"
    r"severe(?:ly)? (?:short of breath|breathless)|"
    r"short(?:ness)? of breath (?:at rest|while resting|lying down|suddenly)|"
    r"sudden(?:ly)? (?:short of breath|breathless)|breathless at rest|"
    r"(?:out of breath|breathless|short of breath|can'?t catch my breath)"
    r"[^.?!]{0,30}(?:sitting|resting|at rest|lying|doing nothing|in bed)",
  );
  static final _stroke = RegExp(
    r"having a stroke|signs? of (?:a )?stroke|stroke symptoms|"
    r"(?:face|mouth)[^.?!]{0,25}droop|droop(?:ing|y|s)?[^.?!]{0,20}(?:face|"
    r"mouth|one side|eye)|\bslurr(?:ed|ing)\b|"
    r"can(?:'|no)?t (?:speak|lift my arm)|"
    r"(?:numb|numbness|weak|weakness) (?:on|in|down) one side|"
    r"(?:half|one side of|side of) my (?:face|body)[^.?!]{0,20}(?:numb|weak|"
    r"droop|tingl)|(?:face|arm|leg)[^.?!]{0,12}(?:went|go|going|gone|is|"
    r"feels?) (?:suddenly )?numb|"
    r"sudden(?:ly)? (?:confused|confusion|numb|numbness|weakness|blind|"
    r"vision loss|lost vision|trouble speaking)|"
    r"(?:lost|losing|lose) (?:the |my |all |some |part of (?:the |my )?)?"
    r"(?:vision|sight)|(?:vision|sight)[^.?!]{0,20}(?:has gone|went|gone|"
    r"disappeared|blacked out)|part of my vision|blind in one eye|"
    r"worst headache|thunderclap headache|sudden(?:ly)? (?:severe|terrible|"
    r"excruciating) headache",
  );
  static final _selfHarm = RegExp(
    r"suicid|kill myself|killing myself|end my life|ending my life|"
    r"want to die|wanna die|don'?t want to (?:live|be alive|be here|exist)|"
    r"self[- ]?harm|hurt(?:ing)? myself|cut(?:ting)? myself|"
    r"no reason to (?:live|keep living|go on)|"
    r"(?:don'?t|can'?t) see (?:a|any) (?:reason|point) (?:to|in) (?:keep )?"
    r"(?:living|going on|being alive|being here)|better off without me|"
    r"better off dead|overdose|tak(?:e|ing) all (?:of )?my (?:pills|tablets|"
    r"meds|medication)|end it all|can'?t go on (?:anymore|any more|like this)|"
    r"(?:pills|tablets|meds)[^.?!]{0,40}(?:not wake up|never wake up)|"
    r"never wake up again|not wake up again",
  );
  static final _symptom = RegExp(
    r"dizz|light-?headed|faint|chest|short of breath|breathless|can'?t breathe|"
    r"confus|palpitat|pounding|vision|sweating|nause",
  );
  static final _restHr = RegExp(
    r"(?:resting|at rest|sitting|lying|in bed|sleeping|while resting)[^.?!]{0,40}"
    r"(?:heart rate|hr|pulse|heart)[^.?!]{0,20}?(\d{2,3})|"
    r"(?:heart rate|hr|pulse)[^.?!]{0,30}?(\d{2,3})\s*(?:bpm)?[^.?!]{0,40}"
    r"(?:at rest|resting|sitting|lying|in bed)",
  );

  /// Any heart-rate number (for a very low one with symptoms).
  static final _anyHr = RegExp(
    r"(?:heart rate|\bhr\b|pulse|heart)[^.?!]{0,30}?\b(\d{2,3})\b",
  );
  static final _racing = RegExp(
    r"heart (?:is |keeps )?(?:racing|pounding|fluttering|skipping)|"
    r"racing heart|irregular heartbeat",
  );
  static final _pregnant = RegExp(r"pregnan");
  static final _pregFlag = RegExp(
    r"bleed|spotting|cramp|severe pain|pain|contraction|waters? (?:broke|"
    r"breaking)|leaking fluid|baby (?:isn'?t|not) moving|reduced movement",
  );

  static const emergencyMessage =
      'This could need urgent care, so please don\'t wait on an app. If you '
      'have chest pain or pressure, trouble breathing, fainting, sudden '
      'weakness, numbness or slurred speech, a racing heart with dizziness, '
      'or bleeding or pain in pregnancy, call your local emergency number '
      'now (112 in the EU and India, 911 in the US, 999 in the UK) or have '
      'someone take you to the nearest emergency department. If it feels '
      'less severe, contact a doctor or urgent-care line today.\n\n'
      'I\'m a wellness tool, not a medical service: your band\'s data can\'t '
      'rule anything out.';

  static const selfHarmMessage =
      'I\'m really sorry you\'re feeling this way. You deserve support right '
      'now, from a person. If you might act on these thoughts or you\'re in '
      'danger, call your local emergency number (112 in the EU and India, '
      '911 in the US, 999 in the UK). You can also talk to a crisis line: '
      'in the US call or text 988, in the UK and Ireland call Samaritans on '
      '116 123, in India call Tele-MANAS on 14416, or find a line near you '
      'at findahelpline.com. If you can, tell someone you trust how you\'re '
      'feeling.';

  static const medicationMessage =
      'I can\'t give advice about medicines, supplements or doses, '
      'including whether to start, stop or change one. A pharmacist or your '
      'doctor can help with that, because they can weigh it against your '
      'health history. If it helps that conversation, I can show what your '
      'band recorded, like your resting heart rate, HRV or sleep.';

  static const eatingMessage =
      'It sounds like food and eating may be feeling hard right now, and '
      'that matters. I\'m not the right tool for this, but people can help: '
      'a doctor is a good first step, and you can find free, confidential '
      'eating-disorder support near you at findahelpline.com. If you feel '
      'unsafe, call your local emergency number (112 in the EU and India, '
      '911 in the US, 999 in the UK).';

  static const pregnancyMessage =
      'Pregnancy changes resting heart rate, HRV, sleep and breathing, and '
      'Airlog\'s scores and ranges aren\'t built or checked for pregnancy. '
      'For questions about training, sleep or your numbers while pregnant, '
      'your midwife, obstetrician or doctor is the right person to ask. If '
      'you have bleeding, severe pain, leaking fluid or fewer baby '
      'movements, contact your maternity unit or emergency services now.';

  static const minorMessage =
      'Airlog\'s coach is built for adults 18 and over, and its scores and '
      'ranges are based on adults. If you\'re under 18, please talk about '
      'training, sleep and health questions with a parent or guardian, a '
      'coach, or a doctor.';

  // ── Medication / supplements / dosing ─────────────────────────────────

  static final _medWords = RegExp(
    r"\b(?:meds|medications?|medicines?|prescriptions?|prescribed|pills?|"
    r"tablets?|capsules?|doses?|dosage|dosing|mg|milligrams?|mcg|"
    r"beta[- ]?blockers?|metoprolol|propranolol|bisoprolol|atenolol|"
    r"antidepressants?|ssris?|sertraline|fluoxetine|citalopram|escitalopram|"
    r"venlafaxine|lexapro|zoloft|prozac|insulin|metformin|ozempic|"
    r"semaglutide|wegovy|statins?|atorvastatin|inhalers?|salbutamol|"
    r"ventolin|ibuprofen|advil|nurofen|paracetamol|tylenol|acetaminophen|"
    r"aspirin|naproxen|painkillers?|antibiotics?|antihistamines?|"
    r"melatonin|magnesium|zinc|iron tablets?|iron supplements?|"
    r"vitamin [a-z0-9]+|creatine|ashwagandha|caffeine pills?|"
    r"pre-?workout (?:supplements?|powders?|drinks?|scoops?|shots?|pills?)|"
    r"supplements?|sleeping (?:pills?|tablets?)|sleep aids?|zolpidem|ambien|"
    r"zopiclone|benzodiazepines?|benzos?|diazepam|valium|xanax|lorazepam|"
    r"steroids?|prednisone|birth control|the pill|thyroxine|levothyroxine|"
    r"blood thinners?|warfarin|nicotine patch(?:es)?|cbd|thc|edibles?)\b",
  );
  static final _medIntent = RegExp(
    r"\b(?:should i|can i|could i|do i|would it|would|is it (?:ok|okay|safe|"
    r"bad|fine)|safe to|ok to|okay to|how much|how many|what dose|which dose|"
    r"right dose|what dosage|dosage|dose|take|taking|took|start(?:ing)?|"
    r"stop(?:ping)?|quit(?:ting)?|skip(?:ping)?|doubl(?:e|ing)|halv(?:e|ing)|"
    r"in half|increas(?:e|ing)|decreas(?:e|ing)|reduc(?:e|ing)|"
    r"lower(?:ing)?|up my|come off|coming off|go off|switch(?:ing)?|"
    r"swap(?:ping)?|chang(?:e|ing)|help(?:s|ing)?|recommend|worth taking|"
    r"better for|best for|affect(?:s|ing)?|raise my|mess(?:es|ing)? with|"
    r"interfer(?:e|es|ing))\b",
  );

  // ── Eating-disorder signals ───────────────────────────────────────────

  static final _edSignals = RegExp(
    r"make myself (?:sick|throw up|vomit|puke)|making myself (?:sick|throw "
    r"up|vomit)|(?:throw|throwing|threw) up (?:after|my) (?:(?:big|large|"
    r"every|each) )?(?:eating|meals?|food|dinner|lunch)|so (?:that )?i "
    r"(?:don'?t|dont|won'?t|wont|can'?t) gain (?:any )?weight|thr[eo]w up (?:after|what) i (?:eat|ate)|purg(?:e|ed|ing)\b|"
    r"laxatives?|diet pills?|starv(?:e|ed|ing) myself|stop(?:ped)? eating|"
    r"not eating (?:to|so|until|for)|haven'?t eaten (?:in|for) (?:days|"
    r"\d+ days|two days|three days)|skip(?:ping)? (?:all )?(?:my )?meals? "
    r"(?:to|so i can) (?:lose|drop|get)|burn off (?:everything|every|all|"
    r"what) (?:i eat|i ate|meal|calories|of it)|burn off every(?:thing)? i "
    r"eat|exercis(?:e|ing) (?:off|to burn off) (?:every|all|everything)|"
    r"fast(?:ing|ed)? for (?:\d+|two|three|four|five|several|a few|many) "
    r"days|(?:feel|felt|feeling) (?:so |really |very )?(?:guilty|disgusting|"
    r"gross|ashamed|fat) (?:after|about|when|for) (?:eating|i eat|i ate|"
    r"food|meals?)|hate (?:my body|myself for eating)|binge(?:d|ing)? and "
    r"(?:purge|throw|compensate)|anorexi|bulimi|eating disorder|pro[- ]?ana|"
    r"thinspo|too fat to|afraid of (?:eating|food|gaining)|terrified of "
    r"(?:eating|gaining)",
  );
  static final _intake = RegExp(
    r"(?:eat|eating|ate|intake|consum\w*|only having|living on|"
    r"sticking to|keep(?:ing)? (?:it )?(?:under|below|to))\D{0,25}?"
    r"(\d{2,4})\s*(?:k?cal|calories)\b|"
    r"(\d{2,4})\s*(?:k?cal|calories)\s+(?:a|per|each)\s+day",
  );

  // ── Pregnancy (non-emergency) and minors ──────────────────────────────

  static final _pregnancyAny = RegExp(
    r"\bpregnan\w*|\bexpecting a baby\b|\bweeks? pregnant\b|\btrimester\b|"
    r"\bmy (?:midwife|obstetrician|ob-?gyn)\b|\bbaby bump\b",
  );

  static const _teen =
      r"(?:1[0-7]|[5-9]|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|"
      r"fourteen|fifteen|sixteen|seventeen)";
  static final _minor = RegExp(
    r"\b(?:i'?m|i am|im|as an?)\s+(?:only\s+|just\s+)?"
    "$_teen"
    r"(?:[- ](?:years?|yrs?|yo|y/o)(?:[- ]old)?)?\b|"
    r"\b"
    "$_teen"
    r"[- ](?:years?|yrs?)[- ]old\b|"
    r"\bunder 18\b|\bunder eighteen\b|\bi'?m a (?:minor|teenager|teen)\b|"
    r"\b(?:in|at) (?:high school|secondary school|middle school|junior "
    r"high)\b|\bin (?:year|grade) (?:[5-9]|1[0-2])\b|\bin (?:[5-9]|1[0-2])"
    r"(?:th|st|nd|rd) grade\b|"
    r"\bmy (?:son|daughter|kid|child|children|kids|teen|teenager|little one)"
    r"\b[^.?!]{0,30}\b(?:use|uses|using|wear|wears|wearing|try|borrow|track|"
    r"tracking|have (?:a|one|my)|get (?:a|one))\b|"
    r"\b(?:son|daughter|kid|child|teen|teenager)\b[^.?!]{0,12}\b(?:is|aged|"
    r"turns|turned)\s+(?:only\s+|just\s+)?"
    "$_teen"
    r"\b",
  );

  /// Words after a number that mean it isn't an age ("I'm 15 minutes in",
  /// "a 12 year old watch").
  static final _notAge = RegExp(
    r"^\s*(?:%|min\b|mins\b|minutes|km|kms|miles|mi\b|k\b|kg|kgs|lbs?|"
    r"pounds|bpm|ms\b|hours?|hrs?\b|h\b|days?|weeks?|reps|sets|steps|laps|"
    r"seconds|secs|points?|strain|percent|nights?|times|workouts?|runs?|"
    r"sessions?|watch|band|phone|mattress|car|bike|house|tracker|beats|"
    r"breaths|degrees|ml|mg|g\b|of\b|out of|/|foot|feet|ft\b|inch(?:es)?|"
    r"cm\b|m\b|'|stone|st\b)",
  );

  /// "a dose of training" is not medication.
  static final _trainingDose = RegExp(
    r"\b(?:dose|dosage|dosing) of (?:training|exercise|cardio|intensity|"
    r"zone \d|running|work|strain|volume|sunlight|daylight)\b",
  );

  /// The routed flag for [question], or null. Deterministic, no I/O.
  static SafetyVerdict? check(String question) {
    final q = question
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(_trainingDose, 'amount of training');
    if (_selfHarm.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.selfHarm, selfHarmMessage);
    }
    if (_chest.hasMatch(q.replaceAll('chest strap', ''))) {
      return const SafetyVerdict(RedFlag.chestPain, emergencyMessage);
    }
    if (_stroke.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.stroke, emergencyMessage);
    }
    if (_breath.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.breathless, emergencyMessage);
    }
    if (_faint.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.fainting, emergencyMessage);
    }
    if (_pregnant.hasMatch(q) && _pregFlag.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.pregnancy, emergencyMessage);
    }
    final hr = _restHr.firstMatch(q);
    if (hr != null) {
      final bpm = int.tryParse(hr.group(1) ?? hr.group(2) ?? '');
      if (bpm != null && (bpm >= 130 || bpm <= 38) && _symptom.hasMatch(q)) {
        return const SafetyVerdict(
          RedFlag.heartRateWithSymptoms,
          emergencyMessage,
        );
      }
    }
    for (final m in _anyHr.allMatches(q)) {
      final bpm = int.tryParse(m.group(1)!);
      if (bpm != null && bpm >= 20 && bpm <= 40 && _symptom.hasMatch(q)) {
        return const SafetyVerdict(
          RedFlag.heartRateWithSymptoms,
          emergencyMessage,
        );
      }
    }
    if (_racing.hasMatch(q) &&
        RegExp(
          r"dizz|light-?headed|faint|chest|short of breath|breathless|"
          r"can'?t breathe|confus",
        ).hasMatch(q)) {
      return const SafetyVerdict(
        RedFlag.heartRateWithSymptoms,
        emergencyMessage,
      );
    }

    // Non-emergency routes.
    if (_edSignals.hasMatch(q) || _lowIntake(q)) {
      return const SafetyVerdict(RedFlag.eatingDisorder, eatingMessage);
    }
    if (_pregnancyAny.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.pregnancyInfo, pregnancyMessage);
    }
    if (_isMinor(q)) {
      return const SafetyVerdict(RedFlag.minor, minorMessage);
    }
    if (_medWords.hasMatch(q) && _medIntent.hasMatch(q)) {
      return const SafetyVerdict(RedFlag.medication, medicationMessage);
    }
    return null;
  }

  /// An eating intake under 1,000 kcal a day ("I eat 600 calories a day").
  static bool _lowIntake(String q) {
    for (final m in _intake.allMatches(q)) {
      final n = int.tryParse(m.group(1) ?? m.group(2) ?? '');
      if (n == null || n < 50 || n >= 1000) continue;
      // "burned 500 calories a day" is energy out, not intake.
      final before = q.substring(0, m.start);
      if (RegExp(
        r"\b(?:burn(?:ed|t|ing)?|active|workout|exercise|"
        r"expend(?:ed)?)\W+(?:\w+\W+){0,2}$",
      ).hasMatch(before)) {
        continue;
      }
      if (m.group(1) == null &&
          RegExp(r"\b(?:burn(?:ed|t|ing)?|active|expend)").hasMatch(before)) {
        continue;
      }
      return true;
    }
    return false;
  }

  static bool _isMinor(String q) {
    for (final m in _minor.allMatches(q)) {
      if (_notAge.hasMatch(q.substring(m.end))) continue;
      return true;
    }
    return false;
  }
}
