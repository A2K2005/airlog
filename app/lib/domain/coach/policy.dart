// Output policy check: runs AFTER the verifier on every model-written chat
// answer and every full-level (LLM-rewritten) insight card. The verifier
// asks "is every number, date and event backed by the data?"; this asks
// "is the text something a wellness coach may say at all?". It rejects:
//
//   * diagnosis: "you have AFib", "this looks like sleep apnea", "you are
//     sick", "your numbers suggest an infection";
//   * dosing / medication instructions: "take 400 mg", "stop your meds",
//     "try melatonin", any mg / mcg / IU amount;
//   * certainty about disease: "this definitely means you're getting sick",
//     "your HRV proves…", "you will get sick";
//   * shaming or weight-loss pressure: "lazy", "no excuses", "you need to
//     lose weight", "burn off that dinner", "cut to 1,200 calories".
//
// Negated, conditional and clinician-pointer sentences pass ("this isn't a
// diagnosis", "if you feel unwell, talk to a doctor", "don't stop your
// medication without your doctor"). A failing answer gets the same single
// repair round as the verifier, then the facts table. Deterministic, pure
// Dart, no I/O.

enum PolicyKind {
  diagnosis('Diagnosis language'),
  dosing('Medication or dosing instruction'),
  certainty('Certainty about illness'),
  shaming('Shaming or weight-loss pressure');

  const PolicyKind(this.label);
  final String label;
}

class PolicyViolation {
  const PolicyViolation(this.kind, this.sentence, this.match);
  final PolicyKind kind;

  /// The offending sentence (citations stripped).
  final String sentence;

  /// The matched phrase.
  final String match;

  /// One line for the repair prompt.
  String get describe => '${kind.label}: "$sentence"';
}

class PolicyReport {
  const PolicyReport(this.violations);
  final List<PolicyViolation> violations;
  bool get ok => violations.isEmpty;
  Set<PolicyKind> get kinds => {for (final v in violations) v.kind};
}

abstract final class OutputPolicy {
  /// Guidance appended to the repair prompt for each violated kind.
  static String fix(PolicyKind k) => switch (k) {
    PolicyKind.diagnosis =>
      'Describe what the data shows; never name or suggest a condition the '
          'user may have. You may say it is not a diagnosis and suggest a '
          'doctor.',
    PolicyKind.dosing =>
      'Give no medication, supplement or dose advice; point to a pharmacist '
          'or doctor instead.',
    PolicyKind.certainty =>
      'Never state that the data shows or proves an illness; describe the '
          'numbers and possible everyday causes.',
    PolicyKind.shaming =>
      'Use calm, neutral wording with no blame, guilt or weight-loss '
          'pressure.',
  };

  // ── Vocabulary ─────────────────────────────────────────────────────────

  static const _conditions =
      r"(?:(?:a |an |the |some )?(?:possible |likely |early |mild |serious )?"
      r"(?:a(?:trial)?[- ]?fib(?:rillation)?|afib|a-fib|arrhythmias?|"
      r"(?:obstructive )?sleep apn(?:o)?ea|apn(?:o)?ea|insomnia|narcolepsy|"
      r"(?:long )?covid(?:-19)?|coronavirus|the flu|flu|influenza|a cold|"
      r"common cold|(?:viral |bacterial |chest |respiratory |sinus |ear |"
      r"throat |urinary |lung )?infections?|virus|"
      r"viral illness|fever|diabetes|pre-?diabetes|hypertension|"
      r"high blood pressure|hypotension|low blood pressure|heart disease|"
      r"(?:a )?heart (?:condition|problem|issue)|cardiac (?:issue|problem|"
      r"condition)|heart failure|tachycardia|bradycardia|pots|"
      r"overtraining syndrome|chronic fatigue|depression|anxiety disorder|"
      r"an? anxiety|anaemia|anemia|thyroid (?:issue|problem|disease)|"
      r"hyperthyroidism|hypothyroidism|pneumonia|bronchitis|asthma|"
      r"mono(?:nucleosis)?|glandular fever|lyme disease|sepsis|"
      r"an? (?:illness|disease|disorder|syndrome|condition)|cancer|"
      r"eating disorder|burnout syndrome|sleep disorder))";

