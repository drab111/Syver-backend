//
//  OpenRouterDTOs.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 20/11/2025.
//

import Vapor

// OpenRouter request/response DTOs
struct OpenRouterRequestDTO: Content {
    let model: String
    let messages: [OpenRouterMessageDTO]
    let max_tokens: Int?

    init(model: String, messages: [OpenRouterMessageDTO], max_tokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.max_tokens = max_tokens
    }
}

struct OpenRouterMessageDTO: Content {
    let role: String
    let content: String
}

struct OpenRouterResponseDTO: Decodable {
    let id: String?
    let object: String?
    let created: Int?
    let choices: [OpenRouterChoiceDTO]
}

struct OpenRouterChoiceDTO: Decodable {
    let index: Int?
    let message: OpenRouterResponseMessageDTO
}

struct OpenRouterResponseMessageDTO: Decodable {
    let role: String
    let content: String
}
