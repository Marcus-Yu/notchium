# Context-aware email reply generation

Research date: 2026-10-21. **Verdict:** generating a draft from explicitly supplied conversation text is highly feasible and belongs in the initial assistant. Universally reading and safely inserting into any email client is not reliable enough for an MVP promise. The approved initial output is preview plus explicit Copy/manual paste; sending always remains under user control.

## Reuse and missing pieces

Reuse `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchPanel.swift` keyboard eligibility, `NotchiumPanelController.swift` focus/Escape ownership, and the existing notification/auxiliary-interaction patterns. `NotchiumServices/ClipboardService.swift` already supplies explicit writes; use that boundary without enabling monitoring. `NotchiumServices/ShortcutService.swift` runs Apple Shortcuts and does **not** register global key combinations. Add a dedicated invocation adapter. There is no existing mail connector, app-content AX reader, extension bridge or browser DOM integration. See [01](01-current-architecture.md).

The shared `ContextEngine`, request/streaming/budget boundary and optional companion window come from [04](04-screen-aware-chat.md) and [06](06-shared-ai-architecture.md). Email-specific logic should be a small `EmailDraftingService` consumer, not another capture or provider stack.

## Architecture comparison

| Approach | Conversation fidelity | Insertion capability | Constraints / recommended use |
|---|---|---|---|
| User-supplied text | Exactly the supplied excerpt; may omit participants/history | Copy and user paste | Lowest permission/friction engineering path; honest about partial context; initial release |
| AX only | Depends on each app's accessibility tree and loaded content | Only supported writable editor attributes/actions | Useful optional selected-text adapter; cannot claim full-thread or universal editor support |
| Screen capture + vision | Visible pixels only; quoted/hidden history may be missing | No native editor identity or safe write guarantee | Explicit fallback for reading, not a reason to guess an insertion target; greater privacy/latency/cost |
| Browser extension | Can bind account/tab/thread/composer and extract loaded DOM | Best opportunity for verified editor-specific insertion | DOM drift, extension install/host grants, transport authentication, browser packaging/store review; conditional production lane |
| Gmail API | Thread/message data independent of browser accessibility | Creates server-side threaded drafts; does not populate a particular live browser composer | OAuth restricted scopes, verification/assessment, alias/thread correctness; conditional later connector |
| Hybrid | Prefer supplied/structured text; AX/vision fallback; verified API/extension writes | Capability-driven, separate read/write paths | Recommended production design if each integration gate is cleared |

A browser extension and Gmail API solve different problems: one binds the user's active editor; the other binds account/thread server state. Their permissions are not interchangeable.

## Browser/client reliability matrix

The following are engineering expectations to validate, not results of browser testing in this task.

| Gmail surface | Selected text/AX | Screenshot | Extension | API |
|---|---|---|---|---|
| Chrome | Selected accessible text may work; full thread depends on Gmail DOM/AX exposure and expanded history | Visible portion only | Chromium content-script/native-messaging path; site-specific editor adapter needed | Same account/thread API semantics regardless of browser |
| Safari | WebKit AX exposure and editing behavior require separate qualification | Visible portion only | Safari Web Extension app packaging/native messaging differs; no existing target | Same API semantics; account matching still necessary |
| Firefox | AX tree/selection differs from Chromium; test independently | Visible portion only | WebExtension plus Firefox native-host manifest/allowed-extension identity | Same API semantics |
| Native Mail/other clients | Each app may expose different text, roles and compose actions | Visible portion only | Browser extension does not apply | Gmail API applies only to Gmail account data, not every mail service/client |

There is no honest percentage reliability estimate before testing. Virtualized lists, collapsed quotes, localization, multiple accounts, pop-out composers, rich text, extensions and enterprise configurations all affect behavior. Do not infer compatibility from an app being Chromium-based.

## Practical MVP data flow

