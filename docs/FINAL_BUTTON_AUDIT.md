# Notchium final independent button/control audit

Source review performed October 8, 2026. No production edits or UI automation were performed by this reviewer. All existing worktree changes were preserved. Parent reviewer owns native screenshots, keyboard traversal, VoiceOver and performance measurements.

## Scope, references and evidence boundary

Read `docs/ENGINEERING_RULES.md`, `docs/STAGE23_PRODUCT_QUALITY.md`, the design-system metrics, all production control-bearing SwiftUI views, the AppKit slider/Caffeine/menu/drag/swipe adapters, and relevant feature models. Applied `apple-design` and `emil-design-eng` from emilkowalski/skills; `break-ui` and its CATALOG from `/tmp/notchium-final-emil-skills`; Impeccable installed skill plus current upstream `audit.native.md`, `ios.md`, `optimize.md`, `polish.md` from `/tmp/notchium-final-impeccable`; and UI-UX Pro Max source skill template, UX checklist and SwiftUI dataset from `/tmp/notchium-final-ux-skill`.

Impeccable upstream provides a native iOS/Android audit, not a macOS-specific reference. Only native semantics, focus, state, resource usage and evidence requirements apply here. Its iOS 44 pt rule, Dynamic Type assumptions and navigation prescriptions are inapplicable to this finished compact macOS app. No numeric audit score is supplied without native interaction/visual evidence. Parent already ran Impeccable context; its missing PRODUCT.md is handled through the established PRODUCT_SPEC and approved no-redesign scope.

Source paths below are relative to `/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/`. Locations describe the current source at review time; later parent edits may shift lines. `native` means SwiftUI/AppKit supplies role, keyboard activation, focus and state behavior; actual native traversal/VoiceOver speech still needs the parent QA. `plain` means no explicit custom hover/press modifier in this view, not a claim that the OS supplies no feedback.

## Count and shared behavior

The final source scan after the conditional Clipboard AX-action correction found **154 production SwiftUI declaration sites**: 115 Button, 11 Toggle, 11 Picker, 6 TextField, 4 Stepper, 2 DatePicker, and 1 each Menu, ColorPicker, Slider accessibility representation, NavigationLink and SettingsLink. It excludes three protocol fallback buttons and the DEBUG-only menu action. It includes reusable wrappers and named accessibility actions; dynamic lists, options and enum-driven buttons produce multiple runtime instances. There is additionally **one native NSButton adapter**, Audio app options, and AppKit Caffeine duration menus, slider pointer input, page swipe input and Shelf drag input. This is a source-site count, not a fixed number of simultaneously visible controls. Scan includes both `Button(...)` and trailing-closure `Button { ... }` forms.

| Shared family / source | Default, hover and press | Disabled, focus and accessibility | Geometry |
| --- | --- | --- | --- |
| `NotchiumDynamicIsland/NotchSettingsButton.swift:102` `NotchUtilityButtonStyle` | 0.97 press scale + 0.8 opacity; Reduce Motion removes scale and retains opacity; label owns hover | SwiftUI Button semantics/focus; each call site supplies label/value/help; primitive Caffeine is separate | Geometry supplied by call site; does not expand hit areas |
| `NotchiumDynamicIsland/NotchSettingsButton.swift:141` `NotchUtilityLabel` | 28 pt circle, 0.06/0.14 selected fill; brighter hover/selected glyph; public system glass | Caller owns enabled/selected semantics; selected not color alone when supplied | 28×28 pt circle |
| `NotchiumDynamicIsland/NotchToolbar.swift:56,94` toolbar style/button | Distinct resting/hover/pressed fills 0.13/0.22/0.32; 0.93 press scale; reduced-motion removes scale | Disabled dimming and hover suppression; native Button focus; explicit spoken label and help | 32×32 pt, compact 26×26 pt circles; 8 pt gap |
| `NotchiumDynamicIsland/NotchToolbar.swift:108,151` search / clear | Capsule hover/focus fill; clear glyph retains visual size but now has 24 pt region, local hover and press opacity | TextField focus binding; clear is real Button with label/help; parent capsule tap focuses field | Search 32 pt high; clear 24×24 pt circle |
| `NotchiumMediaFeature/MediaViews.swift:508` Media control style | Local 0.08 hover fill, 0.97 scale / 0.78 opacity / brightness on press; short motion | Hover suppressed when disabled; Reduce Motion retains opacity/brightness; native Button semantics | Call-site dimensions |
| `NotchiumCalendarFeature/CalendarJoinButtonStyle.swift:5` Join | Opaque capsule; current diff adds hover and press fill independent of scaling | Reduce Motion now preserves press feedback; hover suppressed disabled; native Button semantics | 28 pt high + content width + 24 pt horizontal inset |
| `NotchiumShelfFeature/ShelfPageView.swift:388` secondary text style | Quiet capsule; local hover fill; press fill 0.2 | Native Button focus; no routine caller disables this family | 24 pt high + content width + 20 pt inset |
| `NotchiumDesignSystem/NotchiumSlider.swift:8` shared slider | Local hover/drag; pointer tracking sets bound value directly; track/thumbnail work isolated | Explicit keyboard arrows, custom focus outline, native Slider AX representation and adjustable action; disabled guards; contrast/transparency preferences | At least 20 pt high, full supplied width; AppKit accepts first mouse |

