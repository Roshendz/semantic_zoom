import 'package:flutter/material.dart';
import 'package:semantic_zoom/semantic_zoom.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'semantic_zoom',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1E6F8C)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF1E6F8C),
      brightness: Brightness.dark,
    ),
    home: const _Home(),
  );
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: _tab,
        children: const [TravelDemo(), HealthDemo(), InboxDemo()],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map), label: 'Travel'),
        NavigationDestination(icon: Icon(Icons.monitor_heart), label: 'Health'),
        NavigationDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
      ],
    ),
  );
}

// ─────────────── Travel journal: markup + a header sliver ───────────────
//
// Content written with LeveledText.parse markup: plain words are the brief
// title, [brackets] add the one-line version, {braces} add the full entry.

final _trip = [
  (
    'Sun 15 Sep',
    'Lisbon',
    LeveledText.parse(
      '[Took] Tram 28 [up] to Alfama{, standing room only and every curve a '
      'small adventure}[. Got lost on purpose and found a tiny bakery.]\n'
      '{Pastéis de nata still warm from the oven. I ate three before '
      'admitting it was lunch.}',
    ),
  ),
  (
    'Mon 16 Sep',
    'Sintra',
    LeveledText.parse(
      'Day trip to Sintra[. Pena Palace was lost in fog]{ until noon, then the '
      'whole valley opened up below us}[. Walked back down through the '
      'forest.] {My legs will remember this tomorrow.}',
    ),
  ),
  (
    'Tue 17 Sep',
    'Lisbon',
    LeveledText.parse(
      'Fado {night} in Mouraria[, a tiny room with twelve tables.] {The singer '
      'closed her eyes for the last song and nobody moved, not even the '
      'waiters.}',
    ),
  ),
  (
    'Wed 18 Sep',
    'Porto',
    LeveledText.parse(
      'Train to Porto[, three hours along the coast.] {Window seat on the '
      'left, as the ticket inspector advised.}\n'
      '[Sunset from the] Dom Luís Bridge{ with half the city doing the same '
      'thing}[.]',
    ),
  ),
  (
    'Thu 19 Sep',
    'Porto',
    LeveledText.parse(
      'Port tasting [in Gaia]{: tawny, ruby, and a white I did not expect to '
      'like}[. Bought one bottle for home.] {Then a second, just in case.}',
    ),
  ),
  (
    'Fri 20 Sep',
    'Porto',
    LeveledText.parse(
      'Livraria Lello[ at opening time]{, before the queue wrapped around the '
      'block}[, then coffee by the river.] {Already planning the next trip.}',
    ),
  ),
];

/// Composes the pieces by hand: a header sliver above the zoomable list,
/// inside a [SemanticZoomDetector].
class TravelDemo extends StatefulWidget {
  const TravelDemo({super.key});

  @override
  State<TravelDemo> createState() => _TravelDemoState();
}