1. User invokes a conventional configured shortcut/menu action, pastes conversation text and optionally specifies intended outcome, tone and relevant facts.
2. Show the exact excerpt/source scope and selected provider. Missing recipient/history is labeled partial; ask for missing facts rather than manufacture availability, attachments, promises or dates.
3. `EmailDraftingService` builds a bounded request with no tools. `AIRequestCoordinator` enforces egress authorization and budgets and streams a proposed reply.
4. Render editable draft text, Stop/Retry, Copy and Clear. Copy is an explicit clipboard mutation with a clear success indication; the user chooses where to paste and send.
5. Keep context and draft session-only unless explicitly saved. No background mailbox scan or external draft creation occurs.

No AX or Screen Recording permission is needed for manually pasted text. A future “Use selection” reads through AX only after that capability is enabled; pasting into Notchium is the fallback. Do not synthesize Command-C to discover selection by silently mutating the clipboard.

## Active context and safe insertion design

Capture `NSWorkspace` frontmost application identity **before** presenting/activating Notchium. A future `FocusedContextProvider` resolves the target app's AX focused element, selected text, role/subrole and bounded surrounding content. Native handles remain within the adapter; the request gets an immutable origin token and evidence. Filter secure/password fields and excluded apps; lack of a secure-role signal is not proof that arbitrary content is safe.

Installed macOS 27 SDK headers confirm `AXUIElementCopyAttributeValue`, `AXUIElementIsAttributeSettable` and `AXUIElementSetAttributeValue`, available for this deployment baseline. Crucially, `kAXSelectedTextAttribute` is documented **read-only**; `kAXSelectedTextRangeAttribute` is writable. Do not design insertion by assigning selected text. A target's writable `AXValue` or a supported editor action must be capability-probed. Replacing a whole value can overwrite signatures, rich formatting or user edits and is not a generic safe substitute. [Apple AX interface](https://developer.apple.com/documentation/applicationservices/axuielement_h). Header inspection establishes declarations, not browser behavior.

For a later “Insert” capability:

- Bind proposal to original app PID/bundle, window/tab/account/thread/composer identity, editor revision/content hash, selection range and capture generation. A screen coordinate alone is insufficient.
- Require an explicit Insert action and show whether it appends/replaces. An existing nonempty draft requires a diff and an explicit choice; never silently replace it.
- Hide/release the Notchium typing surface, reactivate the original target where supported, then re-resolve and verify the editor and content. Revalidate again immediately before mutation. If context changed, offer Copy instead.
- Do not keep forcing focus if the user switches applications during generation. App activation is not proof of editor focus. Avoid stale AX element references after navigation.
- After writing, read back where supported and verify expected text without asserting the message was sent. Preserve native undo if supported; otherwise disclose that rollback is unavailable.
- A pasteboard-based insertion fallback requires explicit approval, event-post authorization as applicable, clipboard change-count safeguards and editor verification. Do not overwrite a newly changed user clipboard during attempted restoration; do not promise perfect restoration of arbitrary pasteboard providers.
- No keyboard Return/Send sequence and no send-capable tool in the MVP. Never use vision to guess the Send button.

## Gmail API and OAuth implications

