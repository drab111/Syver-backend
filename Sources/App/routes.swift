import Fluent
import Foundation
import SwiftSoup
import Vapor

let apiKey = Environment.get("API_KEY") ?? ""

// MARK: - MODELE

struct SummarizeRequest: Content {
    let url: String
    let lang: String?
    let apiKey: String
}

struct OpenRouterRequest: Content {
    let model: String
    let messages: [OpenRouterMessage]
    let max_tokens: Int
}

struct OpenRouterMessage: Content {
    let role: String
    let content: String
}

struct OpenRouterResponse: Content {
    let id: String
    let object: String
    let created: Int
    let choices: [OpenRouterChoice]
}

struct OpenRouterChoice: Content {
    let index: Int
    let message: OpenRouterMessage
    let finish_reason: String
}

struct SummarizeFullRequest: Content {
    let url: String
    let content: String
    let lang: String
}

func routes(_ app: Application) throws {
    
    app.get("summarize") { req -> EventLoopFuture<String> in
        
        // 1. Odczytujemy URL, język oraz klucz API z query
        let summarizeReq = try req.query.decode(SummarizeRequest.self)
        let lang = summarizeReq.lang ?? "en"
        let userApiKey = summarizeReq.apiKey
        
        guard let scheme = URI(string: summarizeReq.url).scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            // Jeśli URL nie zawiera protokołu http/https to zwracamy błąd
            return req.eventLoop.makeSucceededFuture("Invalid URL. Must start with http:// or https://")
        }
        
        // 2. Pobieramy zawartość strony
        return req.client.get(URI(string: summarizeReq.url)) { clientRequest in
            clientRequest.headers.add(name: "User-Agent", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15")
        }
        
        // Parsowanie HTML (rzucamy błędy -> flatMapThrowing)
            .flatMapThrowing { htmlResponse in
                guard let buffer = htmlResponse.body else {
                    throw Abort(.badRequest, reason: "No content in HTML response")
                }
                let htmlString = buffer.getString(at: 0, length: buffer.readableBytes) ?? ""
                
                // Rzucamy błędy, bo SwiftSoup też może wyrzucić (try)
                let doc = try SwiftSoup.parse(htmlString)
                let extractedText = try doc.text()
                
                // Zwracamy sam tekst, by wykorzystać w następnym etapie łańcucha
                return extractedText
            }
        
        // 3. Wysyłamy zapytanie do OpenRouter
            .flatMap { extractedText in
                let actualText = extractedText.isEmpty ? "**[Could not fetch actual article text – try to guess the content based on the URL: '\(summarizeReq.url)' or your training data]**": extractedText
                // Budujemy request do OpenRouter
                let openRouterReq = OpenRouterRequest(
                    /* Działające AI (wystarczy podmienić)
                    
                    google/gemini-2.0-flash-exp:free
                    meta-llama/llama-3.1-8b-instruct:free
                    qwen/qwen-2.5-vl-7b-instruct:free
                    mistralai/mistral-nemo:free
                    deepseek/deepseek-chat-v3-0324:free
                     
                    */
                    model: "google/gemini-2.0-flash-exp:free",
                    messages: [
                        .init(role: "system", content: "You are a helpful AI for summarizing articles in the language requested by the user"),
                        .init(role: "user", content: "The user language code is '\(lang)'. Summarize the following article in this language in 3-5 sentences:\n\(actualText)")
                    ],
                    max_tokens: 2000
                )
                
                // Robimy POST z kluczem w nagłówku
                return req.client.post(URI(string: "https://openrouter.ai/api/v1/chat/completions")) { outReq in
                    outReq.headers.bearerAuthorization = BearerAuthorization(token: userApiKey)
                    outReq.headers.add(name: .contentType, value: "application/json")
                    try outReq.content.encode(openRouterReq)
                }
            }
        
        // 4. Dekodujemy JSON z OpenRouter (znowu flatMapThrowing bo .decode może rzucić)
            .flatMapThrowing { openRouterResponse in
                
                if let body = openRouterResponse.body,
                   let responseString = body.getString(at: 0, length: body.readableBytes) {
                    print("RAW OpenRouter response: \(responseString)")
                }
                
                let decoded = try openRouterResponse.content.decode(OpenRouterResponse.self)
                guard let choice = decoded.choices.first else {
                    throw Abort(.badRequest, reason: "No choices from model")
                }
                
                // 5. Zwracamy gotowe streszczenie
                return choice.message.content
            }
    }
    
    app.post("summarizeFull") { req -> EventLoopFuture<String> in
        // Dekodujemy dane
        let body = try req.content.decode(SummarizeFullRequest.self)
        
        _ = body.url
        let pageText = body.content
        let lang = body.lang.isEmpty ? "en" : body.lang
        
        // Budujemy prompt do openrouter
        let openRouterReq = OpenRouterRequest(
            model: "google/gemini-2.0-flash-exp:free",
            messages: [
                .init(role: "system", content: "You are a helpful AI for summarizing articles in the language requested by the user."),
                .init(role: "user", content: "The user language code is '\(lang)'. Summarize the following article in this language in 3-5 sentences:\n\(pageText)")
            ],
            max_tokens: 2000
        )
        
        // Wywołujemy openrouter.ai
        return req.client.post(URI(string: "https://openrouter.ai/api/v1/chat/completions")) { outReq in
            outReq.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
            outReq.headers.add(name: .contentType, value: "application/json")
            try outReq.content.encode(openRouterReq)
        }.flatMapThrowing { openRouterResponse in
            let decoded = try openRouterResponse.content.decode(OpenRouterResponse.self)
            guard let choice = decoded.choices.first else {
                throw Abort(.badRequest, reason: "No choices from model")
            }
            return choice.message.content
        }
    }
}
