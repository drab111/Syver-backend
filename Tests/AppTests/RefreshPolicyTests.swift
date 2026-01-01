//
//  RefreshPolicyTests.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 01/01/2026.
//

import XCTest
import VaporTesting
@testable import App

final class RefreshPolicyTests: XCTestCase {
    func testFetchAllowedWhenNoPreviousTimestamp() {
        let policy = RefreshPolicy(refreshInterval: 60)
        XCTAssertTrue(policy.shouldFetch(now: 100, lastFetch: nil))
    }
    
    func testFetchBlockedWithinInterval() {
        let policy = RefreshPolicy(refreshInterval: 60)
        XCTAssertFalse(policy.shouldFetch(now: 130, lastFetch: 100))
    }
    
    func testFetchAllowedAfterInterval() {
        let policy = RefreshPolicy(refreshInterval: 60)
        XCTAssertTrue(policy.shouldFetch(now: 161, lastFetch: 100))
    }
}
