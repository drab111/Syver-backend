import Vapor

func routes(_ app: Application) throws {
    // rejestrujemy ModelsController
    try app.register(collection: ModelsController())
    try app.register(collection: SummariesController())
}
