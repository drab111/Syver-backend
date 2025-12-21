import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AppConfigController())
    try app.register(collection: ModelsController())
    try app.register(collection: SummariesController())
}
