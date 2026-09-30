# Stages 14–15 — Files, Transfers, Shelf, AirDrop, Screenshots

## macOS capability findings (verified)

| Need | Supported mechanism used | Limits |
| --- | --- | --- |
| Finder / download / AirDrop progress | `Progress.addSubscriber(forFileURL:)` on a folder. Other processes publish `NSProgress` for files inside it (Finder copies, Safari/Chrome downloads, AirDrop receives). Verified cross-process: main-thread callbacks, live `fractionCompleted`, finish/cancel on unpublish. File URL and operation kind come through `userInfo` (the typed accessors can be empty on a fresh proxy). | Only folders we subscribe to (Downloads). No public API for arbitrary Finder operations elsewhere. Unpublish carries no error, so an unfinished end is shown as "Stopped", never as failed or done. No size polling, no fake percent: indeterminate stays indeterminate. |
| AirDrop | `NSSharingService(named: .sendViaAirDrop)`, which presents Apple's own AirDrop UI | No public API to pick a recipient or send directly. `canPerform` false shows "AirDrop is unavailable". |
| Share | SwiftUI `ShareLink` (Apple's native share menu) | — |
| Screenshots | `NSMetadataQuery` for `kMDItemIsScreenCapture == 1` created after launch, in the user's home scope | No Screen Recording permission, independent of save location. Clipboard-only captures have no file and are not observable. The file (and so the activity) arrives when macOS finishes writing it, after its floating thumbnail. |
| Thumbnails | `QLThumbnailGenerator` (downsampled, off-main), `NSCache` with a limit of 48 | Never a full-resolution decode. |
| Shelf persistence | Bookmarks (security-scoped when sandboxed), re-resolved on restore | Missing, unresolvable, or older-than-7-days items are dropped. At most 24 items. Only the reference and the date added are stored. |

## Flow

```
NSProgress / Spotlight / drops → FileTransferService / ScreenshotService / ShelfService
  → TransferActivityModel / ScreenshotActivityModel / ShelfModel (feature truth)
  → typed NotchNotification (persistent "transfer", transient "screenshot"/"shelf.added")
  → ActivityCoordinator (priority, lifetime, primary/secondary) → compact / chip / Shelf page
```

- **Active transfer:** a persistent *baseline* notification. It outranks Music, and every transient interrupts it. While anything runs there is one identity: primary transfer + "+N". When the last transfer ends, the same identity morphs into Done / Failed / Stopped for a short hold, then expires.
- **Screenshot:** transient, high priority. Rapid captures update one activity (latest thumbnail, "3 Screenshots") without replaying the entry animation.
- **Secondary chip:** pairs baselines only. Music beside a transfer shows an artwork chip; promoting Music shows a live progress-ring chip for the transfer. No chip ever appears beside Calendar or system transients.
- **Drop:** the panel controller detects a file drag from the drag pasteboard's change count (only while a button is held) and, near the notch, shows a drop affordance with the feedback-banner geometry. Files are referenced, never copied. Leaving the zone retracts the affordance; nothing expands.
- **Navigation:** clicking a transfer or screenshot opens the Shelf page (explicit). Background events never change the page.
