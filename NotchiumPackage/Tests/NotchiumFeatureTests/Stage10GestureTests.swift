import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class Stage10GestureTests: XCTestCase {
    func testPartialUpwardDragReturnsAndIntentionalFlickDismisses() {
        XCTAssertFalse(NotificationDismissGesturePolicy.shouldDismiss(
            translation: .init(width: 1, height: -20), predicted: .init(width: 1, height: -22)))
        XCTAssertTrue(NotificationDismissGesturePolicy.shouldDismiss(
            translation: .init(width: 2, height: -32), predicted: .init(width: 2, height: -34)))
        XCTAssertTrue(NotificationDismissGesturePolicy.shouldDismiss(
            translation: .init(width: 1, height: -16), predicted: .init(width: 1, height: -70)))
        XCTAssertFalse(NotificationDismissGesturePolicy.shouldDismiss(
            translation: .init(width: 0, height: -4), predicted: .init(width: 0, height: -100)))
        XCTAssertFalse(NotificationDismissGesturePolicy.shouldDismiss(
            translation: .init(width: 0, height: -20), predicted: .init(width: 0, height: 10)))
    }

    func testHorizontalDownwardAndDiagonalDragsNeverDismiss() {
        for translation in [CGSize(width: 50, height: -35), .init(width: 0, height: 50),
                            .init(width: -40, height: -40)] {
            XCTAssertFalse(NotificationDismissGesturePolicy.shouldDismiss(
                translation: translation, predicted: .init(width: 0, height: -100)))
            XCTAssertEqual(NotificationDismissGesturePolicy.offset(for: translation, reduceMotion: false), 0)
        }
    }

    func testDragTravelIsRestrainedAndReduceMotionKeepsFeedbackWithoutTranslation() {
        for distance in stride(from: CGFloat(1), through: 200, by: 1) {
            let translation = CGSize(width: 0, height: -distance)
            let offset = NotificationDismissGesturePolicy.offset(for: translation, reduceMotion: false)
            XCTAssertGreaterThan(offset, -18)
            XCTAssertLessThan(offset, 0)
            XCTAssertEqual(NotificationDismissGesturePolicy.offset(for: translation, reduceMotion: true), 0)
            XCTAssertGreaterThanOrEqual(NotificationDismissGesturePolicy.opacity(for: translation), 0.88)
        }
        XCTAssertEqual(NotificationDismissGesturePolicy.offset(for: .zero, reduceMotion: false), 0)
        XCTAssertEqual(NotificationDismissGesturePolicy.opacity(for: .zero), 1)
    }

    func testOnePagePerScrollSequenceAndCancellationDropsDistance() {
        var session = PageSwipeSession()
        XCTAssertNil(session.update(x: -50, y: 0))
        session.begin()
        XCTAssertNil(session.update(x: -15, y: 1))
        XCTAssertEqual(session.update(x: -16, y: 0), true)
        XCTAssertNil(session.update(x: -100, y: 0))
        XCTAssertNil(session.update(x: 200, y: 0))
        session.cancel()
        XCTAssertNil(session.update(x: -100, y: 0))
        session.begin()
        XCTAssertEqual(session.update(x: 31, y: 0), false)
    }

    func testVerticalIntentCannotLaterTurnIntoPageNavigation() {
        var session = PageSwipeSession()
        session.begin()
        XCTAssertNil(session.update(x: 3, y: 12))
        XCTAssertNil(session.update(x: 100, y: 0))
    }

    func testNavigationStopsAtEdgesAndSkipsDisabledPages() {
        let pages = NotchPageModel()
        pages.moveSelection(forward: false)
        XCTAssertEqual(pages.selectedPage, .home)
        pages.selectedPage = .audio
        pages.moveSelection(forward: true)
        XCTAssertEqual(pages.selectedPage, .audio)
        pages.enabledPages = [.home, .calendar, .audio]
        pages.selectedPage = .home
        pages.moveSelection(forward: true)
        XCTAssertEqual(pages.selectedPage, .calendar)
    }

    func testSwipeSurfaceUsesNativeHitTestingAndCanBeDisabled() {
        let surface = NotchPageSwipeSurface.SwipeView(model: NotchPageModel())
        surface.frame = NSRect(x: 0, y: 0, width: 120, height: 40)
        XCTAssertNil(surface.hitTest(NSPoint(x: 10, y: 10)))
        surface.isEnabled = true
        XCTAssertTrue(surface.hitTest(NSPoint(x: 10, y: 10)) === surface)
        XCTAssertNil(surface.hitTest(NSPoint(x: 140, y: 10)))
        XCTAssertFalse(surface.acceptsFirstResponder)

        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        let button = NSButton(frame: NSRect(x: 120, y: 0, width: 120, height: 40))
        parent.addSubview(surface)
        parent.addSubview(button)
        XCTAssertTrue(parent.hitTest(NSPoint(x: 160, y: 10)) === button,
                      "Events on neighboring controls must never reach the swipe view")
    }

    func testMediaStaysVisibleThroughoutNotificationButMainMorphRemainsBlack() throws {
        let passive = NotchShape(width: 212, height: 38, centerX: 200,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        for phase in [NotchVisualTransition.Phase.openingBlack, .closingBlack] {
            for preservesMedia in [false, true] {
                for height: CGFloat in [38, 52, 76, 94, 126] {
                    let shape = NotchShellSurface(width: 356, height: height, centerX: 200,
                                                  bottomRadius: 34, passiveShape: passive)
                    let view = NotchSurfaceFrame(shape: shape, phase: phase, expandedHeight: 302,
                        notificationVisible: phase == .openingBlack,
                        preservesCollapsedMedia: preservesMedia) { _ in
                            Rectangle().fill(.red).frame(width: 24, height: 24)
                                .padding(.top, 7)
                                .modifier(CollapsedMediaPresentation(visible: false))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }.frame(width: 400, height: 322)
                    let renderer = ImageRenderer(content: view)
                    let image = try XCTUnwrap(renderer.cgImage)
                    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
                    let context = CGContext(data: &data, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    XCTAssertEqual(data[(18 * image.width + 200) * 4], preservesMedia ? 255 : 0)
                }
            }
        }
    }
}