The `NotchiumDesignMetrics.minimumHitTarget = 44` constant is not a mandate to expand every desktop control. Stage 23 explicitly preserves 28–32 pt header/toolbar dimensions. No collapsed physical-notch height, topbar height, silhouette or coordinate system changes are recommended.

## Global header, Home and quick reminder

| Control(s) / source | Semantic role and routing | State, focus and accessibility | Actual intended target / feedback |
| --- | --- | --- | --- |
| Six enabled main section buttons, `NotchiumDynamicIsland/Pages/NotchPagesView.swift:231` | Navigation: Home, Music, Calendar, Focus Timer, Audio, Shelf; one page selection owner | Selected trait + fill/weight; native focus plus explicit 2 pt outline; increased-contrast stroke; label/help/identifier; inaccessible hidden pages disabled and AX hidden | 28×28 circles, 8 pt gaps; utility press style |
| Empty header swipe region, `.../Pages/NotchPageSwipeSurface.swift:26` | Navigation gesture alternative; precise horizontal wheel only, no momentum replay | No separate AX control; page buttons + page container adjustable action provide alternatives; disabled while auxiliary interaction | Remaining unused header space; no overlap with controls |
| Caffeine, `NotchiumDynamicIsland/NotchCaffeineButton.swift:32`; `CaffeinePressButtonStyle.swift:35` | Toggle keep-awake; native contextual durations: 15 minutes, 30 minutes, 1 hour, 2 hours; optional approval recovery | Busy disables; custom keyboard Space/Return and Down menu; explicit focus ring; AX primary and duration actions; off/awake/remaining values; pointer cancel and teardown reset | 28 pt circle; 10 pt local release hysteresis; current diff adds immediate 0.78 pressed opacity, no normal-click timer |
| Mirror, `NotchiumDynamicIsland/NotchSettingsButton.swift:41` | Toggle Mirror preview | Preview open/Off AX value, selected trait, help/label/hint/ID; preview includes permission/recovery, so it does not claim active capture; native Button focus | 28 pt circle; system glass hover, shared press feedback |
| Quick Reminder, `NotchiumQuickActionsFeature/QuickReminderButton.swift:14` | Toolbar action opens native popover | Open/closed AX value, label/help/ID; native focus; auxiliary lease; native popover Escape cancellation | 28 pt circle, selected fill while open, utility press |
| Settings, `NotchiumDynamicIsland/NotchSettingsButton.swift:64` | Toolbar action activates app and opens Settings | Label/help/ID; native focus | 28 pt circle, utility press |
| Close, same file:86 | Cancellation collapses notch | Escape default cancellation, label/help/ID | 28 pt circle; 18 pt separator from other utilities |
| Home Media connection/empty state: `NotchiumMediaFeature/HomeMediaView.swift:21`; information:45; empty background:38 | Navigation to Music; information and transport are siblings | Information AX label includes track; background click-through navigation AX hidden; other real buttons native semantics | Whole bounded Media column / information block; plain style, no explicit custom hover/press on navigation region |
| Home Previous, Play/Pause, Next: same file:73 | Playback actions | Capability/pending disabled; label/help/ID; no fake success; current diff applies same Media control style as Music page | 34×32 pt rectangles, 18 pt gaps; explicit hover/press now consistent with Media |
| Home playback position, `NotchiumMediaFeature/MediaProgressView.swift:24` | Adjustable seek, bound to session model | Native slider AX with elapsed/total speech, 5-second step; arrows; disabled cannot seek; editing lifetime commits once | Full Media column width, 20 pt high; direct pointer feedback |
| Home Calendar, `NotchiumCalendarFeature/HomeCalendarView.swift:40` | Navigation to Calendar, including permission/unavailable/empty states | Native Button, content-derived date/event label, hint and ID; event help exposes full title | Whole Calendar column; plain style, no custom press/hover |
| Home unavailable feature fallback, `NotchiumDynamicIsland/Home/HomeDashboardView.swift:81` | Navigation to affected page | Native text Button; no model duplication | Whole assigned primary region; plain |
| Customize Home empty-state SettingsLink, same file:22 | Native navigation to Settings | System focus/AX | Content-sized borderless link |
| Home shortcut tiles, `NotchiumQuickActionsFeature/HomeQuickActionsView.swift:45` | Secondary launcher actions, scroll horizontally | Busy/unavailable disabled; local focus outline; progress/error/success icons; state speech, label/help/hint; fixed stable action ID | At least 110×34 pt, 6 pt gaps + 2 pt focus inset; utility press and local hover |
| Shortcut menu: Run/Retry, Cancel Run, Edit…, Unpin from Home, Remove: same file:82–92 | Contextual and destructive removal actions; edit opens Home Settings | Native menu behavior; Run disabled busy; Remove destructive role; errors shown on tile/model | Native contextual menu; no custom hover/press needed |
| Reminder composer title: `QuickReminderButton.swift:45`; Due date:52; At Time:55; Time:61 | Text input, date/time choices and checkbox | Native controls; explicit labels; title focus on show; onSubmit Add; conditional time field | 320 pt native popover, 16 pt inset |
| Reminder Open System Settings:66; Add:79 | Permission recovery / single primary save | Add disabled `!canSaveReminder`, Return default action, owned save task prevents double submission; error copy; Escape cancellation | Native buttons; primary bordered-prominent Add |

