import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AppConfigController())
    try app.register(collection: ModelsController())
    
    if Environment.get("ENABLE_SUMMARIES") == "true" {
        try app.register(collection: SummariesController())
    }
}
