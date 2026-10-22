# Notchium AI: executive recommendation

Research date: **2026-10-21**. This blueprint is based on inspected source/configuration, installed Apple SDK declarations, Context7 documentation and official vendor pages. It contains **no implemented features**. No application source, project settings, permissions, dependencies or existing functionality were changed, and nothing was committed or pushed.

## Recommendation

Build an **explicit-text, advisory notch assistant** first: Explain, Summarize and Reply over text the user deliberately supplies, with BYOK OpenAI streaming, Stop/Copy, visible budgets and an optional ordinary window for longer work. Preserve the existing fixed shell and six-page navigation. Add on-demand context and local task/briefing infrastructure as independent next stages. Most valuable proactive behavior can begin with deterministic rules rather than LLM calls.

Do not build the initial product around guaranteed 3–4 AM closed-lid processing, universal email-field insertion, broad mailbox access or unrestricted desktop control. These ideas have materially different reliability, policy and distribution constraints.

## Decisions confirmed through the grilling review

| Decision | Agreed boundary |
|---|---|
| Audience/business | Individual students and knowledge workers; BYOK early access; OpenAI first, Anthropic later |
| Initial cloud behavior | Only explicit user invocation; no automatic screen/mail/calendar uploads |
| First useful feature | Supplied-text explanation, summary and reply drafting; advisory output, explicit Copy/manual paste |
| UI/invocation | Existing 524×266 expanded notch geometry and six pages preserved; invoked AI surface, configurable conventional shortcut/menu; optional longer-work window |
| Memory/spending | Session-only chat by default; explicit saves; later durable task feedback separately; visible request/token budgets and explicit overrides; no silent expensive/provider fallback |
| Briefing promise | Ready or refreshing on return, cached cards with freshness; no exact overnight completion guarantee |
| Later integrations/actions | Screen context optional; approved structured writes later; Gmail, threaded API drafts and browser extensions conditional |
| Distribution | **Strictly zero-cost distribution; keep ad-hoc release policy.** Paid signing/notarization, assessments or hosting cannot be assumed approved or free |

The developer confirmed this consolidated brief and delegated remaining engineering recommendations within it. This is approval of planning scope, not authorization to implement the roadmap.

## Feasibility and combined priorities

This ranking balances delivery sequence, value and risk; it is not a measurement or a sum of scores. Detailed eight-axis judgments for all sixteen proactive candidates are in [07](07-proactive-feature-evaluation.md).

| Order | Feature | Feasibility finding | Practical first increment |
|---:|---|---|---|
| 1 | **C: Notch AI chat** | High for supplied text; conditional for live screen/document fidelity | Explicit-text assistant and shared request/privacy lifecycle |
| 2 | Intelligent Focus Sessions | High with local deterministic rules | Suggest session duration from explicit task/calendar gap; user starts timer |
| 3 | Context-Aware Quick Actions | High for explicitly supplied context | Explain/Summarize/Reply intents; optional selection later |
| 4 | Calendar-Aware Task Planning | High for proposed blocks over explicit inputs | Preview available blocks; no automatic calendar writes |
| 5 | Smart Next-Action Suggestions | High once confirmed tasks and durations exist | Explainable local shortlist; no invented task inventory |
| 6 | Pre-Meeting Briefings | High for curated local event/note bundle | Extend current meeting card with attached evidence |
| 7 | **A: Morning briefing** | High for on-return local cards; exact overnight promise unsuitable | Durable source/task state, cached freshness and coalesced refresh |
| 8 | **B: Contextual email** | High for supplied-text draft; client insertion/mailbox access conditional | Reply intent/Copy first; verified context and insertion later |
| 9 | **D: Computer use** | Feasible for narrow tools; general desktop reliability/security remain difficult | One concrete approved API action with readback, after advisory product |

The five proactive priorities are therefore **intelligent focus, context quick actions, calendar-aware planning, next-action suggestions and bounded pre-meeting briefings**. Resume, conflict detection and preference learning should support these features rather than become separate products.

## Most important source discoveries

1. **Useful architecture already exists.** The app has modular Core/Services/features, explicit composition, renderer-based shell integration, one activity-priority owner and native lifecycle/test patterns. Extend those boundaries; do not add an all-purpose AI application controller.
2. **Local productivity primitives are stronger than integrations.** EventKit Calendar, reminder creation, Pomodoro, Shelf, explicit Clipboard writes and persisted setup are real. Reminder inventory/completion, Gmail, AI providers, current-screen capture/OCR, an AX content reader, a general global hotkey and main-app launch at login are new work.
3. **The proactive module is a pure foundation, not a live assistant.** Stage25 scoring/consent/feedback rules are not connected to the composition target. Feedback lacks durable persistence. Calendar's event-summary UUID map is process-local and cannot safely key cross-launch suppression.
4. **Permissions need the working path.** `NativeOnboardingPermissions` and `OnboardingModel` implement setup; `RealPermissionAuthorizer` is still a scaffold. Optional AI cases must not enter the mandatory `SetupPermission.allCases` completion gate without explicit optionality/migration design.
5. **The shipping policy differs from the original premise.** `Release.xcconfig`, release script and verifier require an arm64 ad-hoc, unnotarized, non-hardened app with no entitlements, unexpected Mach-O executable or bundled `.appex`. A Developer ID enum or Debug configuration does not establish trusted distribution. This plan honors the user's zero-cost constraint.

