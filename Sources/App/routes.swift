import Fluent
import Foundation
import SwiftSoup
import Vapor



func routes(_ app: Application) throws {
    
    
    app.get("cleanUrl") { req -> String in
        // Pobieramy URL z query string
        let originalUrl = try req.query.get(String.self, at: "url")
        
        // Usuwamy protokół `http://` lub `https://` za pomocą RegEx
        let cleanedUrl = originalUrl.replacingOccurrences(
            of: "^https?://",
            with: "",
            options: .regularExpression
        )
        
        // Zwracamy tekst
        return cleanedUrl
    }
}
