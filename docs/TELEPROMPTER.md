# Teleprompter

The Teleprompter page is available for meetings and rehearsal. Meeting detection offers a quiet Home shortcut; it never changes the selected page or starts listening.

## Use

1. Open Teleprompter in the notch, or choose **Teleprompter Scripts…** from the menu bar.
2. Type/paste a script, or import a `.txt`, `.rtf`, or `.docx` file. Review extracted text, then choose **Save Script** in the window toolbar (⌘S). Save and Open Reader stay outside the scrolling document and reading options.
3. Choose **Open Reader**, select a reading mode, and press Start. Use the smaller/larger text buttons in the reader header to adjust 16–40 pt text during playback; the same range is available under Reading Options in the editor.
4. Click a line to reanchor, use previous/next paragraph or Restart, and Pause/Stop when finished.

Teleprompter uses a 655 × 333 pt expanded shell, about 25% larger in each dimension. Other pages retain 524 × 266 pt. One stable 740 × 390 pt hosting panel accommodates both sizes and the existing minor-activity extension; page changes reconcile the native hit region without moving the panel. A separate native, resizable editor holds preparation controls. Mode, language, pace and text size are runtime settings; saved scripts persist across launches.

| Mode | Behavior | Microphone |
|---|---|---|
| Voice Follow | Matches recognized words to the nearby script and advances only with matching evidence | On after Start |
| Fixed Speed + Voice Pause | Scrolls at the selected pace while speech matches; lead is bounded to a few confirmed words | On after Start |
| Fixed Speed | Continuous 50–300 words/minute until paused or stopped | Off |

Automatic waiting keeps local recognition active so the script can resume. Start pins the reader open, including while microphone permission or speech assets are being prepared. Moving the pointer away or clicking meeting controls leaves an active reader open. Explicit Pause/Stop releases capture and restores ordinary outside-click dismissal. Selecting another page, explicitly closing the notch, opening the editor, or hiding the last reading surface pauses the session and retains position. The active script is immutable: saving/importing is disabled during reading. Source-document edits or deletion cannot move an active session.

## Architecture

`NotchiumTeleprompterFeature` owns library/editor state, the reading session and conservative meeting suggestion policy. Core owns immutable script/token models and bounded sequence alignment. Services own native document import, status-only process observation, microphone capture, format conversion and Apple's `SpeechAnalyzer`/`SpeechTranscriber`. Persistence owns an atomic, versioned local library. The shell depends only on `NotchTeleprompterRendering`; composition injects real providers in production and memory/mock providers in fixtures.

Audio tap buffers are copied into bounded Sendable packets, converted off the tap, and supplied in a declared compatible signed-Int16 mono format. Microphone queues retain roughly two seconds of headroom for short scheduling stalls; sustained overflow produces a distinct processing error rather than a missing-microphone error. Raw input metering is independent of conversion and recognition. Transcripts replace overlapping audio ranges, not append-only text. Alignment normalizes matching units while the reader preserves original punctuation, symbols and spacing. Generation checks reject stale work after pause/restart/seek.

Word following needs enough phrase evidence. Silence, unrelated speech and ambiguous short/common phrases hold position. Ordinary tracking searches nearby; a unique long phrase can recover beyond that region after skipped headings, missed sentences or a delayed recognition batch. Short or repeated distant phrases still need manual reanchoring. English contractions, ordinal dates, spoken years and minor anchored spelling differences have regression coverage, including the Declaration opening and “We hold these truths” paragraph. Other offered locales use basic lexical matching and still require language-specific hardware qualification.

Nonfinal recognition can end mid-word (for example, “unanim” before “unanimous”). An exact prefix of the next script word keeps the existing bounded matching grace; it neither counts the unfinished word nor extends the grace without completed-word progress. Final/off-script evidence remains strict. Reader lines are measured once per script/width/font change, rather than on every microphone update. A native animatable text renderer moves the underline and fades consumed words over stable glyph layouts; line changes scroll with a nonbouncing transition. Reduce Motion applies progress immediately without spatial animation. Presentation animation never predicts or advances unrecognized words.

The active reading line is positioned one text-line below the viewport top, with padding at both ends so the opening and final lines can use the same position. The inset follows the selected font size. At Start/Resume or a deliberate seek, exact recognition of the first word can advance immediately at that specific position; the initial three-word prefix does not require a full phrase first. This startup path cannot search ahead or skip unrelated words, and incomplete printed numbers remain unconfirmed. Wider recovery still requires the normal phrase evidence. This reduces matching delay after recognition supplies a word; it does not remove the speech engine's own recognition latency.

## Documents and storage

Native TXT/RTF/DOCX readers produce editable text snapshots without requiring Word. Input size, DOCX declared expansion and extracted text are capped. Layout, headers, footnotes, comments, images and complex revisions are not promised to survive conversion. No OCR, legacy `.doc`, PDF import, source editing, Google OAuth or OneDrive connection is included in this first release. Google Docs can be pasted or exported to DOCX/TXT. Connected Google Docs and Microsoft accounts remain a later milestone.

Scripts are stored as private, atomic JSON under Application Support at `com.marcusyu.notchium/Teleprompter/scripts-v1.json`, with a 100-script / 16 MiB library cap and 1 MiB per-script cap. Directory/file permissions are 0700/0600; this library is not application-encrypted. No external-source URL is retained. Failed loads preserve the original bytes and block saving an empty replacement; Delete removes the app-managed saved script without touching its source. Unsaved drafts remain in memory until quitting.

