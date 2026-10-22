# Proactive feature evaluation

Research date: 2026-10-21. All scores are **engineering judgments**, not measured probabilities or user-research results. Evaluate narrow, consented versions of each idea rather than a hypothetical assistant with universal access. The audience and release constraints were confirmed with the developer; see [00](00-executive-summary.md).

## Scoring and ranking

Every axis is 1–5, higher being better: **I** productivity impact, **F** technical feasibility, **S** implementation simplicity, **R** achievable reliability, **P** privacy/security manageability, **U** existing infrastructure reuse, **D** differentiation, **A** operational affordability. A 5 for affordability does not mean implementation is free. Complexity includes integration/qualification, not just model prompting.

Priority ranks consider daily usefulness, dependencies and the agreed scope; they are deliberately **not a sum-based roadmap**. A high-scoring supporting mechanism can still belong inside another feature, and a useful email feature can be blocked by public-integration costs.

| Priority | Candidate | I | F | S | R | P | U | D | A | Recommendation |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 6 Intelligent Focus Sessions | 4 | 5 | 4 | 5 | 5 | 5 | 3 | 5 | Prioritize rules-first |
| 2 | 16 Context-Aware Quick Actions | 4 | 5 | 4 | 4 | 4 | 4 | 4 | 4 | Prioritize explicit invocation |
| 3 | 15 Calendar-Aware Task Planning | 5 | 4 | 3 | 4 | 5 | 4 | 3 | 5 | Prioritize proposed blocks; writes later |
| 4 | 1 Smart Next-Action Suggestions | 4 | 4 | 4 | 4 | 5 | 4 | 3 | 5 | Prioritize after task inventory |
| 5 | 5 Pre-Meeting Briefings | 4 | 4 | 3 | 4 | 4 | 5 | 3 | 4 | Prioritize bounded/local version |
| 6 | 4 Resume Where You Left Off | 4 | 4 | 4 | 4 | 5 | 4 | 3 | 5 | Merge into on-return brief |
| 7 | 3 Adaptive Study Assistant | 4 | 4 | 3 | 3 | 4 | 3 | 4 | 3 | Optional document-assistant track |
| 8 | 9 Deadline Conflict Detector | 4 | 4 | 4 | 3 | 5 | 4 | 3 | 5 | Merge into task planning |
| 9 | 8 Weekly Productivity Review | 3 | 4 | 4 | 4 | 5 | 4 | 2 | 5 | Local factual review later |
| 10 | 12 Personalized Workflow Learning | 3 | 4 | 4 | 4 | 5 | 5 | 3 | 5 | Supporting policy, not standalone product |
| 11 | 2 Forgotten-Response Detector | 5 | 3 | 2 | 3 | 2 | 2 | 4 | 3 | High value, conditional Gmail gate |
| 12 | 11 Proactive Document Preparation | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | Merge into confirmed-task suggestions |
| 13 | 14 Project Progress Tracking | 4 | 3 | 2 | 3 | 3 | 2 | 3 | 4 | Postpone until explicit project/task model |
| 14 | 10 Cross-App Research Assistant | 4 | 3 | 2 | 3 | 2 | 2 | 4 | 2 | Start with user-selected sources; postpone automatic cross-app collection |
| 15 | 13 Repetitive Task Discovery | 3 | 2 | 2 | 2 | 3 | 3 | 4 | 4 | Postpone; no surveillance |
| 16 | 7 Commitment Tracker | 4 | 2 | 2 | 2 | 2 | 2 | 4 | 2 | Reject broad automatic promise; permit confirmed proposals later |

Reuse anchors are the Calendar/EventKit services, Quick Reminder creation, Pomodoro engine/store, selected-file Shelf, Home Quick Actions, existing activity policy and pure Stage25 suggestion rules. Their source-level limits are documented in [01](01-current-architecture.md). No candidate assumes a shipping mail reader, browser tracker or AI system.

