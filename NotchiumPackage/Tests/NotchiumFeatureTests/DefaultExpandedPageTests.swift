import Combine
import Foundation
import XCTest
import NotchiumCore
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature

@MainActor final class DefaultExpandedPageTests: XCTestCase {
    func testPlaybackAndCachedPausedTrackChooseFreshDefault() {
        let model = presentation()
        let media = MediaSessionController(provider: MockMediaProvider(), coordinator: model.activityCoordinator,
                                           localDeviceNames: ["this mac"])
        defer { media.stop(); model.reset() }
        for playing in [false, true, false] {
            // Playing on this Mac (the local Spotify Connect device); remote playback opens Home.
            media.receive(.init(connectionState: .authenticated, playbackState: playing ? .playing : .paused,
                                title: "Track", trackID: "track", activeDeviceID: "mac",
                                activeDeviceName: "This Mac", activeDeviceType: "Computer", source: .spotify))
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, playing ? .music : .home)
            model.present(.collapsed, animated: false) // Complete collapse before a fresh expansion.
        }
        media.receive(.init(connectionState: .authenticated, source: .spotify))
        XCTAssertTrue(media.isShowingCachedTrack)
        XCTAssertNotNil(model.activityCoordinator.persistentActivity)
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
    }

    func testMusicAlertWinsUntilDismissedWithoutPlayback() {
        for kind in [NotchActivityKind.media, .notification] {
            let model = presentation()
            let alert = activity(kind, destination: .music)
            model.activityCoordinator.present(alert)
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, .music)
            model.activityCoordinator.dismiss(id: alert.id)
            XCTAssertEqual(model.pageModel.selectedPage, .music, "Ending an alert must not navigate an open surface")
            model.present(.collapsed, animated: false) // Complete collapse before a fresh expansion.
            model.setExpanded(true)
            XCTAssertEqual(model.pageModel.selectedPage, .home)
            model.reset()
        }
    }

    func testCalendarAndAudioDoNotBecomeFreshDefaultsOrHidePlayingMusic() {
        for kind in [NotchActivityKind.calendar, .audioDevice] {
            for playing in [false, true] {
                let model = presentation()
                model.pageModel.selectedPage = kind == .calendar ? .calendar : .audio
                model.activityCoordinator.present(.init(id: UUID(), kind: .media, title: "Track", subtitle: nil,
                    lifetime: .persistent, duration: nil, payload: .mediaPlayback(isPlaying: playing)))
                model.activityCoordinator.present(activity(kind))
                XCTAssertEqual(model.activityCoordinator.activeTransient?.kind, kind)
                model.setExpanded(true)
                XCTAssertEqual(model.pageModel.selectedPage, playing ? .music : .home)
                model.reset()
            }
        }
    }

    func testAllManualPagesRemainSelectedThroughoutOpenActivityChanges() {
        for state in [NotchStableState.hovered, .expanded] {
            for page in NotchPage.allCases {
                let model = presentation()
                model.setExpanded(true, target: state)
                model.pageModel.selectedPage = page
                var selections: [NotchPage] = []
                let observation = model.pageModel.$selectedPage.dropFirst().sink { selections.append($0) }
                let alert = activity(.notification, destination: .music)
                model.activityCoordinator.present(alert)
                model.activityCoordinator.dismiss(id: alert.id)
                model.activityCoordinator.present(activity(.calendar))
                model.setExpanded(true) // Pinning an already-hovered surface is not a fresh expansion.
                XCTAssertEqual(model.pageModel.selectedPage, page)
                XCTAssertTrue(selections.isEmpty, "Activity changes must not cause page flicker")
                observation.cancel()
                model.present(.collapsed, animated: false) // Complete collapse before a fresh expansion.
                model.setExpanded(true)
                XCTAssertEqual(model.pageModel.selectedPage, .home)
                model.reset()
            }
        }
    }

    func testQueuedMusicAlertDoesNotOverrideHomeUntilItBecomesActive() {
        let model = presentation()
        let calendar = activity(.calendar)
        model.activityCoordinator.present(calendar)
        let music = activity(.media, destination: .music)
        model.activityCoordinator.present(music)
        XCTAssertEqual(model.activityCoordinator.queueCount, 1)
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        model.present(.collapsed, animated: false) // Complete collapse before a fresh expansion.
        model.activityCoordinator.dismiss(id: calendar.id)
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .music)
        model.reset()
    }

    private func presentation() -> DynamicIslandPresentationModel {
        DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
    }
    private func activity(_ kind: NotchActivityKind, destination: NotchActivityDestination? = nil) -> NotchActivity {
        .init(id: UUID(), kind: kind, title: "Fixture", subtitle: nil,
              lifetime: .transient, destination: destination, duration: .seconds(10))
    }
}
