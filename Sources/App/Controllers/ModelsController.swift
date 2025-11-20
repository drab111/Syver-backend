//
//  ModelsController.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 18/11/2025.
//

import Vapor

// Tworzymy kontroler HTTP, który implementuje protokół RouteCollection
// RouteCollection = obiekt, który dodaje endpointy (URL-e) do aplikacji
struct ModelsController: RouteCollection {
    // Funkcja, którą Vapor wywoła, kiedy rejestrujemy kontroler w routes.swift
    // Tutaj definiujemy wszystkie endpointy HTTP, które należą do tego kontrolera
    func boot(routes: RoutesBuilder) throws {
        // Tworzymy grupę endpointów zaczynających się od /models
        // Dzięki temu zamiast pisać routes.get("models"...) możemy pisać models.get(...)
        let models = routes.grouped("models")
        
        // GET /models?refresh=true
        models.get { req async throws -> [ModelInfoDTO] in
            try await self.listHandler(req)
        }
        
        // POST /models/refresh  (admin) -> wymusza pobranie
        models.post("refresh") { req async throws -> HTTPStatus in
            try await self.refreshHandler(req)
        }
    }
    
    // GET /models?refresh=true
    func listHandler(_ req: Request) async throws -> [ModelInfoDTO] {
        // Pobieramy query param "?refresh=true" (bo jest opcjonalny - można go nie pisać)
        let force = (try? req.query.get(Bool.self, at: "refresh")) ?? false
        
        // sprawdzamy że OPENROUTER_KEY jest ustawione
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }
        
        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        do {
            // zwracamy tablicę DTO — Vapor automatycznie zakoduje JSON i ustawi Content-Type (status, headers)
            let dtos = try await service.fetchModelsDTO(forceRefresh: force)
            return dtos
        } catch let abort as AbortError { // AbortError to specjalny typ błędu w Vapor, który reprezentuje HTTP błąd
            // przekażemy aborty (429 itp.) bez zmian
            throw abort
        } catch {
            req.logger.error("ModelsController.listHandler error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Unable to fetch models right now")
        }
    }
    
    // POST /models/refresh
    func refreshHandler(_ req: Request) async throws -> HTTPStatus {
        // sprawdzamy że OPENROUTER_KEY jest ustawione
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }
        
        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        do {
            _ = try await service.fetchModelsDTO(forceRefresh: true)
            return .ok
        } catch {
            req.logger.error("Failed to refresh models: \(error.localizedDescription)")
            throw Abort(.badRequest, reason: "Refresh failed: \(error.localizedDescription)")
        }
    }
}
