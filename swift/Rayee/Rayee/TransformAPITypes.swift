//
//  TransformAPITypes.swift
//  Rayee
//
//  Codable types for the text transformation API endpoints.
//  Used by PythonBridge to communicate with the Python server.
//

import Foundation

// MARK: - Transform Response Types

/// Response from /transform endpoint
struct TransformAPIResponse: Codable {
    let originalText: String
    let transformedText: String
    let transformationType: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case originalText = "original_text"
        case transformedText = "transformed_text"
        case transformationType = "transformation_type"
        case status
    }
}

/// Response from /transform/status endpoint
struct TransformStatusAPIResponse: Codable {
    let modelLoaded: Bool
    let modelDownloaded: Bool
    let modelDownloading: Bool
    let availableTypes: [String]
    let downloadError: String?

    enum CodingKeys: String, CodingKey {
        case modelLoaded = "model_loaded"
        case modelDownloaded = "model_downloaded"
        case modelDownloading = "model_downloading"
        case availableTypes = "available_types"
        case downloadError = "download_error"
    }
}

/// Response from /transform/download and /transform/download_status
struct TransformDownloadAPIResponse: Codable {
    let status: String
    let error: String?
}

// MARK: - Transform Request Types

/// Request body for /transform endpoint
struct TransformRequestBody: Codable {
    let text: String
    let transformationType: String

    enum CodingKeys: String, CodingKey {
        case text
        case transformationType = "transformation_type"
    }
}
