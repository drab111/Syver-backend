//
//  RefreshPolicy.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 01/01/2026.
//

import Foundation

struct RefreshPolicy {
    let refreshInterval: TimeInterval // minimum interval between upstream refreshes (seconds)
    
    // Determines whether an upstream fetch is allowed based on the last successful fetch timestamp
    func shouldFetch(now: TimeInterval, lastFetch: TimeInterval?) -> Bool {
        guard let lastFetch else { return true } // no timestamp means first fetch
        return (now - lastFetch) >= refreshInterval
    }
}