class _TravelDemoState extends State<TravelDemo>
    with SingleTickerProviderStateMixin {
  late final _zoom = SemanticZoomController(
    vsync: this,
    levelLabels: const ['Highlights', 'Day summary', 'Full entry'],
  );

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge;
    return Column(
      children: [
        Expanded(
          child: SemanticZoomDetector(
            controller: _zoom,
            builder: (context, isPinching) => CustomScrollView(
              physics: isPinching
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(child: _TripHeader()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverSemanticZoomList.builder(
                    controller: _zoom,
                    itemCount: _trip.length,
                    itemBuilder: (context, i) {
                      final (date, place, text) = _trip[i];
                      return _TapToExpand(
                        controller: _zoom,
                        itemId: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: date,
                                      style: label?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '  ·  $place',
                                      style: label?.copyWith(
                                        color: theme.hintColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              LeveledTextView(
                                text,
                                itemId: i,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        _LevelSelector(
          controller: _zoom,
          labels: const ['Highlights', 'Summary', 'Full'],
        ),
      ],
    );
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.all(18),
    alignment: Alignment.bottomLeft,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF4C27A), Color(0xFF3F8FA8), Color(0xFF123E57)],
      ),
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lisbon & Porto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Pinch the list, or tap one day',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    ),
  );
}

// ──────────── Health timeline: fromVersions + SemanticZoomListView ──────────
//
// Visit title → summary → clinician notes, built from three plain versions.

final _visits = [
  (
    'Mar 12',
    'Cardiology',
    LeveledText.fromVersions(const [
      'Blood pressure follow-up',
      'Blood pressure follow-up: readings improved, dose unchanged',
      'Blood pressure follow-up: home readings averaged 128/82 over four '
          'weeks, readings improved since January, dose unchanged. Continue '
          'low-sodium diet and review again in three months.',
    ]),
  ),
  (
    'Feb 02',
    'General practice',
    LeveledText.fromVersions(const [
      'Annual check-up',
      'Annual check-up with routine blood tests, all normal',
      'Annual check-up with routine blood tests, all normal. Vitamin D '
          'slightly low; supplement advised through winter. Flu vaccine '
          'given.',
    ]),
  ),
  (
    'Jan 15',
    'Physiotherapy',
    LeveledText.fromVersions(const [
      'Knee review',
      'Knee review: swelling reduced, cleared to run',
      'Knee review after six sessions: swelling reduced and range of motion '
          'restored, cleared to run twice a week. Keep strength exercises '
          'daily.',
    ]),
  ),
  (
    'Jan 03',
    'Dermatology',
    LeveledText.fromVersions(const [
      'Skin check, nothing concerning',
      'Full skin check found no concerning moles',
      'Full skin check by Dr Rossi found no concerning moles. One mole on '
          'the left shoulder photographed as a baseline; recheck next year.',
    ]),
  ),
];

/// The one-widget setup with [SemanticZoomListView.builder].
class HealthDemo extends StatefulWidget {
  const HealthDemo({super.key});

  @override
  State<HealthDemo> createState() => _HealthDemoState();
}

class _HealthDemoState extends State<HealthDemo>
    with SingleTickerProviderStateMixin {
  late final _zoom = SemanticZoomController(
    vsync: this,
    levelLabels: const ['Visit titles', 'Visit summaries', 'Clinician notes'],
  );

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const _SectionTitle(
          title: 'Patient timeline',
          subtitle: 'Visit title › summary › clinician notes',
        ),
        Expanded(
          child: SemanticZoomListView.builder(
            controller: _zoom,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _visits.length,
            itemBuilder: (context, i) {
              final (date, dept, text) = _visits[i];
              return Card.outlined(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: _TapToExpand(
                  controller: _zoom,
                  itemId: i,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$date · $dept',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        LeveledTextView(
                          text,
                          itemId: i,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _LevelSelector(
          controller: _zoom,
          labels: const ['Titles', 'Summary', 'Notes'],
        ),
      ],
    );
  }
}

// ─────────────── Inbox: LLM-style summaries that rephrase ───────────────
//
// Real summaries rarely only add words. fromVersions aligns them anyway:
// shared words slide, rephrased ones cross-fade.

final _threads = [
  (
    'Maya · Design',
    '9:41',
    LeveledText.fromVersions(const [
      'Onboarding mockups ready for review',
      'Onboarding mockups from Maya are ready for review by Thursday',
      'Onboarding mockups from Maya are ready for review in Figma. She '
          'prefers option B, which cuts signup to two steps, and needs '
          'feedback by Thursday so engineering can start next sprint.',
    ]),
  ),
  (
    'Leo · Support',
    '9:12',
    LeveledText.fromVersions(const [
      'Checkout crash fixed',
      'Android checkout crash is fixed in version 4.2.1',
      'The checkout crash affecting some Android 14 users is fixed in '
          'version 4.2.1, now rolling out to 20% of users. Leo will close the '
          'tickets once the crash rate stays flat for 48 hours.',
    ]),
  ),
  (
    'Finance',
    'Yesterday',
    LeveledText.fromVersions(const [
      'Q3 budget approved',
      'Q3 budget approved with a 5% cut to travel',
      'Q3 budget approved with a 5% cut to travel. Trips already booked are '
          'unaffected; new ones need director sign-off from October.',
    ]),
  ),
  (
    'Sam · People team',
    'Mon',
    LeveledText.fromVersions(const [
      'Offsite moved to Friday',
      'Team offsite moved to Friday because of the rail strike',
      'Team offsite moved from Thursday to Friday because of the rail '
          'strike. Same venue and agenda; Sam is sending new invites today.',
    ]),
  ),
];

class InboxDemo extends StatefulWidget {
  const InboxDemo({super.key});

  @override
  State<InboxDemo> createState() => _InboxDemoState();
}

class _InboxDemoState extends State<InboxDemo>
    with SingleTickerProviderStateMixin {
  late final _zoom = SemanticZoomController(
    vsync: this,
    levelLabels: const ['Subjects', 'Short summaries', 'Detailed summaries'],
  );

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const _SectionTitle(
          title: 'Inbox',
          subtitle: 'AI summaries at three lengths, rephrasing included',
        ),
        Expanded(
          child: SemanticZoomListView.builder(
            controller: _zoom,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            itemCount: _threads.length,
            itemBuilder: (context, i) {
              final (from, time, text) = _threads[i];
              return _TapToExpand(
                controller: _zoom,
                itemId: i,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        child: Text(from.characters.first),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    from,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                                Text(
                                  time,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LeveledTextView(
                              text,
                              itemId: i,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _LevelSelector(
          controller: _zoom,
          labels: const ['Subject', 'Short', 'Detailed'],
        ),
      ],
    );
  }
}

// ───────────────────────────── shared ─────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

/// Tapping an entry steps just that entry to the next level, wrapping back
/// to the global level after the last one.
class _TapToExpand extends StatelessWidget {
  const _TapToExpand({
    required this.controller,
    required this.itemId,
    required this.child,
  });

  final SemanticZoomController controller;
  final Object itemId;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    // The text view already exposes adjust actions to screen readers.
    excludeFromSemantics: true,
    onTap: () {
      final next = controller.itemLevel(itemId) + 1;
      controller.setItemLevel(
        itemId,
        next > controller.maxLevel ? controller.level : next,
      );
    },
    child: child,
  );
}

/// Pinch isn't discoverable or usable for everyone. Always ship an explicit
/// control that drives the same animation.
class _LevelSelector extends StatelessWidget {
  const _LevelSelector({required this.controller, required this.labels});

  final SemanticZoomController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SegmentedButton<int>(
        // Full width, and no check icon, so labels never wrap and the row
        // doesn't change size as the level changes.
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        segments: [
          for (var i = 0; i < labels.length; i++)
            ButtonSegment(value: i, label: Text(labels[i])),
        ],
        selected: {controller.level},
        onSelectionChanged: (s) => controller.animateToLevel(s.first),
      ),
    ),
  );
}
