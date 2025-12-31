//
//  OpenRouterService.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 18/11/2025.
//

import Vapor

enum ModelsRefreshMode {
    case cacheOnly        // always return cached models if available
    case revalidate       // revalidate cache if refresh interval elapsed
    case force            // always fetch from upstream (admin-only)
}

final class OpenRouterService {
    private let client: Client
    private let cache: Cache
    private let logger: Logger
    private let apiKey: String
    
    // MARK: - Refresh policy
    
    // Minimum interval between upstream refreshes (seconds)
    private let refreshInterval: TimeInterval = 120
    
    // Cache key storing the timestamp of the last successful upstream fetch
    private let lastFetchKey = "openrouter:models:lastFetch"
    
    // Cache key storing serialized ModelInfoDTO array
    private let cacheKey = "openrouter:models:simple:v1"
    
    init(client: Client, cache: Cache, logger: Logger, apiKey: String) {
        self.client = client
        self.cache = cache
        self.logger = logger
        self.apiKey = apiKey
    }
    
    // MARK: - AI Models
    /// Fetches available models from OpenRouter.
    ///
    /// - Parameter mode:
    ///   Controls cache and refresh behavior:
    ///   - cacheOnly: always return cached data if available
    ///   - revalidate: revalidate cache only if refresh interval elapsed
    ///   - force: always fetch from upstream, bypassing cache and throttling
    
    func fetchModelsDTO(mode: ModelsRefreshMode) async throws -> [ModelInfoDTO] {
        // Cache-first strategy (always try cache first)
        if let cached: String = try await cache.get(cacheKey, as: String.self),
           let data = cached.data(using: .utf8),
           let dtos = try? JSONDecoder().decode([ModelInfoDTO].self, from: data) {
            
            switch mode {
            // Public read-only access: always serve cached data if present
            case .cacheOnly:
                return dtos
                
            // Public refresh hint: only revalidate if refresh interval elapsed
            case .revalidate:
                if !(await shouldFetchFromUpstream()) {
                    return dtos
                }
                
            // Admin-only: bypass cache and throttling, always fetch upstream
            case .force:
                break
            }
        }
        
        // Prepare upstream request
        guard !apiKey.isEmpty else {
            logger.error("OpenRouterService: OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "OPENROUTER_KEY not configured")
        }
        
        let url = URI(string: "https://openrouter.ai/api/v1/models")
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        headers.add(name: .accept, value: "application/json")
        
        // Fetch from upstream
        let response: ClientResponse
        do {
            response = try await client.get(url, headers: headers)
        } catch {
            logger.error("OpenRouterService: network error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Network error fetching from OpenRouter")
        }
        
        // Handle upstream rate limiting (429)
        if response.status == .tooManyRequests {
            if let ra = response.headers.first(name: "Retry-After") {
                logger.warning("OpenRouterService: upstream 429 Retry-After=\(ra)")
                throw Abort(.tooManyRequests, reason: "OpenRouter rate limit. Retry after \(ra)s")
            } else { throw Abort(.tooManyRequests, reason: "OpenRouter rate limit") }
        }
        
        // Validate successful response status
        guard (200...299).contains(response.status.code) else {
            let txt = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
            logger.error("OpenRouterService: upstream returned \(response.status.code): \(txt.prefix(200))")
            throw Abort(.badGateway, reason: "Upstream returned \(response.status.code)")
        }
        
        // Read response body
        let bodyString = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
        
        guard let rawData = bodyString.data(using: .utf8) else {
            logger.error("OpenRouterService: empty body")
            throw Abort(.badGateway, reason: "Empty upstream response")
        }
        
        // Parse dynamic JSON and extract `data` array
        let jsonAny = try JSONSerialization.jsonObject(with: rawData)
        guard let top = jsonAny as? [String: Any], let dataArr = top["data"] as? [[String: Any]] else {
            logger.error("OpenRouterService: unexpected upstream format")
            throw Abort(.badGateway, reason: "Unexpected upstream format")
        }
        
        // Map upstream items into DTOs
        var dtos: [ModelInfoDTO] = []
        for item in dataArr {
            if let dto = ModelInfoDTO(from: item) {
                dtos.append(dto)
            }
        }
        
        // Deduplicate by model id
        var seen = Set<String>()
        var unique: [ModelInfoDTO] = []
        unique.reserveCapacity(dtos.count) // memory optimization
        
        for dto in dtos {
            if seen.insert(dto.id).inserted {
                unique.append(dto)
            } else { logger.warning("Duplicate model skipped: \(dto.id) (\(dto.name))") }
        }
        unique.sort { $0.id < $1.id }
        
        // Cache result and update last fetch timestamp
        do {
            let outData = try JSONEncoder().encode(unique)
            if let outString = String(data: outData, encoding: .utf8) {
                try await cache.set(cacheKey, to: outString)
            }
        } catch { logger.warning("OpenRouterService: could not cache DTOs: \(error.localizedDescription)") }
        
        // Update last successful fetch timestamp
        try? await cache.set(lastFetchKey, to: Date().timeIntervalSince1970)
        
        logger.info("OpenRouterService: fetched \(unique.count) unique models")
        return unique
    }
    
    // Determines whether an upstream fetch is allowed based on the last successful fetch timestamp
    private func shouldFetchFromUpstream() async -> Bool {
        let now = Date().timeIntervalSince1970
        
        if let last: Double = try? await cache.get(lastFetchKey, as: Double.self) {
            return (now - last) >= refreshInterval
        }
        
        // No timestamp means first fetch
        return true
    }
    
    // MARK: - Summaries
    
    func postChatCompletion(client: Client, logger: Logger, apiKey: String, requestBody: OpenRouterRequestDTO) async throws -> OpenRouterResponseDTO {
        // Prepare OpenRouter Chat Completions endpoint
        let url = URI(string: "https://openrouter.ai/api/v1/chat/completions")
        
        // Configure request headers
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        
        // Send request to OpenRouter
        let response: ClientResponse
        do {
            response = try await client.post(url, headers: headers) { outReq in
                // Encode request body as JSON
                try outReq.content.encode(requestBody)
            }
        } catch {
            logger.error("OpenRouterService.postChatCompletion: network error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Network error contacting OpenRouter")
        }
        
        // Handle upstream rate limiting (429)
        if response.status == .tooManyRequests {
            if let ra = response.headers.first(name: "Retry-After") {
                logger.warning("OpenRouterService.postChatCompletion: upstream 429 Retry-After=\(ra)")
                throw Abort(.tooManyRequests, reason: "OpenRouter rate limit. Retry after \(ra)s")
            } else { throw Abort(.tooManyRequests, reason: "OpenRouter rate limit") }
        }
        
        // Validate successful response status
        guard (200...299).contains(response.status.code) else {
            let txt = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
            logger.error("OpenRouterService.postChatCompletion: upstream returned \(response.status.code): \(txt.prefix(200))")
            throw Abort(.badGateway, reason: "OpenRouter returned \(response.status.code)")
        }
        
        // Decode upstream response into OpenRouterResponseDTO
        do {
            let data = response.body?.getData(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? Data()
            let decoded = try JSONDecoder().decode(OpenRouterResponseDTO.self, from: data)
            return decoded
        } catch {
            logger.error("OpenRouterService.postChatCompletion: decode error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Invalid response from OpenRouter")
        }
    }
}