  static const _sickWords =
      r"(?:sick|ill|unwell|illness|infection|infected|virus|viral|flu|cold|"
      r"covid|fever|disease|condition|disorder|afib|a-?fib|arrhythmia|"
      r"apn(?:o)?ea|heart problem|heart issue|coming down with something)";

  static const _meds =
      r"(?:meds|medications?|medicines?|prescriptions?|pills?|tablets?|"
      r"capsules?|doses?|dosage|beta[- ]?blockers?|antidepressants?|ssris?|"
      r"insulin|inhalers?|statins?|metformin|ibuprofen|paracetamol|"
      r"acetaminophen|aspirin|naproxen|melatonin|magnesium|zinc|iron "
      r"supplements?|vitamin [a-z0-9]+|creatine|ashwagandha|"
      r"antihistamines?|sleeping (?:pills?|tablets?)|sleep aids?|"
      r"zolpidem|ambien|benzodiazepines?|diazepam|xanax|supplements?|"
      r"electrolyte tablets?|caffeine pills?|painkillers?|antibiotics?)";

  static final _diagnosis = <RegExp>[
    // "You have AFib", "you've got the flu", "you probably have an infection".
    RegExp(
      r"\byou(?:'ve| have|'re having| are having)?\s+(?:(?:probably|likely|"
      r"clearly|definitely|already|now|still|might|may|could|must|seem to|"
      r"appear to)\s+)*(?:have|got|caught|developed|developing|getting|"
      r"get|contracted|be (?:getting|developing|coming down with))\s+"
      "$_conditions\\b",
    ),
    // "You're coming down with…", "you are sick", "you've caught something".
    RegExp(
      r"\byou(?:'re| are)\s+(?:(?:probably|likely|clearly|definitely|"
      r"already|now|still|getting|becoming|falling|actually|really)\s+)*"
      r"(?:sick|ill|unwell|infected|diabetic|hypertensive)\b",
    ),
    RegExp(
      r"\byou(?:'re| are)\s+(?:(?:probably|likely|clearly|definitely|"
      r"already|now|still|actually)\s+)*coming down with\b",
    ),
    RegExp(r"\byou(?:'ve| have)\s+(?:probably\s+|likely\s+)?caught\b"),
    // "This looks like sleep apnea", "these are symptoms of AFib",
    // "your numbers suggest an infection".
    RegExp(
      r"\b(?:this|that|it|these|those|the pattern|this pattern|that pattern|"
      r"your (?:numbers|data|readings|results|pattern|trend|hrv|heart rate|"
      r"resting (?:hr|heart rate)|sleep|breathing|spo[2₂]|temperature)|"
      r"the (?:numbers|data|readings|results))\s+(?:(?:really|strongly|"
      r"clearly|definitely|probably|likely|could|might|may|would|all)\s+)*"
      r"(?:looks?|sounds?|seems?|is|are|be|suggests?|indicates?|points? to|"
      r"means?|reflects?|shows?|signals?|reveals?|matches|fits|"
      r"(?:is|are) consistent with|(?:is|are) typical of|(?:is|are) "
      r"(?:a |the )?(?:classic |early )?(?:signs?|symptoms?|markers?) of)\s+"
      r"(?:like\s+|consistent with\s+|typical of\s+)?(?:(?:the )?(?:early |"
      r"classic )?(?:signs?|symptoms?|onset|start) of\s+)?(?:you (?:have|are "
      r"getting|are developing|'re getting|'re developing|might have|may "
      r"have)\s+)?"
      "$_conditions\\b",
    ),
    RegExp(
      r"\b(?:it's|that's|this's)\s+(?:(?:probably|likely|just|definitely|"
      r"clearly|almost certainly|most likely|possibly)\s+)*(?:(?:the )?"
      r"(?:early |classic )?(?:signs?|symptoms?|onset|start) of\s+)?"
      "$_conditions\\b",
    ),
    RegExp("\\b(?:signs?|symptoms?) of\\s+$_conditions\\b"),
    RegExp(
      r"\b(?:points? to|suggests?|indicates?|signals?|is consistent with|"
      r"are consistent with|is typical of|are typical of|looks like|"
      r"sounds like|seems like|means)\s+(?:that\s+)?(?:you(?:'re| are)? "
      r"(?:have|are getting|getting|developing|might have|may have|could "
      r"have|probably have|likely have)\s+)?(?:(?:the )?(?:early |classic |"
      r"first )?(?:signs?|symptoms?|onset|start) of\s+)?"
      "$_conditions\\b",
    ),
    RegExp(
      r"\b(?:diagnos(?:e|ed|is|ing))\b(?:\s+(?:you|it|this))?(?:\s+(?:as|with))",
    ),
    RegExp(
      r"\byou(?:'re| are) (?:suffering from|experiencing) "
      "$_conditions\\b",
    ),
  ];

