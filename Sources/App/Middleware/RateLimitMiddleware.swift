//
//  RateLimitMiddleware.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 31/12/2025.
//

import NIOConcurrencyHelpers
import Vapor

// Simple per-IP rate limiting middleware
final class RateLimitMiddleware: Middleware, @unchecked Sendable {
    // Represents a rate limit bucket for a single client (IP)
    struct Bucket {
        var count: Int // number of requests in the current window
        var resetAt: Date // when the window resets
    }
    
    private var buckets: [String: Bucket] = [:]
    private let lock = NIOLock()
    
    private let maxRequests: Int
    private let window: TimeInterval
    
    init(maxRequests: Int, window: TimeInterval) {
        self.maxRequests = maxRequests
        self.window = window
    }
    
    // Vapor middleware entry point
    // Called for every incoming request before it reaches route handlers
    func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let key = req.remoteAddress?.ipAddress ?? "unknown"
        let now = Date()
        
        // All bucket mutations and checks are performed under a lock to avoid race conditions between concurrent requests
        let isLimited: Bool = lock.withLock {
            if var bucket = buckets[key] {
                // If the time window has expired, start a new one
                if now > bucket.resetAt {
                    bucket = Bucket(count: 1, resetAt: now.addingTimeInterval(window))
                } else { bucket.count += 1 } // otherwise, increment the request counter
                
                buckets[key] = bucket
                return bucket.count > maxRequests
            } else { // first request from this IP — create a new bucket
                buckets[key] = Bucket(count: 1, resetAt: now.addingTimeInterval(window))
                return false
            }
        }
        
        // If the rate limit is exceeded, reject the request
        if isLimited {
            return req.eventLoop.makeFailedFuture(Abort(.tooManyRequests, reason: "Rate limit exceeded"))
        }
        
        // Otherwise, forward the request to the next responder
        return next.respond(to: req)
    }
}
