//
//  RefreshTokenServices.swift
//  SRNetworkLayer
//
//  Created by Siamak Rostami on 7/16/24.
//

import Combine
import Foundation

// MARK: - RefreshTokenServicesProtocols

protocol RefreshTokenServicesProtocols {
    func refreshToken(token: String) -> AnyPublisher<RefreshTokenModel, NetworkError>
    func asyncRefreshToken(token: String) async throws -> RefreshTokenModel
}

// MARK: - RefreshTokenServices

class RefreshTokenServices {
    // MARK: Lifecycle

    init(client: APIClient) {
        self.client = client
    }

    // MARK: Private

    private let client: APIClient
}

// MARK: RefreshTokenServicesProtocols

extension RefreshTokenServices: RefreshTokenServicesProtocols {
    func asyncRefreshToken(token: String) async throws -> RefreshTokenModel {
        return try await client.asyncRequest(RefreshTokenRouter.refreshToken(token: token))
    }
    
    func refreshToken(token: String) -> AnyPublisher<RefreshTokenModel, NetworkError> {
        client.request(RefreshTokenRouter.refreshToken(token: token))
    }
}

// MARK: RefreshTokenServices.RefreshTokenRouter

extension RefreshTokenServices {
    enum RefreshTokenRouter: NetworkRouter {
        case refreshToken(token: String)

        // MARK: Internal

        var method: RequestMethod? {
            return .post
        }
        
        var path: String {
            return "authn/refresh-token"
        }
        
        var headers: [String: String]? {
            return HeaderHandler.shared
                .addAcceptHeaders(type: .applicationJson)
                .addContentTypeHeader(type: .applicationJson)
                .build()
        }
        
        var params: [String: Any]? {
            switch self {
            case .refreshToken(let token):
                var dict = [String: Any]()
                dict.updateValue(token, forKey: "token")
                return dict
            }
        }
    }
}