## Privacy and limits

- Only explicit voice-mode Start requests the microphone. No recording, transcript archive, cloud transcription or LLM is used. Local speech assets may download before capture starts.
- The microphone menu beside the reader's input meter and Reading Options in the editor offer System default or a specific input. The default option names the actual current default device. Selection applies only to Notchium's audio engine; it does not change macOS or conferencing-app routing. Changing input pauses reading and requires explicit Resume. Input levels and the actual active device are exposed separately from script matching, so a silent input can be distinguished from recognized off-script speech.
- Native Zoom/Teams input yields probable-call evidence. Browser input also needs a current authorized calendar event with a meeting link. Unsupported clients, muted clients and unscheduled browser calls can be missed; manual access always works.
- Speaker identity is not established. Meeting audio leaking from laptop speakers into the microphone can affect matching; a headset reduces this risk.
- Capture invisibility is not guaranteed. Check the conferencing application's actual sharing preview before presenting. No Screen Recording permission or private capture-blocking API is introduced.
- No 30–60 minute live-call, battery, microphone coexistence, packaged permission-upgrade, or minimum macOS 26 hardware acceptance is claimed by automated tests.

## Validation

Tests cover matching/repeated phrases, punctuation and Unicode, revised transcript ranges, silence/off-script holding, three scrolling modes, clock/cancellation races, source-snapshot isolation, native document parsing, persistence/corruption preservation, meeting evidence, bounded audio conversion and lifecycle mapping. Native offscreen fixtures cover the empty/saved reader, long scripts, large text and the editor at supported sizes. UI automation uses the isolated `com.marcusyu.notchium.uitesting` identity and mocks; it never opens the real microphone or script library.

Before advertising voice-follow reliability, qualify real Zoom/Teams/Meet calls on macOS 26 and the current OS with built-in, USB and Bluetooth microphones. Measure pause/reacquisition latency, incorrect jumps, energy and call quality. Include input changes, permissions/revocation, sleep/session inactivity, accents, names/numbers, repetitions, digressions and other speakers. Test full-display and window sharing separately.

### Engineering receipts — 2026-11-03

- Swift package build passed with Swift 6 and the macOS 26 deployment target.
- Targeted feature, architecture, page, display and timer regression suites passed; native fixtures also rendered ten reader/editor PNGs at the supported sizes.
- The isolated Xcode app build and `TeleprompterUITests.testCreateScriptReadAtFixedPaceAndPause` passed. The test opens the retained editor through an explicit DEBUG mock fixture, types/saves a script, opens the reader, selects Fixed Speed, starts/pauses scrolling, and reopens the editor to verify saved text. It does not claim native menu/hover traversal coverage.
- Editor-toolbar regression: Save/Open Reader use native toolbar items outside the nested scroll views. The normal create/read flow passed after this change, and `testLongScriptSaveStaysReachableAtMinimumWindowSize` passed in a native titled window with 780 × 500 pt content: a long script was entered/scrolled, Save remained visible and hittable above the text editor, and clicking it saved successfully.
- Voice-follow repair: deterministic cases reproduce/fix delayed long recognition batches, skipped Declaration headings/paragraphs, “July fourth seventeen seventy-six,” quiet input, device selection, and hover/outside-click cancellation during capture preparation and reading. The actual Apple transcriber also recognized a 15-second synthetic Declaration excerpt through the production packet/conversion bridge simulating 24 kHz mono Bluetooth input, with progressive/final results; no physical microphone, speakers, or user audio were used for that probe. Actual microphone routing and long real-call qualification remain outstanding.
- Final voice-follow acceptance: 129 targeted tests passed, including late final revisions after silence and fresh repeated speech after a seek. `testVoiceInputAndReadingSurviveClickingMeetingControlsOutsideTheNotch` also passed in the isolated native app, verifying that the input control is available and an outside menu click leaves the active reader running.
- Larger-reader/motion acceptance: 219 targeted tests passed, including page-size/hit-region reconciliation, source-preserving font/width reflow, actual Declaration subword revisions, finality ordering, and bounded partial-word grace. Native fixtures rendered the 655 × 263 pt page content at 16, 24 and 40 pt. The isolated app build and fixed-pace create/read/pause UI flow passed; the voice fixture also passed with animations enabled, live 24→26→25 pt changes, expanded content width, and outside-click continuity. These mock UI checks do not qualify live microphone accuracy or measured frame pacing on physical hardware.
- Reading-position/startup acceptance: 120 feature/architecture tests passed, with new cases for first- and second-word progress, incomplete/unrelated opening words, complete spoken numbers, and first-word recovery after a deliberate seek with stale-audio rejection. The isolated native UI test passed with animations enabled and verifies that the active line remains 25–45 pt below the reader top at 25 pt text after live font changes. Native offscreen fixtures also rendered the reading position at 16, 24 and 40 pt. No physical microphone was used.
- Purpose strings were checked in the built app; property lists and whitespace checks passed.
- No microphone, real calendar data, production script library, or conferencing session was accessed by this validation. This host runs macOS 27.0.1; minimum macOS 26 hardware/runtime acceptance remains outstanding.