Google documents threaded draft/message requirements: supply `threadId`, compliant `References`/`In-Reply-To` headers and matching subject. A Gmail draft is a server-side object; it is not guaranteed to attach to a specific already-open browser reply field. Store the returned draft/message identity and provide an account-aware recovery path. [Gmail threads](https://developers.google.com/workspace/gmail/api/guides/threads).

`gmail.readonly` and `gmail.compose` are restricted scopes. Compose grants sending as well as draft management; there is no claim here of a draft-only least-privilege OAuth scope. If later adopted, the local tool allowlist can forbid send operations even though the credential has broader power. Request read-only and compose incrementally when actually needed; do not request full-mail scope for convenience. [Gmail scope definitions](https://developers.google.com/workspace/gmail/api/auth/scopes).

Public OAuth verification and applicable restricted-data security assessment are an independent release gate. Direct transmission from a desktop client to an AI server must be included in the assessment analysis; BYOK is not a blanket exemption. Confirm exact applicability/cost with Google before committing to a public connector. Workspace Limited Use, disclosure, model-training restrictions, retention and subcontractor handling require review. This is a material conflict risk with the zero-cost constraint, not merely a login-screen implementation detail. See [09](09-security-and-distribution.md) and [Google Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy).

Use Google's native-app system-browser OAuth/PKCE flow with state validation and an approved redirect mechanism, no embedded login scraping or shipped client-secret assumption. Refresh tokens belong in separate Keychain items. [Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).

## Extension production option

A later Chrome-first prototype may use an explicit extension action/context menu and `activeTab`/narrow site permissions, with a native bridge restricted to the expected extension ID. **A shortcut received by the native app does not automatically constitute an extension user gesture or grant `activeTab`.** Either invoke the extension itself or obtain separately justified host permission. No broad all-sites grant or private-browsing capture by default.

Keep API keys in the native app, never in the content script. Authenticate bridge sessions, validate message sizes/schema/origins, bind requests to tab/document generations, and verify composer contents before insertion. Webpage content is untrusted even when delivered by the extension. Chrome's host process/manifest adds installation and executable-inventory work; the current release verifier would need a deliberate reviewed change. Safari and Firefox are separate qualification/distribution lanes, not automatic ports. [Chrome activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Firefox native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging), [Safari native app messaging](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app).

## Proposed services and UI

`EmailDraftingService` receives a `ConversationContext` of participants, ordered message excerpts, completeness and evidence, plus a `ReplyIntent` of user-provided facts. `DraftSuggestion` contains editable text, missing-information flags and evidence references. `DraftInsertionProviding` is a separate optional capability; its absence never blocks generation.

```swift
protocol EmailDrafting: Sendable {
    func draft(_ intent: ReplyIntent, context: ConversationContext) async throws
        -> AsyncThrowingStream<DraftEvent, Error>
}
protocol DraftInsertionProviding: Sendable {
    func prepare(_ draft: DraftSuggestion, target: ReplyTarget) async throws -> InsertionPreview
    func insert(_ approved: ApprovedInsertion) async throws -> InsertionResult
}
```

Use the same invoked AI surface as chat; Reply is a mode/intent, not a seventh permanent page. Keep generated text separate from source text and preserve manual edits on retries. A companion window supports long conversations/diffs. Double-Command is deferred: a modifier-event state machine must distinguish left/right Command, chords, hold/release, interleaved keys, Secure Input and timing/accidental triggers, and must not consume ordinary Command shortcuts. Prefer a registered conventional hotkey plus menu fallback. No new external dependency is needed for supplied-text drafting.

## Failure cases, tests and acceptance

Complexity: **medium** supplied-text drafting using shared chat; **high** supported-client insertion; **high** public Gmail/extension integration including distribution/policy.

Test empty/partial threads, ambiguous recipients, reply-all expectations, stale account/tab/window, app quit during generation, user edits, quoted hostile instructions, missing attachments, invented dates/commitments, provider refusal and interrupted streams. Test multilingual text and emoji without corrupting grapheme/UTF-16 ranges. Browser tests must cover expanded/collapsed thread history, multiple composers and nonempty drafts; mocks cannot certify editor compatibility.

Ordered plan:

1. Deliver the shared explicit-text assistant and budget/privacy model.
2. Add a Reply intent/template with user constraints and partial-context messaging; evaluate grounded drafting.
3. Add Copy and session cleanup; validate keyboard focus and existing Clipboard privacy behavior.
4. Add optional selected-text AX extraction behind a packaged permission spike.
5. Prototype one qualified insertion path with revision checks; fail closed to Copy.
6. Only after cost/policy/packaging gates, pursue a Chrome-specific extension and/or Gmail draft connector; qualify Safari/Firefox separately.

MVP accepts supplied text, produces an editable/cancellable suggestion, identifies missing facts, copies only on explicit action, persists no default chat history, performs no mailbox scan/insertion/send, and remains usable with AX/Screen Recording denied. A synthetic test corpus must detect fabricated commitments rather than merely measure fluent wording. UI tests verify that source/app switching cannot redirect a write, since no automated write exists in the MVP.

Production hardening requires measured per-client compatibility, versioned DOM adapters, rollback/readback behavior, prompt-injection tests, account/alias correctness, OAuth revocation/deletion, Keychain upgrade tests and a real ad-hoc artifact acceptance matrix on macOS 26+. General client support remains best-effort; an unsafe/unknown target always retains Copy as the supported outcome.
