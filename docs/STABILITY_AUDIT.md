# Pre-Stage-11 stability audit

Scope: current working tree, including the existing navigation, Reminder, and Caffeine changes. Existing user changes were preserved. No UI redesign or Core Audio architecture change.

## Confirmed bugs and corrections

- Home progress explicitly disabled hit testing over an Open Music background button. It now uses the same interactive seek control as Music.
- A real pointer UI test reproduced a seek click leaving the time at 0:30. The shared SwiftUI drag recognizer was ineffective in the non-key panel. Slider pointer down/drag/up now belongs to a local AppKit responder that accepts the first mouse event; drawing and accessibility remain in SwiftUI. No global input interception or parent high-priority drag was added.
- Paused seek never resumed. The provider now executes seek then play as one action, with one combined position/playing confirmation gate. Intermediate paused snapshots and delayed desktop hints cannot replace that expectation. The session reserves both controls and gives immediate optimistic feedback. Previous/restart retains its existing playback behavior.
- Spotify volume acknowledgements fabricated an authoritative volume snapshot, prematurely releasing optimistic feedback. Volume is now confirmed by a real read after the final drag command; intermediate drag writes do not add polling.
- Releasing a seek after the track changed could submit the cancelled drag against the replacement track. Release now requires an active seek session.
- Music's percentage label appeared/disappeared in the slider's layout during editing. Its space now remains fixed.
- Audio output feedback could remain pinned when confirmation arrived before mouse-up, hiding subsequent hardware volume changes. Mouse-up releases an already-confirmed value. Device changes cancel stale writes, and cancelled requests cannot overwrite a newer device's feedback.

## Ownership and audit coverage

- Navigation: `NotchPageModel` owns selection. Header, Home links, explicit notification activation and the empty-header swipe surface are the writers. Defaults run at fresh expansion; playback does not write selection. Existing collapse-reversal/session ownership fixes retained.
- Activity: MediaSessionController submits the persistent media activity; Calendar and Audio submit notifications through the shared arbiter. Transient notification expiry does not select a page.
- Notifications: one absolute timer; Calendar 5 s, output 2.5 s, volume/mute 1.75 s. Coalescing retains identity; expiry continues while open and does not replay after collapse.
- Input: audited all shared slider call sites, panel pointer monitors, header swipe surface, notification background drag, hit-testing layers, and hover/collapse paths. No broad parent drag exists. Notification gestures and page swipes are confined to separate background regions.
- Calendar: selected secondary event is retained by ID across refresh; one selection; all overlapping events remain in the secondary list; Join uses the selected event URL. Fixed page layout and reminder boundary scheduling reviewed.
- Reminder: existing permission request coalescing, list refresh, parsing/manual override, save validation, native popover focus and success notification reviewed.
- Caffeine: retained model-owned 750 ms press session, movement tolerance and single-action consumption. Header ordering and panel fullscreen collection behavior reviewed.
- Lifecycle: reviewed playback poll/event/queue tasks, command revisions, audio meter start/stop serialization, device/process listeners, Calendar observer teardown and panel event-monitor removal.

## Validation

Final checks completed September 29, 2026. Focused tests only; no full hundreds-test suite was run.

| Check | Result |
| --- | --- |
| Swift package build | PASS |
| Signed macOS Debug build after final source edit | PASS |
| 30 distinct focused unit checks | PASS |
| Pointer slider and page ownership UI scenario | PASS |
| Five physical-pointer Caffeine holds in one UI scenario | PASS, 5/5 |
| Reminder focus, mock save, Escape and retention UI scenario | PASS |
| Shell hover, expansion, close and relaunch UI scenario | PASS |
| Final whitespace/error-marker check (`git diff --check`) | PASS |

Unit coverage includes seek/resume ordering and failure, stale snapshots/desktop events, previous/restart behavior, volume feedback, output changes, per-app settings/reset, navigation ownership, notification expiry/coalescing, overlapping Calendar selection, reminder boundaries/parsing/permission loading, and Caffeine press cancellation/consumption.

The pointer scenario reproduced the original ineffective seek click before the native responder fix. It then passed Home/Music seeking, Spotify/output volume clicking and dragging, and repeated explicit page selection. The shell test initially failed because it expected an obsolete 640 × 242 hosting panel; its expectation now matches the existing 740 × 322 geometry. No shell resize was introduced by that test correction.

A final native smoke check launched the signed build with Safari fullscreen, expanded the panel, opened Reminder with the title field focused, and closed it with Escape. Safari remained in fullscreen when inspected and was restored to windowed mode afterward. App-scoped captures do not conclusively prove the absence of an intervening Space transition; that acceptance check remains a manual verification item.

Build/test artifacts are under `.build/stability-audit/Logs/Test/`. The final shell run is `Test-Notchium-2026.09.29_09-30-39--0400.xcresult`. The final build and shell logs are `/tmp/notchium-audit-final-build.log` and `/tmp/notchium-audit-shell.log` (temporary).

## Remaining verification limits

- Live Spotify device/API seek and volume were not validated end to end. Command ordering and reconciliation passed scripted real-provider tests; native controls passed against mock services. The observed live iPhone target did not support Spotify volume, and the UI correctly disabled it.
- Physical trackpad dragging and actual per-app/hardware audio gain remain unverified. Automated pointer input and mixer/model tests passed.
- Reminder save was tested against an isolated mock, not by creating a real EventKit reminder.
- The final track-change release guard compiled successfully; the pointer UI scenario passed before that small guard was added.
- No additional confirmed high-severity defect remains from the reviewed paths. The items above are coverage limits, not a claim that every live environment is certified.

## Audit change inventory

Production changes are confined to `NotchiumSlider.swift`, `HomeMediaView.swift`, `MediaProgressView.swift`, `MediaViews.swift`, `MediaFeatureModel.swift`, `MediaService.swift`, `RealMediaProvider.swift`, `PlaybackReconciliation.swift`, and `AudioFeatureModel.swift`.

Fixture injection uses `AppEnvironment.swift`, `Stage11Fixtures.swift`, and `ServiceRegistry.swift`. Regression coverage changed `MediaProgressTests.swift`, `SpotifyMediaTests.swift`, `PlaybackPipelineTests.swift`, `AudioMixerTests.swift`, and `NotchiumUITests.swift`. This report is new. Existing navigation, Caffeine, Reminder, and other working-tree changes were preserved and are not attributed to this audit.
