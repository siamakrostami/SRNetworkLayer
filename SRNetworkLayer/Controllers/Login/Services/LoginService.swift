//
//  LoginServices.swift
//  SRNetworkLayer
//
//  Created by Siamak Rostami on 7/4/24.
//

import Combine
import Foundation

// MARK: - LoginServiceProtocols

protocol LoginServiceProtocols {
    func login(email: String, password: String) -> AnyPublisher<UserResponseModel, NetworkError>
    func asyncLogin(email: String, password: String) async throws -> UserResponseModel
}

// MARK: - LoginService

class LoginService {
    // MARK: Lifecycle

    init(client: APIClient) {
        self.client = client
    }

    // MARK: Private

    private let client: APIClient
}

// MARK: LoginServiceProtocols

extension LoginService: LoginServiceProtocols {
    func asyncLogin(email: String, password: String) async throws -> UserResponseModel {
        try await client.asyncRequest(LoginRouter.login(email: email, password: password))
    }

    func login(email: String, password: String) -> AnyPublisher<UserResponseModel, NetworkError> {
        client.request(LoginRouter.login(email: email, password: password))
    }
}

// MARK: LoginService.LoginRouter

extension LoginService {
    enum LoginRouter: NetworkRouter {
        case login(email: String, password: String)

        // MARK: Internal

        var method: RequestMethod? {
            return .post
        }

        var baseURLString: String {
            return "YOUR_BASE_URL"
        }

        var headers: [String: String]? {
            let header = HeaderHandler.shared
                .addAcceptHeaders(type: .applicationJson)
                .addContentTypeHeader(type: .applicationJson)
                .build()
            return header
        }

        var path: String {
            return "YOUR_PATH"
        }

        var params: [String: Any]? {
            var dictionary: [String: Any] = [:]
            switch self {
            case .login(let email, let password):
                dictionary.updateValue(email, forKey: "email")
                dictionary.updateValue(password, forKey: "password")
            }
            return dictionary
        }
    }
}