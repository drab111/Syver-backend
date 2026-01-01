//
//  RateLimitMiddlewareTests.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 01/01/2026.
//

import XCTest
import VaporTesting
@testable import App

final class RateLimitMiddlewareTests: XCTestCase {
    func testRateLimitBlocksAfterLimit() async throws {
        let app = try await Application.make(.testing)
        
        app.middleware.use(RateLimitMiddleware(maxRequests: 2, window: 60))
        app.get("ping") { _ in "ok" }
        
        try await app.test(.GET, "/ping") { response in
            XCTAssertEqual(response.status, .ok)
        }
        try await app.test(.GET, "/ping") { response in
            XCTAssertEqual(response.status, .ok)
        }
        try await app.test(.GET, "/ping") { response in
            XCTAssertEqual(response.status, .tooManyRequests)
        }
        
        try await app.asyncShutdown()
    }
}
