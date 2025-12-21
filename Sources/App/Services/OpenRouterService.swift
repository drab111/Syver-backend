//
//  OpenRouterService.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 18/11/2025.
//

import Vapor

final class OpenRouterService {
    private let client: Client
    private let cache: Cache
    private let logger: Logger
    private let apiKey: String
    
    // cache trzyma JSON string z zakodowanymi DTO
    private let cacheKey = "openrouter:models:simple:v1"
    
    init(client: Client, cache: Cache, logger: Logger, apiKey: String) {
        self.client = client
        self.cache = cache
        self.logger = logger
        self.apiKey = apiKey
    }
    
    // MARK: - Models
    
    // Zwraca tablicę DTO (Vapor zakoduje je jako JSON automatycznie)
    func fetchModelsDTO(forceRefresh: Bool) async throws -> [ModelInfoDTO] {
        // 1) próbujemy z cache (jeśli nie wymuszono refresh)
        if !forceRefresh {
            if let cached: String = try await cache.get(cacheKey, as: String.self) {
                logger.debug("OpenRouterService: returning cached JSON")
                if let data = cached.data(using: .utf8) {
                    do {
                        let dtos = try JSONDecoder().decode([ModelInfoDTO].self, from: data)
                        return dtos
                    } catch {
                        // jeżeli cache jest uszkodzony -> fallback do pobrania fresh
                        logger.warning("OpenRouterService: failed to decode cache, refetching: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // 2) przygotowywujemy request do OpenRouter
        guard !apiKey.isEmpty else {
            logger.error("OpenRouterService: OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "OPENROUTER_KEY not configured")
        }
        let url = URI(string: "https://openrouter.ai/api/v1/models")
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        headers.add(name: .accept, value: "application/json")
        
        // 3) fetch
        let response: ClientResponse
        do {
            response = try await client.get(url, headers: headers)
        } catch {
            logger.error("OpenRouterService: network error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Network error fetching from OpenRouter")
        }
        
        // 4) obsługa 429
        if response.status == .tooManyRequests {
            if let ra = response.headers.first(name: "Retry-After") {
                logger.warning("OpenRouterService: upstream 429 Retry-After=\(ra)")
                throw Abort(.tooManyRequests, reason: "OpenRouter rate limit. Retry after \(ra)s")
            } else { throw Abort(.tooManyRequests, reason: "OpenRouter rate limit") }
        }
        
        // 5) status nie 2xx
        guard (200...299).contains(response.status.code) else {
            let txt = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
            logger.error("OpenRouterService: upstream returned \(response.status.code): \(txt.prefix(200))")
            throw Abort(.badGateway, reason: "Upstream returned \(response.status.code)")
        }
        
        // 6) oczytujemy body jako Data i parsujemy dynamicznie
        let bodyString = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
        guard let rawData = bodyString.data(using: .utf8) else {
            logger.error("OpenRouterService: empty body")
            throw Abort(.badGateway, reason: "Empty upstream response")
        }
        
        // 7) dynamiczny pars na [String:Any] i bierzemy "data" jako tablicę
        let jsonAny = try JSONSerialization.jsonObject(with: rawData)
        guard let top = jsonAny as? [String: Any], let dataArr = top["data"] as? [[String: Any]] else {
            logger.error("OpenRouterService: unexpected upstream format")
            throw Abort(.badGateway, reason: "Unexpected upstream format")
        }
        
        // 8) mapujemy każdą pozycję na ModelInfoDTO (używa init?(from:))
        var dtos: [ModelInfoDTO] = []
        for item in dataArr {
            if let dto = ModelInfoDTO(from: item) {
                dtos.append(dto)
            }
        }
        
        // 9) deduplikacja po id
        var seen = Set<String>()
        var unique: [ModelInfoDTO] = []
        unique.reserveCapacity(dtos.count) // optymalizacja pamięciowa (wiemy ile max będzie rekorów więc tyle rezerwujemy miejsca)
        
        for dto in dtos {
            if seen.insert(dto.id).inserted {
                unique.append(dto)
            } else { logger.warning("Duplicate model skipped: \(dto.id) (\(dto.name))") }
        }
        unique.sort { $0.id < $1.id }
        
        // 10) zapis do cache (prosty JSON string)
        do {
            let outData = try JSONEncoder().encode(unique)
            if let outString = String(data: outData, encoding: .utf8) {
                try await cache.set(cacheKey, to: outString)
            }
        } catch { logger.warning("OpenRouterService: could not cache DTOs: \(error.localizedDescription)") }
        
        logger.info("OpenRouterService: fetched \(unique.count) unique models")
        return unique
    }
    
    // MARK: - Summaries
    
    func postChatCompletion(client: Client, logger: Logger, apiKey: String, requestBody: OpenRouterRequestDTO) async throws -> OpenRouterResponseDTO {
        // zamieniamy request body na JSON i wysyłamy
        let url = URI(string: "https://openrouter.ai/api/v1/chat/completions")
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: .authorization, value: "Bearer \(apiKey)")
        
        let response: ClientResponse
        do {
            response = try await client.post(url, headers: headers) { outReq in
                try outReq.content.encode(requestBody)
            }
        } catch {
            logger.error("OpenRouterService.postChatCompletion: network error: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Network error contacting OpenRouter")
        }
        
        if response.status == .tooManyRequests {
            if let ra = response.headers.first(name: "Retry-After") {
                logger.warning("OpenRouterService.postChatCompletion: upstream 429 Retry-After=\(ra)")
                throw Abort(.tooManyRequests, reason: "OpenRouter rate limit. Retry after \(ra)s")
            } else { throw Abort(.tooManyRequests, reason: "OpenRouter rate limit") }
        }
        
        guard (200...299).contains(response.status.code) else {
            let txt = response.body?.getString(at: response.body!.readerIndex, length: response.body!.readableBytes) ?? ""
            logger.error("OpenRouterService.postChatCompletion: upstream returned \(response.status.code): \(txt.prefix(300))")
            throw Abort(.badGateway, reason: "OpenRouter returned \(response.status.code)")
        }
        
        // decode body into OpenRouterResponse
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
