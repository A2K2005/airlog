// noteCard: a StatusCard for an engine note, with a button only when the
// note's fix names a screen that can actually change the outcome. Shared by
// Strain, Trends and others; lives in app/ because it resolves routes.
//
// Shared kit for features/: imports no feature.

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../domain/results.dart';
import 'route_names.dart';

Widget noteCard(BuildContext context, StatusNote n) {
  final fix = n.fix ?? '';
  // Fixes name "Settings → Data sources" (older stored notes: "→ Sources").
  final (String? label, String? route) = fix.contains('Profile')
      ? ('Open profile', Routes.profile)
      : fix.contains('Data sources') || fix.contains('Sources')
      ? ('Open data sources', Routes.sources)
      : (null, null);
  return StatusCard.fromNote(
    n,
    actionLabel: label,
    onAction: route == null
        ? null
        : () => Navigator.of(context).pushNamed(route),
  );
}
