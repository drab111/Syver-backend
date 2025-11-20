//
//  SummariesController.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 19/11/2025.
//

import Vapor
import SwiftSoup

struct SummariesController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Grupujemy endpointy pod /summarize
        let summarize = routes.grouped("summarize")

        // GET /summarize?url=...&lang=...&apiKey=...
        summarize.get { req async throws -> SummarizeResponseDTO in
            try await self.summarizeHandler(req)
        }

        // POST /summarize/full
        summarize.post("full") { req async throws -> SummarizeResponseDTO in
            try await self.summarizeFullHandler(req)
        }
    }

    // GET /summarize
    // Example: GET /summarize?url=https://example.com/article&lang=en&apiKey=USER_KEY
    func summarizeHandler(_ req: Request) async throws -> SummarizeResponseDTO {
        // decode query
        let query = try req.query.decode(SummarizeRequestDTO.self)
        let lang = query.lang ?? "en"
        guard let userApiKey = query.apiKey, !userApiKey.isEmpty else {
            throw Abort(.badRequest, reason: "Missing apiKey query parameter")
        }
        
        // validate URL scheme
        guard let scheme = URI(string: query.url).scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw Abort(.badRequest, reason: "Invalid URL. Must start with http:// or https://")
        }
        
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }
        
        // fetch page HTML
        let htmlResponse: ClientResponse
        do {
            htmlResponse = try await req.client.get(URI(string: query.url)) { clientReq in
                clientReq.headers.add(name: "User-Agent", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15")
            }
        } catch {
            req.logger.error("SummariesController: error fetching page: \(error.localizedDescription)")
            throw Abort(.badGateway, reason: "Failed to fetch page")
        }
        
        // extract text
        let pageText: String
        if let body = htmlResponse.body, let htmlString = body.getString(at: 0, length: body.readableBytes) {
            do {
                let doc = try SwiftSoup.parse(htmlString)
                // plain text extraction
                pageText = try doc.text()
            } catch {
                req.logger.warning("SummariesController: SwiftSoup parse failed: \(error.localizedDescription)")
                pageText = ""
            }
        } else { pageText = "" }
        
        let actualText = pageText.isEmpty ? "**[Could not fetch full article text – using URL context]**" : pageText
        
        // build OpenRouter request
        let ORRequest = OpenRouterRequestDTO(
            model: "tngtech/deepseek-r1t2-chimera:free",
            messages: [
                .init(role: "system", content: "You are a helpful AI for summarizing articles in the language requested by the user."),
                .init(role: "user", content: "The user language code is '\(lang)'. Summarize the following article in this language in 3-5 sentences:\n\(actualText)")
            ], max_tokens: 2000
        )
        
        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        // send to OpenRouter using user's key
        let ORResponse = try await service.postChatCompletion(client: req.client, logger: req.logger, apiKey: userApiKey, requestBody: ORRequest)
        
        // extract content text
        guard let choice = ORResponse.choices.first else {
            throw Abort(.badGateway, reason: "No choices in OpenRouter response")
        }
        
        return SummarizeResponseDTO(summary: choice.message.content)
    }

    // POST /summarizeFull
    func summarizeFullHandler(_ req: Request) async throws -> SummarizeResponseDTO {
        // decode body
        let body = try req.content.decode(SummarizeFullRequestDTO.self)
        let lang = body.lang.isEmpty ? "en" : body.lang
        let pageText = body.content

        // use server OPENROUTER_KEY
        guard let apiKey = Environment.get("OPENROUTER_KEY"), !apiKey.isEmpty else {
            req.logger.error("OPENROUTER_KEY not configured")
            throw Abort(.internalServerError, reason: "Server misconfiguration (OPENROUTER_KEY)")
        }

        let ORRequest = OpenRouterRequestDTO(
            model: "tngtech/deepseek-r1t2-chimera:free",
            messages: [
                .init(role: "system", content: "You are a helpful AI for summarizing articles in the language requested by the user."),
                .init(role: "user", content: "The user language code is '\(lang)'. Summarize the following article in this language in 3-5 sentences:\n\(pageText)")
            ], max_tokens: 2000
        )

        let service = OpenRouterService(client: req.client, cache: req.cache, logger: req.logger, apiKey: apiKey)
        let ORResponse = try await service.postChatCompletion(client: req.client, logger: req.logger, apiKey: apiKey, requestBody: ORRequest)

        guard let choice = ORResponse.choices.first else {
            throw Abort(.badGateway, reason: "No choices in OpenRouter response")
        }

        return SummarizeResponseDTO(summary: choice.message.content)
    }
}