  static final _dosing = <RegExp>[
    // Any explicit dose amount.
    RegExp(
      r"\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|milligrams?|micrograms?|iu|"
      r"units? of insulin|ml of|g of|grams? of|drops? of|scoops? of)\b",
    ),
    // "take 2 tablets", "take a pill", "double your dose".
    RegExp(
      r"\b(?:take|taking|try|trying|use|using|start(?: taking)?|increase|"
      r"double|halve|up|add|pop)\s+(?:your\s+|a\s+|an\s+|some\s+|another\s+|"
      r"one\s+|two\s+|\d+\s+|extra\s+|more\s+|less\s+|half\s+(?:a\s+)?)*"
      r"(?:[a-z-]+\s+){0,2}"
      "$_meds\\b",
    ),
    // "stop your meds", "skip your beta blocker", "come off your pills".
    RegExp(
      r"\b(?:stop|stopping|quit|skip|skipping|pause|pausing|come off|go off|"
      r"cut out|cut back on|discontinue|drop|reduce|lower|raise|change|"
      r"adjust|switch)\s+(?:taking\s+|using\s+)?(?:your\s+|the\s+|all\s+)?"
      r"(?:[a-z-]+\s+){0,3}"
      "$_meds\\b",
    ),
    // "you should take melatonin", "I recommend magnesium".
    RegExp(
      r"\b(?:you should|you could|you can|you might|you may want to|"
      r"i(?:'d| would)? (?:recommend|suggest|advise)|i recommend|"
      r"it(?:'s| is) (?:fine|ok|okay|safe) to|consider|go ahead and)\s+"
      r"(?:taking\s+|using\s+|trying\s+|a\s+|an\s+|some\s+)?"
      "$_meds\\b",
    ),
  ];

  static final _certainty = <RegExp>[
    RegExp(
      r"\b(?:definitely|certainly|clearly|undoubtedly|surely|obviously|"
      r"without (?:a |any )?doubt|no doubt|there(?:'s| is) no question|"
      r"for sure|100 ?%|guaranteed?|proves?|proven|proof|confirms?|"
      r"confirmed|is a sure sign|are sure signs|always means|means for sure|"
      r"(?:it's|it is|i'm|i am|we're|absolutely|completely|totally) certain)"
      r"[^.!?]{0,60}\b"
      "$_sickWords",
    ),
    RegExp(
      "\\b$_sickWords"
      r"\b[^.!?]{0,40}\b(?:definitely|certainly|for sure|without (?:a )?"
      r"doubt|is (?:confirmed|certain|guaranteed))\b",
    ),
    RegExp(
      r"\byou(?:'ll| will| are going to|'re going to|'re about to| are "
      r"about to)\s+(?:definitely\s+|certainly\s+|probably\s+)?"
      r"(?:get|be|fall|become|come down)\s+(?:sick|ill|unwell|with|injured|"
      r"hurt)\b",
    ),
  ];