Actual paths, symbols, reuse matrix and architecture diagram: [01](01-current-architecture.md).

## Shared architecture

Use a small `AIProvider` contract with OpenAI Responses first and a later Anthropic Messages adapter. A dedicated `AIRequestCoordinator` owns request budgets, cancellation and normalized streaming; `ContextEngine` owns bounded, consented evidence acquisition/freshness. UI owns presentation only. A later `ProductivityRuntime` composes source projections, encrypted TaskStore and existing pure suggestion policies. A still-later ToolRegistry/approval boundary/executors validate and verify every authorized action.

Use Foundation HTTP/SSE, Security/CryptoKit and current modular conventions; no external agent framework, remote vector database or managed backend is required for the first release. Keep secrets separate from Clipboard keys, context out of activity events/logs, and time/UUID/I/O injectable. Direct BYOK can later gain an explicitly consented managed transport without uploading users' API keys. Consumer subscriptions are not unlimited API access; current Anthropic subscriber credits are a capped developer-Console program, not a consumer-token workaround. Provider findings, cost scenarios, data models, Mermaid diagram and protocol boundaries: [06](06-shared-ai-architecture.md).

## Important risks and gates

- **Native availability:** ad-hoc Keychain/permission persistence and first-install behavior need actual macOS26/current-OS artifact tests. Existing setup records cannot guarantee OS grants survive identity changes.
- **Context correctness:** AX access varies by app/browser; selected text is read-only at the AX attribute level. Screenshots show only current pixels; OCR/vision can miss math, hidden messages and sensitive content.
- **Source identity/grounding:** recurrence/reschedules/sync resets, ambiguous dates, account aliases and unanswered-email semantics require explicit evidence/state. Schema-valid output is not truth or completion evidence.
- **Gmail/public integration:** restricted scopes, data-transfer policy and potential assessment costs are independent gates; BYOK does not establish exemption. Under current constraints, the feature may remain deferred.
- **Distribution reach:** zero-cost ad-hoc distribution keeps Gatekeeper friction and managed-Mac limitations. Trusted signing/notarization is an analyzed alternative that conflicts with the chosen constraint.
- **Agents:** isolation, prompt injection, approval binding, partial outcomes and non-universal rollback make general computer use a separate major project.

API capabilities/prices/policies were checked against current documentation; model/account combinations must be rechecked during implementation. No live AI requests, mailbox access, real permission prompts, UI automation, builds or tests were performed for this planning-only task. Native SDK headers confirm available interfaces, not runtime reliability. Further qualification is specified in each feature document.

## MVP, long-term direction and next concrete stage

The essential AI MVP is the Stage0/1 vertical slice in [08](08-implementation-roadmap.md): mock-backed compact UI → OpenAI HTTPS/SSE → Keychain credential → egress/budget controls → native focus/lifecycle/free-release qualification. Manual text input makes this independently valuable before integrations. Existing utility behavior must remain intact when AI is disabled or unavailable.

After that, pursue optional selected/window/file context and a separate local task/on-return briefing track. Prefer structured APIs for later writes and a dedicated isolated browser only for demonstrated API gaps. A managed cloud assistant and broad desktop automation remain conditional directions, with explicit funding, security and distribution decisions required before commitment.

## Document index

| Document | Contents |
|---|---|
| [01-current-architecture.md](01-current-architecture.md) | Verified source inventory, architecture, reuse and debt |
| [02-morning-brief.md](02-morning-brief.md) | Scheduling alternatives, local/cloud sources, durable tasks, briefing plan |
| [03-contextual-email.md](03-contextual-email.md) | Draft generation, AX/vision/extension/API alternatives and safe insertion |
| [04-screen-aware-chat.md](04-screen-aware-chat.md) | Explicit chat, ContextEngine, capture/OCR and document retrieval |
| [05-computer-use.md](05-computer-use.md) | Current provider execution interfaces, structured/browser/desktop strategy |
| [06-shared-ai-architecture.md](06-shared-ai-architecture.md) | Shared contracts, concurrency, storage, providers, business models and costs |
| [07-proactive-feature-evaluation.md](07-proactive-feature-evaluation.md) | All sixteen scored candidates, five priorities and eight additional ideas |
| [08-implementation-roadmap.md](08-implementation-roadmap.md) | Stage scope, dependencies, complexity, risk, tests and release gates |
| [09-security-and-distribution.md](09-security-and-distribution.md) | Optional onboarding, permissions, data controls, policy and packaging |
