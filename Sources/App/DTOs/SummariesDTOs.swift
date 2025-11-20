//
//  SummariesDTOs.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 20/11/2025.
//

import Vapor

// GET /summarize
struct SummarizeRequestDTO: Content {
    let url: String
    let lang: String?
    let apiKey: String?   // user's key
}

// POST /summarizeFull
struct SummarizeFullRequestDTO: Content {
    let url: String?      // optional, may be used for context
    let content: String   // full article text
    let lang: String
}

// response we return to client
struct SummarizeResponseDTO: Content {
    let summary: String
}
