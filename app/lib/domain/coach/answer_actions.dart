// Today's plan actions shown under an answer (AnswerAction): the plan's own
// words, picked by the answer's topic. TodayPlan stays the only narrator of
// the day: an action is copied, never paraphrased, and only for the newest
// day with data, which the answer itself read. Built on the phone after the
// answer; never sent anywhere. Pure Dart.

import '../today_plan.dart';
import 'coach_contracts.dart';
import 'topics.dart';

abstract final class AnswerActions {
  /// Most actions one answer shows.
  static const max = 2;

  /// The plan action kinds that belong to each answer topic.
  static Set<PlanActionKind> kindsFor(ChatTopic topic) => switch (topic) {
    ChatTopic.sleep => const {PlanActionKind.sleep},
    ChatTopic.recovery => const {
      PlanActionKind.recover,
      PlanActionKind.effort,
      PlanActionKind.checkIn,
    },
    ChatTopic.training => const {PlanActionKind.effort},
    ChatTopic.journal || ChatTopic.general => const {},
  };

  /// [plan]'s actions for [topic], at most [max]; none while the plan has
  /// no usable day (no data, still learning) or its data is behind.
  static List<AnswerAction> fromPlan(TodayPlan plan, ChatTopic topic) {
    if (plan.stale ||
        plan.state == DayState.noData ||
        plan.state == DayState.calibrating) {
      return const [];
    }
    final kinds = kindsFor(topic);
    return [
      for (final a in plan.actions)
        if (kinds.contains(a.kind))
          AnswerAction(
            kind: a.kind.name,
            title: a.title,
            date: plan.date,
            meta: a.evidence.isEmpty
                ? null
                : '${a.evidence.first.label} ${a.evidence.first.value}',
            route: a.route,
          ),
    ].take(max).toList();
  }
}
