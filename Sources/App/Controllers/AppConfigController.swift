//
//  AppConfigController.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 21/12/2025.
//

import Vapor

struct AppConfigController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Grupujemy endpointy pod /config
        let config = routes.grouped("config")
        
        // GET /config/ios-min-version
        config.get("ios-min-version") { req async throws -> AppConfigDTO in
            try await self.minVersionHandler(req)
        }
    }
    
    // GET /config/ios-min-version
    func minVersionHandler(_ req: Request) async throws -> AppConfigDTO {
        let minVersion = Environment.get("IOS_MIN_VERSION") ?? "1.0"
        req.logger.info("Serving min version: \(minVersion)")
        
        return AppConfigDTO(minVersion: minVersion)
    }
}