  static final _shaming = <RegExp>[
    RegExp(
      r"\b(?:lazy|laziness|pathetic|disgusting|disgraceful|embarrassing|"
      r"shameful|unacceptable|terrible effort|poor effort|weak effort|"
      r"sloppy|slacking|slacker|no excuses?|excuses?,? excuses|"
      r"get your act together|pull yourself together|man up|"
      r"toughen up|you should be ashamed|ashamed of yourself|"
      r"shame on you|you failed|you've failed|you have failed|failed again|"
      r"you(?:'re| are) a failure|let yourself down|let yourself go|"
      r"you blew it|you messed up|you ruined|you wasted)\b",
    ),
    RegExp(
      r"\b(?:you should|you ought to|you must|you need to|you have to|"
      r"you'll need to|time to|try to|aim to|start to|you could stand to)\s+"
      r"(?:feel\s+)?(?:guilty|bad about)\b",
    ),
    // Weight-loss pressure and calorie restriction.
    RegExp(
      r"\b(?:lose|losing|drop|dropping|shed|shedding|cut|cutting|burn|"
      r"burning|get rid of)\s+(?:some\s+|a few\s+|more\s+|the\s+|that\s+|"
      r"those\s+|extra\s+|\d+\s*)*(?:weight|pounds|lbs|kilos|kg|body ?fat|"
      r"belly fat|fat)\b",
    ),
    RegExp(
      r"\byou(?:'re| are| look| seem)\s+(?:(?:a bit|a little|too|very|"
      r"quite|so|rather|clearly|getting)\s+)*(?:overweight|fat|obese|heavy|"
      r"chubby|out of shape)\b",
    ),
    RegExp(
      r"\b(?:burn|work|run|sweat)\s+(?:it\s+)?off\s+(?:that|the|your|this|"
      r"those|last night's|all|everything)?\s*(?:dinner|lunch|breakfast|"
      r"meal|food|snack|dessert|pizza|cake|drinks?|beers?|wine|calories|"
      r"treat|takeaway|burger)?",
    ),
    RegExp(
      r"\bearn (?:your|that|the|a|this) (?:dinner|lunch|breakfast|meal|"
      r"food|dessert|treat|snack)\b",
    ),
    RegExp(
      r"\b(?:cut|reduce|drop|limit|restrict|keep)\s+(?:down\s+)?(?:your\s+)?"
      r"(?:calories|calorie intake|intake|eating|food)\s+(?:to|below|under)\b|"
      r"\b(?:cut|go|drop|get)\s+(?:down\s+)?to\s+(?:about\s+)?[\d,]{3,5}\s*"
      r"(?:k?cal|calories)\b|"
      r"\b(?:eat|eating|intake|consume|consuming|stick to|stay under|"
      r"limit yourself to|aim for|target)\s+(?:about\s+|around\s+|only\s+|"
      r"just\s+|under\s+|below\s+|no more than\s+)?[\d,]{3,5}\s*"
      r"(?:k?cal|calories)\b|"
      r"\bcalorie deficit\b|\beat (?:less|fewer calories|smaller portions)\b|"
      r"\bskip (?:a |your |the )?(?:meal|meals|dinner|lunch|breakfast)\b",
    ),
    RegExp(
      r"\bmake up for (?:eating|that meal|the meal|what you ate|dinner)\b",
    ),
  ];

  // ── Exemptions ─────────────────────────────────────────────────────────

  static final _negator = RegExp(
    r"\b(?:no|not|never|none|nothing|without|neither|nor|cannot|can't|"
    r"can not|don't|doesn't|didn't|isn't|aren't|wasn't|weren't|won't|"
    r"wouldn't|shouldn't|couldn't|haven't|hasn't|no need|no reason|"
    r"rather than|instead of|unable|avoid|nobody)\b|n't\b",
  );
  static final _certainNegPhrase = RegExp(
    r"without (?:a |any )?doubt|no doubt|there(?:'s| is) no question|"
    r"no question",
  );
  static final _conditional = RegExp(
    r"\b(?:if|whether|unless|in case|when|whenever|should you)\b",
  );
  static final _userFrame = RegExp(
    r"\byou (?:said|mentioned|told me|noted|logged|reported|asked)\b|"
    r"\bas you (?:said|mentioned)\b|\byour (?:doctor|clinician|gp) "
    r"(?:said|diagnosed|told)\b|\bdiagnosed by\b",
  );
  static final _pointer = RegExp(
    r"\b(?:doctor|gp|clinician|pharmacist|physician|nurse|midwife|"
    r"cardiologist|specialist|medical professional|healthcare provider|"
    r"urgent care|emergency)\b",
  );