## Evaluation of all sixteen candidates

### 1. Smart next-action suggestions

**Experience/example:** after a meeting, show “Review chapter 4 for 20 minutes” because a user-confirmed task is due tomorrow and a 25-minute calendar gap exists. Inputs: confirmed task inventory, due meaning, user priority, optional duration/energy preference and selected Calendar. Permissions: optional Calendar/Reminders; no screen monitoring. Missing duration or effort estimates produce a request for input, not invented precision.

**Judgments:** I4—frequent prioritization friction; F4—bounded scoring is straightforward once tasks exist; S4—small rules engine; R4—explainable ranking over explicit tasks; P5—local minimal metadata; U4—Stage25 ranking/timer/Calendar reuse, TaskStore still new; D3—many task apps rank work; A5—no model call required.

**Limits/false positives:** “urgent” is not necessarily important, gaps may include travel or unrecorded work, and an estimate can be wrong. Complexity **medium**. AI is optional for wording/extraction; rules/APIs can run locally. Depends on A's task inventory/brief infrastructure, not overnight scheduling or D. Friction: task confirmation and occasional duration input. Recommend an on-demand ranked shortlist with reasons, one suggestion at a time and easy dismiss; avoid a universal “best task” claim.

### 2. Forgotten-response detector

**Experience/example:** “Alex asked for your availability two working days ago; may need a reply,” or “You asked Alex for a file; no later relevant response seen.” Inputs: authorized thread history, participants/aliases, sent/draft status, request evidence and working-day preferences. Permissions: connector OAuth and cloud egress if used.

**Judgments:** I5—expensive frequent missed follow-ups; F3—mail access possible but inference/account identity are hard; S2—sync/aliases/policy work; R3—can assist, cannot prove all requests answered; P2—sensitive mailbox access; U2—no mail connector today; D4—good context-aware follow-up has value; A3—incremental sync helps, extraction and assessment can cost.

**Limits/false positives:** replies elsewhere, assistant/delegate responses, automated mail, multiple requests per thread and drafts. Complexity **high**. Rules handle direction/age; AI can classify requests but is not infallible. Partly local after authorized sync; full inference need not run locally. Depends on A's mail-source/task model and B's drafting intent, not D. Friction: OAuth/trust/review. Merge into the conditional mail connector and use “may need reply,” never unread-equals-unanswered. See [02](02-morning-brief.md).

### 3. Adaptive study assistant

**Experience/example:** select a textbook chapter, generate five cited practice questions, then schedule a review from a confirmed exam date. Inputs: authorized excerpts, topics, exam/task dates and explicit answer feedback. File access and optional Reminders/Calendar suffice.

**Judgments:** I4—high for students, less universal; F4—selected text/PDF generation is available; S3—extraction/question evaluation adds work; R3—model questions/answers can be wrong; P4—user-selected study material contains less incidental data; U3—Shelf/timer reuse, retrieval is new; D4—study in the notch fits the audience; A3—long material/repeated generation costs.

**Limits/false positives:** incorrect answers, diagrams/math not extracted, syllabus mismatch, copyright/DRM and guessed mastery. Complexity **medium-high**. AI helps generate/explain questions; rules can handle spaced review and deadlines locally. Depends on C's file/context/retrieval path and A for review tasks; not D. Friction: choose material and confirm schedule. Recommend selected-excerpt practice with page evidence, editable answers and no claim of pedagogically validated mastery. Delay adaptive scheduling until there is real feedback data.

### 4. Resume where you left off

**Experience/example:** after returning, show a paused Focus session, a user-pinned chapter and the last explicitly saved task. Inputs: Notchium-owned timer/task state and user-pinned references. No app/browser history collection or AX/Screen Recording required.

**Judgments:** I4—frequent interruption recovery; F4—owned-state restoration is tractable; S4—small snapshot/projection; R4—reliable for observed app-owned facts; P5—explicit bookmarks/state only; U4—timer/store/Shelf reuse, resume projection new; D3—useful but familiar; A5—entirely local rules.

