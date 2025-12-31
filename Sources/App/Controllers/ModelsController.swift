//
//  ModelsController.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 18/11/2025.
//

import Vapor

struct ModelsController: RouteCollection { // RouteCollection = an object that registers endpoints (URLs) in the application
    // Vapor will call this function automatically at startup
    func boot(routes: RoutesBuilder) throws {
        // Group all model-related endpoints under /models
        let models = routes.grouped("models")
        
        // GET /models?refresh=true
        models.get { req async throws -> [ModelInfoDTO] in
            try await self.listHandler(req)
        }
        
        // POST /models/refresh (admin-only)
        models.post("refresh") { req async throws -> HTTPStatus in
            try await self.refreshHandler(req)
        }
    }
    
    // Returns the list of available models
    func listHandler(_ req: Request) async throws -> [ModelInfoDTO] {
        // Retrieves the optional query parameter "?refresh=true" (the client may omit it)
        let force = (try? req.query.get(Bool.self, at: "refresh")) ?? false
        let mode: ModelsRefreshMode = force ? .revalidate : .cacheOnly
        
        // Verify that the OPENROUTER_KEY environment variable is set
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }
        
        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        do {
            // Return the DTO array — Vapor will automatically encode it as JSON and set the appropriate Content-Type, status, and headers
            let dtos = try await service.fetchModelsDTO(mode: mode)
            return dtos
        } catch let abort as AbortError { // AbortError is a Vapor-specific error type representing an HTTP error
            throw abort // forward AbortErrors without modification
        } catch {
            req.logger.error("ModelsController.listHandler error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Unable to fetch models right now")
        }
    }
    
    // Forces a model refresh
    func refreshHandler(_ req: Request) async throws -> HTTPStatus {
        // Load admin key from ENV
        guard let adminKey = Environment.get("ADMIN_REFRESH_KEY"), !adminKey.isEmpty else {
            req.logger.critical("ADMIN_REFRESH_KEY not configured")
            throw Abort(.internalServerError)
        }
        
        // Read header and compare to original admin key
        guard let providedKey = req.headers.first(name: "X-Admin-Key"), providedKey == adminKey else {
            req.logger.warning("Unauthorized models refresh attempt")
            throw Abort(.unauthorized)
        }
        
        // Verify that the OPENROUTER_KEY environment variable is set
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }
        
        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        do {
            _ = try await service.fetchModelsDTO(mode: .force)
            return .ok
        } catch {
            req.logger.error("Failed to refresh models: \(error.localizedDescription)")
            throw Abort(.badRequest, reason: "Refresh failed: \(error.localizedDescription)")
        }
    }
}
