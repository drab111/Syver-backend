//
//  AppConfigDTO.swift
//  ExtensionBackend
//
//  Created by Wiktor Drab on 21/12/2025.
//

import Vapor

// Content = Codable, pozwala Vaporowi automatycznie kodować/dekodować JSON
struct AppConfigDTO: Content {
    let minVersion: String
}