**Limits/false positives:** changed/moved documents, stale bookmarks and a user who intentionally abandoned the task. Complexity **medium**. AI is unnecessary; optional prose adds little. Depends on A's return trigger/brief and C only for explicit saved excerpts. Friction is pin/save, not continuous monitoring. Merge into the on-return brief. Reject the broader interpretation of silently recording every open tab/window or reconstructing another application's unsaved state.

### 5. Pre-meeting briefings

**Experience/example:** before a tutorial, offer join link, last explicitly attached notes and two user-confirmed discussion points. Inputs: selected Calendar event plus deliberately linked notes/tasks; attendees and email are not currently in Calendar summaries. Calendar/file authorization; connector permissions only for later optional sources.

**Judgments:** I4—useful repeated preparation; F4—bounded source bundle is feasible; S3—event/source linking and dedup required; R4—strong for curated evidence; P4—restricted relevant sources; U5—Calendar/join/reminder ownership already exists; D3—common elsewhere, notch timing helps; A4—local facts free, optional short summary cheap.

**Limits/false positives:** wrong linked document, canceled/rescheduled meetings and speculation about participants. Complexity **medium** locally, **high** with mailbox search. AI optional; local checklist can ship first. Depends on A's occurrence/freshness and C for user-requested note summary; B/D unnecessary. Friction: attach relevant source once. Extend the existing meeting card instead of adding another 60/30/5-minute alert. Evidence and missing-source states matter more than fluent prose.

### 6. Intelligent focus sessions

**Experience/example:** a 35-minute calendar gap offers a 25-minute focus session for a selected task, leaving a buffer before the meeting. Starting remains an explicit existing timer action. Inputs: Pomodoro state/preferences, explicit task and optional selected Calendar. No new permission when using only timer/task data.

**Judgments:** I4—frequent reduction in planning friction; F5—existing pure timer/Calendar primitives; S4—small policy/projection work; R5—bounded deterministic recommendation; P5—local metadata only; U5—Pomodoro and activity lifecycle directly reusable; D3—incremental feature, strong fit; A5—no inference needed.

**Limits/false positives:** unknown travel/setup time and unrecorded obligations. Complexity **low-medium** after task projection. AI is unnecessary for timing; optional explicit-text help can clarify a task. Works locally, depends on A only for a confirmed task inventory, not B/C/D. Low friction: accept, shorten, dismiss. Never start/pause a session automatically or infer system Focus status from unavailable free-build adapters. Keep existing timer control/notification ownership.

### 7. Commitment tracker

**Experience/example:** detect “I'll send you the draft Friday,” propose a task with quote/date evidence and ask the user to confirm. Inputs: sensitive emails/messages/documents and evidence of fulfillment. Every connector requires independent authorization; broad message scraping is absent.

**Judgments:** I4—missed commitments matter; F2—fulfillment often occurs outside observed sources; S2—cross-source identity/state complexity; R2—high false positive/negative risk; P2—broad private information; U2—mostly new connectors/models; D4—would differentiate if reliable; A2—repeated cross-source analysis expensive.

**Limits/false positives:** sarcasm, quotes, delegation, conditional promises, renegotiation, phone calls and completion outside Notchium. Complexity **very high**. AI helps extract proposals; rules cannot prove semantic fulfillment. Fully local only with narrower supplied text/rules or an eligible local model, not the chosen external-provider default. Depends on A/C and conditional connectors. High correction/trust friction. Reject automatic comprehensive tracking for now; merge explicit confirmed commitments into TaskStore with no “all fulfilled” claim.

### 8. Weekly productivity review

**Experience/example:** show “Four focus sessions; six confirmed tasks completed; three still open,” then upcoming deadlines. Inputs: app-owned completion/feedback history and permitted Calendar/tasks. No additional permission beyond those sources.

