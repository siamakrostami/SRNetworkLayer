//
//  NetworkError.swift
//  SRNetworkLayer
//
//  Created by Siamak Rostami on 6/13/24.
//

import Foundation

// MARK: - NetworkError

enum NetworkError: Error {
    case unknown
    case urlError(URLError)
    case decodingError(Error)
    case customError(ErrorResponse)
    case responseError(Int, Data)
}

// MARK: LocalizedError

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
            case .urlError(let urlError):
                return urlError.localizedDescription
            case .decodingError(let decodingError):
                return decodingError.localizedDescription
            case .customError(let errorModel):
                return errorModel.message
            case .unknown:
                return "An unknown error occurred"
            default:
                return nil
        }
    }
}