## Media and Calendar

| Control(s) / source | Role | States and accessibility | Target / feedback |
| --- | --- | --- | --- |
| Currently Playing / Up Next, `NotchiumMediaFeature/MediaPageHeader.swift:16` | Segmented choice | Selected fill/trait; text label + IDs; native focus; queue lifecycle only while visible | 32 pt high, content width + 24 pt inset, 4 pt gap; Media feedback |
| Connect Spotify / Open Settings status recovery, `NotchiumMediaFeature/MediaViews.swift:161` | Secondary recovery opens Settings | Only appropriate experience states; initializing/authorizing visible status; native Button | Native small glass capsule |
| Shuffle, Previous Track, Play/Pause, Next Track, Repeat, same file:271 | Playback actions; Shuffle/Repeat toggles | Capability/pending disabled; spoken labels; Shuffle On/Off and Repeat Off/All tracks/One track; active dots + selected trait; no action on unavailable | 32 pt circles, 16 pt gaps; Media feedback |
| Spotify source logo, `MediaPageHeader.swift:72` | Navigation to Spotify with download fallback | Explicit Open Spotify label/help/ID | 24 pt logo + 10 pt padding = 44×44 pt rectangle; Media feedback |
| Spotify volume, `MediaViews.swift:324` | Adjustable volume | Capability disabled and precise unavailable help; 5% arrows/AX step, spoken percent; bound editing commits final | Up to 180 pt wide × 20 pt; shared slider |
| Spotify Connect device, same file:356 | Contextual device picker | Device label and ID; refresh on actual open; local presentation lease, Escape/background dismissal | 144×26 pt; truncates name; Media feedback |
| Picker background dismiss:221 | Contextual cancellation | Deliberately AX hidden; Escape provides keyboard equivalent | Whole player content; transparent plain Button |
| Spotify device options:436 | Contextual route selection | Restricted or loading disabled; visible Unavailable; active checkmark and selected trait; native Button label from device content | 34 pt row in 228 pt picker; plain; 92 pt scrolling list viewport |
| Up Next tracks, `UpNextView.swift:59` | Read-only queue, no play/reorder action | Full title/artist help and AX name; numeric duration | 44 pt row; no invented clickable affordance |
| Calendar Allow Calendar Access / Open System Settings / Try Again, `NotchiumCalendarFeature/CalendarActivityView.swift:18,23,30` | Permission/unavailable recovery | Native Button semantics; denied/restricted/unavailable remain distinct from no events | Native glass buttons in centered status view |
| Calendar main Join, same file:105 | Primary meeting action | Only when meeting URL exists; native label and ID | Content width capsule × 28 pt; Calendar Join feedback |
| Calendar upcoming disclosure, `CalendarUpcomingEventRow.swift:15` | Contextual expand/collapse | Expanded/Collapsed AX value; action hint; stable event ID | Full row, 8 pt inset; hover fill at row level, plain press |
| Calendar upcoming Join, same file:51 | Primary contextual meeting action, sibling of disclosure | Label includes event title; only expanded + meeting URL; independent ID | 28 pt capsule with 7 pt surrounding positioning inset; Join feedback |
| Calendar reminder open, `CalendarReminderView.swift:13` | Navigation to event page | Full event/label AX name | Expanding text column, content shape; plain |
| Calendar reminder Join / Join Now:30 | Primary imminent meeting action | Native Button + help/ID; imminence changes emphasis | 30 pt capsule; explicit pressed fill/opacity; opaque fallback |
| Calendar reminder dismiss:38 | Cancellation | Help + Dismiss Calendar reminder label/ID; container also named dismiss action | 28×28 pt rectangle; native plain style |

