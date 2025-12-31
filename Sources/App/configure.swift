import Vapor

public func configure(_ app: Application) async throws {
    app.caches.use(.memory) // in-memory cache (ok for dev & small production)
    
    if let portString = Environment.get("PORT"), let port = Int(portString) {
        app.http.server.configuration.port = port
    }
    
    // Apply a simple global rate limit to protect public endpoints
    app.middleware.use(RateLimitMiddleware(maxRequests: 60, window: 60))
    
    // Register routes
    try routes(app)
}
