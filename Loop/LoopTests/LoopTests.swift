//
//  LoopTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/18/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import XCTest

@testable import Loop

class LoopTests: XCTestCase {
    func testPresentAfterDismissingPresentedViewControllerDismissesBeforePresenting() {
        let root = MockPresentationViewController()
        let presented = UIViewController()
        let destination = UIViewController()
        root.fakePresentedViewController = presented

        root.presentAfterDismissingPresentedViewController(destination)

        XCTAssertTrue(root.didDismissPresentedViewController)
        XCTAssertTrue(root.presentedDestinationViewController === destination)
    }

    func testPresentAfterDismissingPresentedViewControllerDismissesAncestorPresentationBeforePresenting() {
        let root = MockPresentationViewController()
        let navigationController = MockNavigationController(rootViewController: root)
        let presented = UIViewController()
        let destination = UIViewController()
        navigationController.fakePresentedViewController = presented

        root.presentAfterDismissingPresentedViewController(destination)

        XCTAssertTrue(navigationController.didDismissPresentedViewController)
        XCTAssertTrue(root.presentedDestinationViewController === destination)
    }
}

private final class MockPresentationViewController: UIViewController {
    var fakePresentedViewController: UIViewController?
    var didDismissPresentedViewController = false
    var presentedDestinationViewController: UIViewController?

    override var presentedViewController: UIViewController? {
        fakePresentedViewController
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        didDismissPresentedViewController = true
        fakePresentedViewController = nil
        completion?()
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedDestinationViewController = viewControllerToPresent
        completion?()
    }
}

private final class MockNavigationController: UINavigationController {
    var fakePresentedViewController: UIViewController?
    var didDismissPresentedViewController = false

    override var presentedViewController: UIViewController? {
        fakePresentedViewController
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        didDismissPresentedViewController = true
        fakePresentedViewController = nil
        completion?()
    }
}

extension XCTestCase {
    
    func waitOnMain(timeout: TimeInterval = 1.0, file: StaticString = #file, function: String = #function, line: UInt = #line) {
        let exp = expectation(description: function)
        var fulfilled = false
        DispatchQueue.main.async {
            fulfilled = true
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        XCTAssertTrue(fulfilled, "Failed to wait on main in \(function)", file: file, line: line)
    }

}