## Audio, Shelf and Clipboard

| Control(s) / source | Role | States, focus and accessibility | Target / feedback |
| --- | --- | --- | --- |
| System volume, `NotchiumAudioFeature/AudioPageView.swift:68` | Adjustable system volume | Capability disabled; spoken percentage; 5% AX/arrows; authoritative device state | Full output-row width, 20 pt; shared slider |
| System mute/unmute, same file:86 | Toggle | Omitted if cannot mute; icon/name switches; label/help | 22×22 pt native plain Button in 20 pt row |
| Output device rows:117 | Contextual route choice | Current output identified in AX name and white dot, heavier weight and fill; system state confirms route; error text | Full column × 32 pt rows; plain |
| Audio access menu:157; Request Access:158; Open Privacy & Security:159 | Contextual permission recovery | Native Menu and menu Buttons; icon-only label Audio Access + help; no input when only status unavailable | Native borderless menu; native semantics/focus |
| App mute/unmute:215 | Toggle | App-specific label/help; symbol and visible Muted text; native Button | 24×24 pt, plain |
| App volume:239 | Adjustable app volume | Per-app spoken label/percent; 5% steps; final commit on end | Remaining row width × at least 20 pt; shared slider |
| App options native button:318; Reset Volume to 100% / Pin in Mixer / Unpin from Mixer:314 | Contextual menu | NSButton native focusRing/label/toolTip; native menu delegates maintain panel lease; pinned menu title | 24×24 pt NSButton; native press tracking, no replica |
| Shelf / Clipboard title section choices, `NotchiumDynamicIsland/NotchUtilityFeatureRendering.swift:53` | Segmented navigation | Selected trait; weight/contrast; identifiers; native Button focus | Content-sized text glyph region in 32 pt toolbar; 12 pt gap; plain, no explicit minHeight |
| Shelf Add Files…, `NotchiumShelfFeature/ShelfPageView.swift:76` | Toolbar insertion | Native file chooser; label/help | 32 pt shared toolbar circle |
| Shelf AirDrop:77; Share:80 | Toolbar contextual native sharing | Disabled empty targets or sharing; targets selected entries or all when selection empty; native share anchor | 32 pt circles; toolbar feedback |
| Shelf Clear Shelf / Remove Selected:87 | Destructive removal of app-managed Shelf entries | Disabled empty Shelf; action label/help changes with selection; no original source deletion | 32 pt trash circle; toolbar feedback |
| Shelf file tiles:233 | Selection, double-click Open, drag out | Missing dim + warning, selection fill/border/trait; full filename help; AX Open guard; stable domain IDs | At least 82 pt wide × 91 pt high; utility feedback; local hover; click-transparent drag adapter |
| File menu Open / Show in Finder / Copy / Copy Path / Share… / AirDrop:187–192; Remove from Shelf:113 | Contextual actions, local removal | Native menus; unavailable file omits protected actions; sharing disables during operation | Native menus; Shelf item remains removable when missing |
| Shelf empty Add Files…:133 | Secondary insertion | Native Button label | 24 pt text capsule |
| Transfers Add to Shelf / Show in Finder:326,329,333 | Contextual file actions | Add only known completed file; reveal known active/completed URL; terminal status remains Done/Stopped/Failed | Compact 26 pt toolbar circles in 28 pt row |
| Screenshot Add All to Shelf:164 | Secondary insertion | Text Button; appears only existing captures | 24 pt text capsule |
| Screenshot tiles:170 | Double-click Open / drag; selection callback deliberately no-op | Native file menu supplies real Open/Add to Shelf; full name help/AX Open | Same FileTile target; explicit exception: primary click does not select screenshot |
| Screenshot menu Add to Shelf:173; Dismiss:176; common file actions | Contextual insertion/dismissal | Native menus; source screenshot file is preserved | Native contextual menu |
| Downloads/screenshot-folder Open Settings:366 | Permission recovery | Visible precise reason plus native Button; combined AX row needs native speech check | 24 pt text capsule in 26 pt row |
| Clipboard storage Try Again, `NotchiumClipboardFeature/ClipboardPageView.swift:22` | Recovery | Identifier; storage error; source combined container requires native QA | Native Button |
| Clipboard Search, same file:78 | Text input/filter | Accessible label Search clipboard history; submit focuses list; field binding | Up to 190×32 pt search capsule; clear button 24 pt |
| Clipboard Clear History:81 | Destructive bulk removal excluding pinned | Disabled unavailable store or no unpinned rows | 32 pt toolbar trash; shared feedback |
| Clipboard copy row:129 | Primary copy | Selected trait, pinned/copied value, kind + preview label and copy hint; actual native Button; list has arrows/Return/Space/Delete | Flexible text region in 26 pt row; parent hover/selection fill; plain |
| Clipboard Pin/Unpin:156; Delete:160; helper:235 | Contextual toggle / destructive row removal | Revealed hover OR selected, label/help; Pin disabled cap reached; custom AX Pin/Unpin and Delete on copy row; model guards availability | 20×20 pt compact circles, 9 pt gaps; local hover, plain press |
| Clipboard focused list:48–55 | Keyboard navigation surface | Explicit focusable + focusEffectDisabled; arrow selection scrolls, Return/Space copy, Delete remove | Scroll viewport; potential invisible initial focus noted below |

