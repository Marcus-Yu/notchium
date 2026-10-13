# Ready-to-use Codex prompt: Stage 25A, pure proactive policy foundation

This is a proposed first implementation stage. Do not execute this prompt until the developer explicitly approves implementation.

---

Work in the existing Notchium macOS repository. Implement ONLY Stage 25A: a small deterministic value/policy foundation for later proactive suggestions. Do not implement the full roadmap.

Read repository guidance, docs/ENGINEERING_RULES.md, docs/PROACTIVE_INTELLIGENCE_FEASIBILITY.md, current Package.swift, AppClock, activity priority/lifetime policy, Calendar summary, and relevant existing tests before editing. Treat the current source as authoritative where historical stage documents differ.

Before coding, briefly explain the intended ownership and list the small set of files you expect to change. Preserve unrelated work. Use the available Swift/native review skills; fetch current official documentation only for APIs you actually need.

## Scope

1. Add small Foundation-only Sendable/Equatable value contracts in NotchiumCore for:
   - Explicit proactive source/category consent, initially disabled.
   - Opaque source/run/occurrence identity and source revision, distinct from presentation UUID.
   - Minimal immutable input context with freshness/availability and Focus unknown/on/off; no titles, raw notes, URLs, file paths, clipboard data or framework objects.
   - Suggestion candidate/category, evidence/reason code, eligibleAt/relevantUntil, and supported prepared-action descriptors.
   - Typed response: opened, accept, snooze, dismiss, exposed expiry, less-like-this, never-suggest; neutral invalidation/withdrawal.
   - Minimal learning aggregates and bounded reducer state.

2. Add one NotchiumProactiveFeature package target depending initially only on NotchiumCore. Keep pure decision code in focused files:
   - Candidate validity/consent checks.
   - A deterministic meeting candidate rule using a supplied supportedMeetingLinkAvailable Boolean and opaque occurrence token, not EventKit/URL parsing.
   - Relevance scoring and an interruption decision value (eligible, defer until a supplied deadline, or discard with typed reason).
   - Feedback transitions with smoothed per-category counts, snooze separated from dislike, explicit disable, and deterministic quieting after three distinct dismissals or sufficiently exposed ignores.

3. Define the narrow action enum/plan as values only: join current supported meeting by occurrence token, show Mirror, finite Caffeine, start focus timer with requested duration, run user-pinned Shortcut by pin ID, reveal/add observed completed transfer by ID. No executable closure, arbitrary URL/script, generic dictionary or inferred authorization.

4. Add deterministic tests using explicit wall date, elapsed-time input, revisions and supplied IDs. No real providers or production composition. Reuse existing clock/UUID test infrastructure where useful; do not refactor the repository's clock system.

## Explicit exclusions

- No modification to NotchiumApplicationController production wiring, current FeatureFlags, feature startup or UI.
- No new ActivityCoordinator category, priority change, notification, shell renderer, Settings pane or panel.
- No live Calendar/battery/transfer/Focus observer, global bus, timer loop, process launch, permission request, camera/screen capture, filesystem scan or model.
- No production persistence/store migration. State is supplied/returned in memory. Persistence DTOs may be values only if necessary; avoid building an unused framework.
- No Action Broker executor or real action invocation. No function accessible from candidate generation can perform a side effect.
- No third-party dependency, signing/entitlement/distribution changes, commit, publication, or automatic continuation into Stage 25B.

## Required behavioral fixtures

- Consent off produces no candidate.
- Authorized fresh non-all-day meeting in five minutes with a supported-link flag produces one candidate; no URL flag/all-day/ended/cancelled/denied/stale source produces none.
- Same occurrence with a newer content revision updates validity without becoming a second occurrence; a distinct occurrence is distinct.
- Absolute relevance ends at the earlier of event end and two minutes after start; feedback/content updates cannot extend it.
- Focus unknown is not interpreted as Focus off, and does not block all deterministic candidates. Explicit manual pause or configured known Focus on can defer optional interruption.
- Interruption input indicating sleep, fullscreen, expanded/manual/auxiliary/drag/Mirror interaction, protected transient, active transfer or protected timer cannot yield an unsolicited eligible presentation.
- Generator eligibility/scoring cannot override a critical activity.
- Three distinct actual dismissals quiet a category for seven days; duplicate feedback for one occurrence is idempotent.
- Three adequately exposed ignores quiet the category; hidden expiry, source invalidation, stop and opening are neutral.
- Snooze changes timing only, schedules at most one future eligibility value and never crosses relevance expiry.
- Never suggest disables the category immediately and cannot be reversed by accept, time advancement or ordinary reset.
- Reset learning clears learned weights/recent history while preserving explicit source/category opt-outs; a separate explicit settings reset can restore those choices only through a represented user intent.
- Reducer history/candidates/counts have hard documented bounds and cannot silently evict safety-relevant live identities into duplicate eligibility.
- Forward/backward wall-clock changes use supplied time/validity and cannot replay stale candidates; cooldown/exposure math uses explicit elapsed time within a run.
- Plans/deserialized values contain no approval token and cannot execute anything.

Initial numerical policy is an engineering hypothesis: smoothing a=2, b=2; accept adds one positive, dismiss one negative, adequately exposed ignore 0.25 negative, less-like-this three negative plus quieting, snooze neutral. Score clamp(0.55*evidence + 0.20*urgency + 0.25*affinity - timingPenalty, 0...1), initial threshold 0.75. Keep constants centralized and test policy outcomes, not merely the formula. If a fixture reveals inconsistency, explain and make the smallest coherent adjustment without expanding scope.

## Architecture and non-regression

Existing services and feature models remain authoritative. ActivityCoordinator still owns priority/coalescing/visible lifetime. Stage 21 still owns display/fullscreen/sleep/panel mechanics. New values do not duplicate mutable provider state, store NSScreen/EKEvent, or introduce a second timer. No root/global context environment.

Do not add abstract SignalAdapter protocols per source, a generic event engine, model backend abstraction or database. Small pure functions and a bounded value reducer are enough. Any future action executor belongs at the composition boundary, never in this stage's generator.

## Validation and completion

Build the package and run the new focused tests. Run affected ArchitectureTests and existing activity/Calendar scheduling tests. Compile the existing Release workspace using the release script's free-profile propagation in isolated derived data; CODE_SIGNING_ALLOWED=NO is compile-only validation. Do not run packaging/publishing or permission-dependent app workflows. Run git diff --check and inspect the final diff/status.

Report files changed, why the boundaries were chosen, exact checks run/results, and any unavailable validation. Do not claim runtime/UI/performance evidence from a build. Update only narrowly relevant planning/architecture notes to record Stage 25A's actual interfaces and that production remains unconnected.

Stop after Stage 25A. Provide one narrow next-stage recommendation, but do not begin Stage 25B.
