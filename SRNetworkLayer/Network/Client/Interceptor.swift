//
//  Interceptor.swift
//  SRNetworkLayer
//
//  Created by Siamak on 7/23/24.
//

import Combine
import Foundation

// MARK: - RetryHandlerProtocol

protocol RetryHandlerProtocol {
    var numberOfRetries: Int { get }
    func shouldRetry(request: URLRequest, error: NetworkError) -> Bool
    func modifyRequestForRetry(client: APIClient, request: URLRequest, error: NetworkError) -> (URLRequest, NetworkError?)
    func shouldRetryAsync(request: URLRequest, error: NetworkError) async -> Bool
    func modifyRequestForRetryAsync(client: APIClient, request: URLRequest, error: NetworkError) async throws -> URLRequest
}

// MARK: - DefaultRetryHandler

class Interceptor: RetryHandlerProtocol {
    let numberOfRetries: Int

    init(numberOfRetries: Int) {
        self.numberOfRetries = numberOfRetries
    }

    @discardableResult
    func shouldRetry(request: URLRequest, error: NetworkError) -> Bool {
        return numberOfRetries > 0
    }

    @discardableResult
    func modifyRequestForRetry(client: APIClient, request: URLRequest, error: NetworkError) -> (URLRequest, NetworkError?) {
        return (request, error)
    }

    @discardableResult
    func shouldRetryAsync(request: URLRequest, error: NetworkError) async -> Bool {
        return numberOfRetries > 0
    }

    @discardableResult
    func modifyRequestForRetryAsync(client: APIClient, request: URLRequest, error: NetworkError) async throws -> URLRequest {
        return request
    }
}