## Pomodoro, Mirror and system HUDs

| Control(s) / source | Role | States and accessibility | Target / feedback |
| --- | --- | --- | --- |
| Timer actions, `NotchiumFocusFeature/PomodoroControlsView.swift:42`; `PomodoroControl.swift:4` | Primary Start Focus / Start Break / Pause / Resume; secondary +5 mins / Skip / Skip Break / Take Break; destructive End Focus | Same model/state table supplies page and completion banner; only phase-valid controls exist; text labels and IDs; no simultaneous conflicting primary styling | 28 pt content-sized capsules, 8 pt gaps; utility press style |
| History, `PomodoroPageView.swift:184` | Navigation to history | Native Button, visible History text, hint and ID | Text sized with 12 pt leading inset; plain, no explicit minHeight |
| Past 30 Days / Back to timer:227 | Back navigation | Back to timer AX label/ID | Text-sized header control; plain |
| History chart day hover:287 | Read-only inspection, not a button | Every day has full date/focus/session AX description; hover tooltip supplies focus duration only | 9 pt bars + 3.5/7 pt spacing; no invented click action |
| Completion Open Focus Timer / dismiss, `PomodoroCompletionView.swift:17,30` | Navigation / cancellation | Labels/IDs; container dismiss AX action; common timer controls remain real buttons | Expanding title / 28×28 pt dismiss; plain |
| Mirror Allow Camera / Open Settings, `NotchiumCameraFeature/CameraPreviewPanel.swift:89` | Permission recovery | Native Button; explicit request owns auxiliary lease; `children: .combine` speech/action reachability must be checked natively | 24 pt text capsule inside 272×153 tile; plain |
| Camera device choices:154 | Contextual device selection | Checkmark vs circle and selected trait; native name; list scrolls if multiple devices | Flexible width × 22 pt rows; local hover fill; plain press |
| Mirrored/Natural orientation:125,154 | Toggle display orientation | Orientation AX label; Mirrored/Natural value + explanatory hint; text changes independent of color | Same 22 pt row with icon; local hover |
| Close Mirror:131 | Cancellation | Close Mirror label/ID | Content-sized 24 pt capsule; plain |
| Compact activity primary, `NotchiumDynamicIsland/NotchCompactActivityView.swift:83` | Promotes current activity | Actual Button for compact mode; AX title/value/ID; display geometry shared with hit testing | Whole compact row minus physical excluded hardware area; native plain |
| Secondary chip, `NotchSecondaryActivityChip.swift:49` | Promotes secondary activity or Music | Show <title> AX label/ID; control exists only eligible indicator | 32 pt width × collapsed visible height; circle/artwork visual 15–20 pt; native plain |
| Minor expanded system HUD, `NotchExpandedMinorActivity.swift:74` | Read-only volume/brightness/battery/status | `.allowsHitTesting(false)` intentional; no false slider/command | 292 pt wide status extension; not a button |
| Feedback banner / notification dismissal, `UnifiedNotchNotificationContent.swift:38`; `NotificationDismissModifier.swift:28` | Status + accessible dismiss / upward background drag | Named dismiss action; background drag deliberately avoids nested buttons; parent handles Escape | Existing banner geometry; no expanded HUD click targets invented |
| Shell hardware activation region, `NotchiumPanelController.swift:413` | Open/pin/unpin; outside-click collapse | Shell AX Toggle Notchium action; deliberate expanded key eligibility; notification/chip/content clicks excluded from duplicate routing | Existing physical-notch/hover frame; no topbar/collapsed-height change |