**Judgments:** I3—weekly rather than daily payoff; F4—factual aggregation; S4—small queries/views; R4—reliable within known coverage; P5—local aggregates; U4—timer records/TaskStore, not a full work log; D2—generic review feature; A5—rules suffice.

**Limits/false positives:** records represent observed app use, not all work or productivity quality. Complexity **medium** once history exists. AI is optional for a user-requested narrative; rules work locally. Depends on A's confirmed history and feedback, not B/C/D. Low friction if on-demand; avoid automatic guilt notifications or “productivity scores.” Fold into the companion detail window rather than a new notch page.

### 9. Deadline conflict detector

**Experience/example:** two user-estimated assignments require six hours before tomorrow, but the selected calendar shows two free hours; offer a review. Inputs: explicit durations/deadlines, working hours/buffers and calendar coverage. Optional Calendar/Reminders access.

**Judgments:** I4—overload warnings can prevent misses; F4—interval/capacity arithmetic; S4—bounded rules; R3—task effort/availability uncertain; P5—local metadata; U4—Calendar/tasks/ranking reused; D3—reasonable integration value; A5—no AI required.

**Limits/false positives:** parallel work, flexible deadlines, private events, incomplete calendars and underestimated effort. Complexity **medium**. AI unnecessary for math, optional for explanation. Works locally; depends on A's tasks and Candidate15's planning inputs. Friction: duration/working-hours setup. Merge into planning, label assumptions and “possible overload,” never assert an impossible schedule from incomplete data.

### 10. Cross-app research assistant

**Experience/example:** user chooses two PDFs and a webpage excerpt, asks for a cited comparison, and saves an outline. Inputs: explicitly chosen source set, retrieval and provenance; file authorization and optional browser/AX/capture scopes. Account connectors are separate.

**Judgments:** I4—valuable but episodic; F3—bounded sources work, arbitrary cross-app extraction does not; S2—many adapters/evidence handling; R3—grounding and missing context remain hard; P2—combining sources magnifies disclosure; U2—document/browser infrastructure new; D4—good workflow potential; A2—retrieval/multi-source inference and agents can cost.

**Limits/false positives:** conflicting editions, missing pages, unsupported sites and plausible fabricated citations. Complexity **high**. AI helps synthesis; local rules can collect/index but not deliver equivalent semantic synthesis. Depends on C; D only for later approved external output actions. Friction: source selection/preview. Start as a selected-source C workflow, postpone unattended cross-app collection and automatic destination writes.

### 11. Proactive document preparation

**Experience/example:** a user-confirmed “submit lab report” deadline offers “Create an outline from these notes.” Inputs: confirmed task, explicit task-to-document association and selected material. File/task permissions and user-invoked cloud egress.

**Judgments:** I3—situational benefit; F3—needs reliable task/source association; S3—moderate linking/templates; R3—wrong document/intent is common; P3—content may be sensitive; U3—task/Shelf/AI reuse, association new; D3—useful but generic; A3—generation cost plus false-trigger waste.

**Limits/false positives:** deadline already handled elsewhere, incorrect template/requirements, unavailable notes. Complexity **medium-high**. Rules trigger the suggestion; AI creates optional prose. Local templates can work without AI. Depends on A and C, later D for external file mutations. Friction: confirm source/outline. Merge into next-action suggestions rather than autonomously pre-generating documents. Never overwrite the original.

### 12. Personalized workflow learning

**Experience/example:** repeated dismissals of a category reduce its surfacing; “Never suggest this” disables it. Inputs: Notchium exposure/accept/dismiss/snooze receipts only, not app usage surveillance. No additional permission.

**Judgments:** I3—improves other features rather than creating independent value; F4—existing bounded feedback reducer; S4—persistence/integration still needed; R4—explicit feedback is interpretable; P5—content-free local receipts; U5—Stage25 learning directly relevant; D3—quality differentiator; A5—rules only.

