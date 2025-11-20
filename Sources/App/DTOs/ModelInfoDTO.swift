//
//  ModelInfoDTO.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 19/11/2025.
//

import Vapor

// prosty DTO używany do zwracania klientowi
struct ModelInfoDTO: Content {
    let id: String
    let slug: String?
    let name: String
    let description: String?
    let context_length: Int?
    let pricing: [String: String]?
}

// helper init z surowego słownika (upraszcza mapping)
extension ModelInfoDTO {
    init?(from dict: [String: Any]) {
        // id wymagane
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        // slug (canonical_slug)
        if let slug = dict["canonical_slug"] as? String {
            self.slug = slug
        } else if let slug = dict["slug"] as? String {
            self.slug = slug
        } else {
            self.slug = nil
        }
        // name (fallback to id)
        if let name = dict["name"] as? String { self.name = name }
        else { self.name = id }
        // description
        self.description = dict["description"] as? String
        // context_length (Int or Number)
        if let ctx = dict["context_length"] as? Int { self.context_length = ctx }
        else if let n = dict["context_length"] as? NSNumber { self.context_length = n.intValue }
        else { self.context_length = nil }
        // pricing: normalize values to String
        if let pricing = dict["pricing"] as? [String: Any] {
            var p: [String: String] = [:]
            for (key, value) in pricing {
                if let string = value as? String { p[key] = string }
                else if let n = value as? NSNumber { p[key] = "\(n)" }
                else { p[key] = "\(value)" }
            }
            self.pricing = p
        } else { self.pricing = nil }
    }
}