## Settings, native menus and editors

All settings below use native Form/List controls, SF Symbols, system button/toggle/picker behavior, intrinsic macOS targets and native focus/AX. No 44 pt blanket conversion or custom hover/press override is warranted. Exceptions are the custom preset swatches explicitly noted.

| Surface / source | Every control / semantic role | Enabled/loading/selected/recovery and keyboard |
| --- | --- | --- |
| Sidebar, `NotchiumFeature/NotchiumSettingsView.swift:96` | General, Home Page, Media, Audio, Calendar, Clipboard, Focus, Caffeine navigation links | Native List selection; unsupported feature categories omitted; stable category IDs; min settings window 740×520 |
| General:107 | Show menu-bar icon toggle | Explicit preference binding; immediate setting; native state |
| Home, `NotchiumQuickActionsFeature/HomeCustomizationView.swift:36,42,15` | Media/Calendar/Show shortcut row toggles; Reset Home Layout; standalone Done | Persisted model bindings; error visible; Reset retains shortcuts; Done Escape cancellation |
| Shortcuts, `QuickActionsSettings.swift:51–65,117` | Add Shortcut…, Remove, Edit…, Move up, Move down, Refresh availability, row Enabled toggle, reorder drag | Selection/boundary/refresh disables; row Enable <name> AX label; up/down help/labels; progress/error visible |
| Shortcuts context:33–38,123–127 | Run, Check Availability, Cancel Run, Edit…, Hide from Home/Show on Home, destructive Remove; AX Move up/Move down | Native menus/actions, canRun guard; reorder button alternative to drag; stable action ID |
| Shortcut editor, `QuickActionEditor.swift:23–42` | Action picker, Name field, Icon picker, Enabled/Show on Home toggles, Cancel, Add/Save | Kind locked existing/choosing/saving; save disabled invalid/choosing/saving; Return save, Escape cancel; visible errors |
| Editor target:57–95 | Shortcut picker, Refresh Shortcuts, URL field, Choose… app/file/folder, System Action picker | Refresh disabled busy; URL inline validation; native chooser sets name focus; save guard; target file name middle truncation |
| Reminder settings, `QuickActionsSettings.swift:75,83,85` | Default Reminder List picker, Enable Quick Reminder…, Open Reminders Privacy Settings | Lists conditional granted; denied/restricted recovery; explicit error |
| Media, `NotchiumMediaFeature/MediaConnectionView.swift:15,24,57` | Spotify client ID field, Connect Spotify/Cancel, Disconnect | Field disabled in attempt; initial restoration disables Connect; Cancel task owned until cleanup; connection/status visible |
| Waveform, `WaveformAppearanceSettings.swift:15,25,45,50,54` | Colour mode picker; White/Blue/Green/Black preset choices; Custom colour ColorPicker; Hex code field; Apply | Static controls conditional mode; preset checkmark + selected trait/name/help; invalid hex copy; Return apply. Swatches custom plain 28×28 pt including padding, no custom hover/press |
| Audio, `AudioMeterPermissionView.swift:11,12` | Enable system audio waveform; Open Recording Settings | Offered idle/permissionRequired/unavailable; visible status; native actions |
| Calendar, `NotchiumCalendarFeature/CalendarSettingsSection.swift:14,18,21,26,33` | Allow Calendar Access; Open System Settings; Check Again; Try Again; per-calendar selection toggles | Permission branches explicit; calendar toggles only usable; name-derived label + color dot; native selected toggle state |
| Clipboard, `NotchiumFeature/UtilitySettingsSections.swift:11–26` | Capture clipboard history toggle; History size picker (25/50/100); Keep items for picker; Clear History; destructive Clear All, Including Pinned; Try Again | Clear buttons disabled storage unavailable; capture off retains history; retention and pin policy disclosed |
| Focus, same file:45–48,102 | Reduce interruptions toggle; Turn on Focus during timer toggle; Turn on with / Turn off with shortcut pickers | Unsupported capability explained; selectors only relevant enabled; None and persisted missing choice retained; errors visible |
| Focus Timer, same file:64–86 | Timer/Music collapsed display segmented picker; Focus, Short break, Long break, cycle-count steppers; Completion sound picker; Preview; Restore Timer Defaults | Supported model ranges; tabular/pluralized labels; Preview disabled no sound; restore disabled standard; native focus/state |
| Caffeine, `NotchiumCaffeineFeature/LidAwakeSettingsSection.swift:11,19,21` | Closed-lid keep-awake toggle; Open Login Items & Extensions; Remove Closed-Lid Helper | Explicit admin/thermal/battery behavior copy; visible controller message; approval recovery conditional; async removal |
| Menu bar, `NotchiumFeature/NotchiumMenuView.swift:18,20,37` | Open Notchium, Settings…, Quit Notchium | Open deliberately grants keyboard focus; Settings activates app; Cmd-Q quit; native menu tracking |
| System-owned Share/AirDrop/file panels, `NotchiumShelfFeature/NativeFileSharing.swift`, `FileActions.swift` | Native service/action chooser, selection, Cancel, confirmation as supplied by OS | Intentionally system controls; inspect native routes in parent QA, preserve lease/cancellation ownership |

