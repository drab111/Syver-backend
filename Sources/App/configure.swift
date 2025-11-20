import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.caches.use(.memory) // in-memory cache (ok for dev & small production)
    
    if let portString = Environment.get("PORT"), let port = Int(portString) {
        app.http.server.configuration.port = port
    }
    
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .DELETE, .OPTIONS, .PUT, .PATCH],
        allowedHeaders: [.xRequestedWith, .origin, .contentType, .accept]
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors)
    
    // register routes
    try routes(app)
}