**Limits/false positives:** dismissal can mean “bad timing,” not dislike; inactivity isn't always rejection. Complexity **medium**. AI unnecessary; works locally. Supports A and all proactive candidates, not a new core feature. Friction: low if controls are clear. Preserve explicit disablement across resets and durable suppression across relaunch; keep optional learning reset separate from replay authorization. Integrate rather than launch a standalone “workflow intelligence” product.

### 13. Repetitive task discovery

**Experience/example:** after several explicit Notchium-owned successful sequences, suggest saving a user-reviewed routine. Inputs: opted-in action receipts with exact task/action parameters. Avoid observing raw keystrokes/app usage. Each future automation still needs its own scope.

**Judgments:** I3—value limited to repeated patterns; F2—little existing event coverage and semantics; S2—sequence matching/execution safety; R2—similar actions need not mean an intended routine; P3—bounded receipts manageable, expansion dangerous; U3—Quick Actions/feedback help, event hooks new; D4—interesting if trustworthy; A4—local rules possible.

**Limits/false positives:** coincidental sequences, retry noise, changed context and hidden Shortcut side effects. Complexity **high**. AI unnecessary initially; rules can discover exact repeated patterns locally. Depends on D's verified action receipts and Candidate12 feedback. Friction: explain/approve routine. Postpone until enough explicit action data exists; no continuous desktop monitoring and no automatic creation/enabling of a system Shortcut.

### 14. Project progress tracking

**Experience/example:** a user groups confirmed tasks under “Thesis” and sees open milestones/blockers. Inputs: explicit project membership, task state and user-maintained milestones. Additional external project tools require separate connectors.

**Judgments:** I4—strong for project-oriented users; F3—manual structure feasible, inferred progress unreliable; S2—new project model/migrations/UI; R3—status stale without deliberate updates; P3—aggregates sensitive plans; U2—no current project domain; D3—crowded product category; A4—rules/local storage affordable.

**Limits/false positives:** checkbox counts do not measure meaningful progress; missed dependencies and unrecorded work. Complexity **high**. AI optional for summaries, not needed for an explicit board. Local operation possible. Depends on A's TaskStore, C for explicitly supplied source summaries; not D by default. Friction: maintaining another project system. Postpone unless users ask; prefer source links over duplicating a full project-management application.

### 15. Calendar-aware task planning

**Experience/example:** choose a 90-minute essay task; propose two 45-minute blocks within working hours before its confirmed due date. Inputs: selected Calendar events, timezone, explicit task durations, work hours and buffers. Read Calendar first; calendar writes require a separate future capability and approval.

**Judgments:** I5—turns priorities into usable time; F4—interval planning is tractable; S3—constraints/recurrence/write UX add work; R4—good for explicit inputs with caveats; P5—local planning; U4—Calendar/timer/task reuse, event mutation new; D3—existing category, notch execution helps; A5—no model needed.

**Limits/false positives:** free time is not necessarily available time; estimates and timezone transitions matter. Complexity **medium-high**. Rules solve allocation locally; AI can optionally clarify intent. Depends on A task inventory, and D only when adding events externally. Friction: initial hours/durations, then preview. Prioritize proposed blocks and explicit timer starts; do not automatically rearrange meetings or claim calendar creation already exists.

### 16. Context-aware quick actions

**Experience/example:** paste an error and choose Explain, or supply an email excerpt and choose Reply. Later an explicit “Use selection” offers Summarize/Create Task from that evidence. Inputs: user-supplied context initially; optional app/window metadata and requested AX/file/capture later.

**Judgments:** I4—frequent reduction in app switching; F5—bounded intent selection and text generation; S4—shared chat intent UI; R4—reliable invocation, generated content still needs review; P4—explicit scope with cloud disclosure; U4—Home/shell/actions/presentation reused, context providers new; D4—natural compact notch advantage; A4—short requests and rules-based intent choices.