DEBUG-only controls in DeveloperPanelView / NotchShellDeveloperControls / MediaDeveloperControls / NotchActivityDeveloperControls and the DEBUG menu item are outside the production button count, and were not restyled. Their source sites were excluded from the production count.

## Current diff review: resolved defects

Emil-required review format:

| Before | After in parent diff | Why / verdict |
| --- | --- | --- |
| Normal Caffeine press changes no observed presentation state until action release | `CaffeinePressInteraction.isPressed` changes on begin and resets on cancel; primitive label dims immediately | Source confirms immediate local feedback; cancellation/disabled teardown retained; no task added to normal click |
| Calendar Join only scales; Reduce Motion removes every pressed cue | Fill changes on hover/down independently of scale | Same layout, role and meeting routing; reduced-motion remains responsive |
| Home transport used plain style, unlike the same controls in Media | `MediaControlButtonStyle` reused | Same targets/capability guards; local hover/press consistency with no new model or timer |
| Search clear target was only an 11 pt glyph | 24×24 pt circle + local hover/down + help | Target now centered around unchanged glyph; stays inside 32 pt field and separate from TextField |
| Clipboard row read only native motion environment while shell preview overrides use design-system preference | `@NotchReducedMotion` | Source now honors both actual system value and inherited native presentation override |

No reachable new role, action routing, model truth, physical-notch geometry or native keyboard regression was found in those edits. Conditional Clipboard Pin/Unpin/Delete accessibility actions were also re-reviewed after the parent correction: no phantom Pin action remains at the cap, and allowed actions retain native semantics. Native press appearance and focus should be checked by parent, not inferred solely from source.

## Remaining source findings and bounded native checks

| Severity / evidence | Location | Before | Minimal correction or verification |
| --- | --- | --- | --- |
| Resolved after independent finding; source re-reviewed | `NotchiumClipboardFeature/ClipboardPageView.swift:153`; `ClipboardModel.swift:202` | Pin was always published as a named AX action when the cap disabled the visual button | Parent now uses conditional accessibilityActions: Pin appears only when canPin, Unpin remains for pinned items and Delete always remains. Model policy unchanged. |
| Native verification needed, source shows absent fallback | `ClipboardPageView.swift:48–50` | ScrollView becomes focusable and disables focus effect; no row is selected until Arrow, so initial focus may be invisible | Verify native Tab/search-submit; if container is an actual stop, add narrow focus indication or establish selection on focus. Do not redesign rows. |
| Resolved after independent finding | `NotchiumDynamicIsland/NotchCaffeineButton.swift` | Indefinite active Caffeine used only foreground color; timed state also had a progress ring; AX spoke active state | Active Caffeine now adds a small checkmark when Differentiate Without Color is enabled. Normal-mode appearance and the approved absence of an indefinite timer border are preserved. |
| Native verification needed | Plain-control families: Calendar disclosure/reminder dismiss, Audio mute/output, Clipboard row/icons, Mirror choices/close, Pomodoro History/back, Shelf section title, Spotify device options, waveform presets | Most have hover or selected cues, but no explicit pressed modifier; some have no local hover | Inspect actual native OS Button feedback. Only reuse an existing local style if verified unresponsive; do not assume plain style is broken. |
| Native verification needed | Clipboard bulk clear + Settings clear all; mirror message and storage recovery combined groups | Destructive bulk actions currently immediate; combined AX groups contain buttons | Verify existing approved deletion contract/irreversibility and native VoiceOver action reachability. Do not add blanket confirmations or classify unsupported source inference as a defect. |

