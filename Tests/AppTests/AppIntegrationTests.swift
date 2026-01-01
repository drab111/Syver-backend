//
//  AppIntegrationTests.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 07/03/2025.
//

import XCTest
import VaporTesting
@testable import App

final class AppIntegrationTests: XCTestCase {
    // MARK: - Setup
    
    func withApp(_ body: (Application) async throws -> Void) async throws {
        // Spin up the application in testing mode
        let app = try await Application.make(.testing)
        try await configure(app)
        
        // Execute the test logic against the running app
        try await body(app)
        
        // Cleanly shut down the app
        try await app.asyncShutdown()
    }
    
    // MARK: - Tests
    
    func testMinIOSVersionEndpointReturnsConfiguredValue() async throws {
        // Set environment variable used by the config endpoint
        setenv("IOS_MIN_VERSION", "2.5", 1)
        defer { unsetenv("IOS_MIN_VERSION") }
        
        // Execute the test logic against the running app
        try await withApp { app in
            try await app.test(.GET, "/config/ios-min-version") { response in
                XCTAssertEqual(response.status, .ok)
                
                let config = try response.content.decode(AppConfigDTO.self)
                XCTAssertEqual(config.minVersion, "2.5")
            }
        }
    }
    
    func testMinIOSVersionEndpointReturnsDefaultValueWhenNotConfigured() async throws {
        // Ensure the environment variable is not set
        unsetenv("IOS_MIN_VERSION")
        
        // Execute the test logic against the running app
        try await withApp { app in
            try await app.test(.GET, "/config/ios-min-version") { response in
                XCTAssertEqual(response.status, .ok)
                
                let config = try response.content.decode(AppConfigDTO.self)
                XCTAssertEqual(config.minVersion, "1.0")
            }
        }
    }
    
    func testModelsEndpointFailsWhenApiKeyIsMissing() async throws {
        unsetenv("OPENROUTER_KEY")
        
        try await withApp { app in
            try await app.test(.GET, "/models") { response in
                XCTAssertEqual(response.status, .internalServerError)
            }
        }
    }
    
    func testModelsRefreshRequiresAdminKey() async throws {
        setenv("OPENROUTER_KEY", "dummy", 1)
        setenv("ADMIN_REFRESH_KEY", "secret", 1)
        defer {
            unsetenv("OPENROUTER_KEY")
            unsetenv("ADMIN_REFRESH_KEY")
        }
        
        try await withApp { app in
            try await app.test(.POST, "/models/refresh") { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
        }
    }
    
    func testModelsRefreshRejectsInvalidAdminKey() async throws {
        setenv("OPENROUTER_KEY", "dummy", 1)
        setenv("ADMIN_REFRESH_KEY", "secret", 1)
        defer {
            unsetenv("OPENROUTER_KEY")
            unsetenv("ADMIN_REFRESH_KEY")
        }
        
        try await withApp { app in
            var headers = HTTPHeaders()
            headers.add(name: "X-Admin-Key", value: "wrong")
            
            try await app.test(.POST, "/models/refresh", headers: headers) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
        }
    }
}