**Limits/false positives:** app identity alone cannot establish user intent or document content; generated quick actions may be irrelevant. Complexity **medium** using C. Rules choose the few available actions; AI needed for explanation/drafting, not the action menu. Partly local; generation uses the chosen external provider. Depends on C, B is a Reply intent, D only for later approved Create Task writes. Low friction after BYOK setup. Prioritize explicit entry, three or four relevant choices, no automatic capture on every app switch.

## Five strongest candidates: concrete delivery guidance

| Candidate | First useful increment | Evidence/acceptance gate | Stop or merge condition |
|---|---|---|---|
| Intelligent focus | Suggest a session fitting a known gap, user starts existing timer | Deterministic gap/buffer tests; no automatic start; deny Calendar leaves ordinary timer usable | If inaccurate availability causes frequent rejection, retain manual duration suggestions only |
| Context quick actions | Explain/Summarize/Reply over supplied text in the first AI release | Users complete a useful task with explicit scope, Stop/Copy and no hidden reads; evaluate unsupported claims | If BYOK/setup outweighs saved switching, improve onboarding before adding surveillance/integrations |
| Calendar task planning | Preview blocks from confirmed duration/deadline and selected calendars | Correct DST/working-hours/overlap tests; no source writes before approved execution stage | Merge conflict detector; avoid turning notch into a calendar editor |
| Next action | Rank three confirmed tasks with short deterministic reasons | Feedback survives relaunch; no invented urgency; available-time uncertainty visible | Merge document-preparation nudges; do not ask model to invent a task inventory |
| Pre-meeting brief | Existing meeting card plus attached notes/checklist | Same occurrence ownership as Calendar alerts, missing evidence stated, source link always available | If no relevant attached source, keep ordinary meeting card rather than generate generic filler |

Suggested product validation is qualitative early-access feedback, then opt-in aggregate counts: useful completion, explicit acceptance/dismissal and repeated use. Do not instrument raw screen content, message bodies or entire user activity histories to measure success. Targets should be set after a small baseline study; this research does not invent conversion or retention rates.

## Additional ideas beyond the requested list

These are rules-first possibilities using existing native integrations, not additional MVP scope.

| Idea | Example and native fit | Limit / why better than another generic notification |
|---|---|---|
| Meeting collision with owned focus timer | Upcoming meeting offers “Finish this session in 5 min” | Only proposes; existing timer stays authoritative, avoids redundant alerts |
| Download-to-next-step handoff | A genuinely completed observed download offers Reveal/Add to Shelf | Reuse publisher terminal evidence; no inference that every file in Downloads is complete |
| Selected-resource availability check | Before a user-pinned session, warn that its external-volume file is unavailable | Check bookmarked resources only; gives a repair action before the task starts |
| Battery-aware session duration | On battery, offer a shorter session when existing battery/timer evidence makes it useful | No fabricated remaining-runtime estimate or privileged power control |
| Meeting-link readiness | Before a real upcoming event, indicate missing/unsupported join link and offer Open Calendar | Fits existing Calendar card; never invent/join a guessed URL |
| Quick Reminder save recovery | If a chosen list disappears, preserve the user's draft and offer a valid writable list | Directly prevents lost work; uses actual save failure instead of speculative proactivity |
| Temporary work-resource bundle | Explicitly pin a task, file and Quick Action for a session, then offer to clear the bundle on completion | User-curated context, no open-window recorder; saves repeated navigation |
| Gentle attention queue | Accumulate low-priority Notchium events while its own timer is running, show a compact return count | Cannot read other apps' notifications; respects existing activity expiry and privacy |

Each needs deduplication against existing battery/meeting/download/timer behaviors. The objective is better timing and actionable recovery, not a new alert for an event Notchium already presents. Shared policy and roadmap: [06](06-shared-ai-architecture.md), [08](08-implementation-roadmap.md).