## Hostile-content review

This is a source mapping, not a claim of completed rendered hostile-fixture tests. Parent owns the rendered fixture matrix. User's no-feature/no-redesign scope overrides the generic break-ui instruction to install a new production Demo/Worst-case toggle.

| Rendered field / source | Type/limit | Hostile case and what source already protects | Remaining rendered check |
| --- | --- | --- | --- |
| Track title/artist, MediaState; Home/Media/queue | Strings, unbounded provider metadata | Long CJK/emoji/mixed scripts; Home title 2 lines, player/queue one line; queue full help/AX; fixed artwork slots with fallback | Check Home title/controls at compact geometry; Home artist has no help but AX button title identifies track |
| Spotify device/output/camera/app names, provider models | Unbounded strings; lists dynamic | Long compound names; single-line truncation; fixed control heights; camera choices scroll | Full name discoverability in Spotify button vs picker; audio route/action remains reachable |
| Calendar title/name/detail/time, CalendarEventSummary | Strings unbounded; next/upcoming provider bounded window | Two-line titles, compact time, separate Join reservation; Home event full help | Long translated time/location and CJK; main event title/meeting action fit vertical region |
| QuickAction.displayName / target, user-owned local store | Name unbounded; URL validation constrains scheme/shape | Long names ellipsize in 110 pt minimum tiles, full name help/AX; horizontal scroll preserves every tile; no icon shrink | 0/1/many tiles, same names, long Unicode; unavailable busy contexts stay reachable |
| Shelf filename, displayName/provider URL | Filename bounded by filesystem, display name otherwise unbounded | Middle truncation preserves extension, 2 fixed lines, tooltip full name; missing file warning/action guard | Many selected count, long names; Show/Share/Add controls stay visible |
| Transfers name/status/count | Unbounded name and failure message; finite fraction/time guard | Middle ellipsis; bounded displayed rows; Done/Stopped/Failed preserved, numeric progress | Long failure detail may compress name/actions; +large-count aligns and remains understandable |
| Clipboard preview, ClipboardItem | Content-derived string; row single-line | Text/URL/file/image types; unpinned bounded 25/50/100, max 10 pinned; ellipsis + full AX label; icon fallbacks | Long Unicode/newline literal, row actions at narrow width, cap-exhausted Pin action semantics |
| Reminder title / list names | User strings unbounded | Native field horizontal scroll; native lists; single owned save | Denied/restricted/no writable lists, long error, Return/Escape and focus restoration |
| Timer titles/durations/counts | Enum titles; validated configuration ranges; history30 days | Content-sized capsule labels; one primary, stable 8 pt gaps; numeric digits monospaced; pluralization handled | Paused three-control row; end/take-break vs centered resume collision with translated strings |

Read-only queue rows, charts, waveform, preview, battery values and minor HUDs are intentionally not buttons. Missing output volume/mute controls are omitted with precise capability text. Standard Settings toggles/pickers/steppers retain native state feedback. No new animation system, button shape system, global hover state, repetitive hover tasks, hidden-page control exposure or blanket target-size normalization is recommended.

## Validation handoff

Fresh source scan and scoped git diff review completed; no tests/builds or native accessibility speech claimed by this reviewer. Parent should use the same executable/configuration for before/after QA and confirm Tab/Shift-Tab, Space/Return, Escape, native menu tracking, VoiceOver values/actions, Increase Contrast, Reduce Motion, Differentiate Without Color and hostile fixtures. Preserve approved shell dimensions, display handling, timed Caffeine policy and native system dialogs. The source-confirmed pin-action availability and non-color Caffeine cue issues are resolved. Initial Clipboard focus and plain Button feedback require native evidence. Native execution and its limitations are recorded in FINAL_OPTIMIZATION_PASS.md.