  /// Checks [text] (an answer or a card). [question] lets conditions the
  /// user stated themselves ("I have a cold") be referred back to only in
  /// user-framed sentences ("you mentioned a cold").
  static PolicyReport check(String text) {
    final out = <PolicyViolation>[];
    for (final s in _sentences(text)) {
      final lower = s.toLowerCase().replaceAll('’', "'");
      void test(
        PolicyKind kind,
        List<RegExp> rules, {
        bool Function(String before, String match)? exempt,
      }) {
        for (final re in rules) {
          for (final m in re.allMatches(lower)) {
            final before = _clauseBefore(lower, m.start);
            if (exempt != null && exempt(before, m.group(0)!)) continue;
            out.add(PolicyViolation(kind, s.trim(), m.group(0)!.trim()));
            return;
          }
        }
      }

      bool negatedOrConditional(String before, String _) =>
          _negator.hasMatch(_lastWords(before, 7)) ||
          _conditional.hasMatch(before) ||
          _userFrame.hasMatch(before);

      test(PolicyKind.diagnosis, _diagnosis, exempt: negatedOrConditional);
      test(
        PolicyKind.dosing,
        _dosing,
        exempt: (before, match) {
          // An explicit dose amount is never OK; the rest pass when negated
          // ("don't stop your medication without your doctor") or when the
          // sentence points to a clinician in a question/conditional frame.
          if (RegExp(r'\d').hasMatch(match)) return false;
          return _negator.hasMatch(_lastWords(before, 7)) ||
              (_conditional.hasMatch(before) && _pointer.hasMatch(lower));
        },
      );
      test(
        PolicyKind.certainty,
        _certainty,
        exempt: (before, match) =>
            _negator.hasMatch(_lastWords(before, 7)) ||
            _conditional.hasMatch(before) ||
            // "doesn't prove", "definitely not sick" (but "no doubt" is
            // itself the certainty phrase).
            _negator.hasMatch(match.replaceAll(_certainNegPhrase, ' ')),
      );
      test(
        PolicyKind.shaming,
        _shaming,
        exempt: (before, match) => _negator.hasMatch(_lastWords(before, 5)),
      );
    }
    return PolicyReport(out);
  }

  static final _cite = RegExp(r'\s*\[\s*r\d+(?:\s*[,;]\s*r?\d+)*\s*\]');

  static List<String> _sentences(String text) {
    final clean = text.replaceAll(_cite, '');
    final out = <String>[];
    var start = 0;
    for (final m in RegExp(r'[.!?](?=\s|$)|\n').allMatches(clean)) {
      final s = clean.substring(start, m.end);
      if (s.trim().isNotEmpty) out.add(s);
      start = m.end;
    }
    if (start < clean.length && clean.substring(start).trim().isNotEmpty) {
      out.add(clean.substring(start));
    }
    return out;
  }

  /// Text of the current clause before [pos] (from the last , ; : — or
  /// "but").
  static String _clauseBefore(String s, int pos) {
    final b = s.substring(0, pos);
    final cut = b.lastIndexOf(RegExp(r'[,;:—–(]|\bbut\b|\bhowever\b'));
    return cut < 0 ? b : b.substring(cut + 1);
  }

  static String _lastWords(String s, int n) {
    final w = RegExp(r"[a-z']+").allMatches(s).map((m) => m.group(0)!).toList();
    return (w.length <= n ? w : w.sublist(w.length - n)).join(' ');
  }
}
