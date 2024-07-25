import Combine
import Foundation

// MARK: - NetworkInterceptor

class NetworkInterceptor: Interceptor {
    // MARK: Internal

    override func shouldRetry(request: URLRequest, error: NetworkError) -> Bool {
        if numberOfRetries > 0, case let NetworkError.responseError(statusCode, _) = error, statusCode == 403, (request.allHTTPHeaderFields?.keys.contains("Authorization")) != nil {
            return true
        } else {
            return false
        }
    }

    override func shouldRetryAsync(request: URLRequest, error: NetworkError) async -> Bool {
        if numberOfRetries > 0, case let NetworkError.responseError(statusCode, _) = error, statusCode == 403, (request.allHTTPHeaderFields?.keys.contains("Authorization")) != nil {
            return true
        } else {
            return false
        }
    }

    override func modifyRequestForRetry(client: APIClient, request: URLRequest, error: NetworkError) -> (URLRequest, NetworkError?) {
        var newRequest = request
        var returnError: NetworkError?
        if case let NetworkError.responseError(statusCode, _) = error, statusCode == 403, (request.allHTTPHeaderFields?.keys.contains("Authorization")) != nil {
            let semaphore = DispatchSemaphore(value: 0)
            syncQueue.sync {
                refreshToken(client: client)?.sink(receiveCompletion: { [weak self] completion in
                    guard let _ = self else {
                        return
                    }
                    switch completion {
                        case .finished:
                            break
                        case let .failure(failure):
                            returnError = failure
                    }
                    semaphore.signal()
                }, receiveValue: { [weak self] model in
                    // Save your token here
                    newRequest.setValue("Bearer \(model.token ?? "")", forHTTPHeaderField: "Authorization")
                    semaphore.signal()
                }).store(in: &cancellabels)
            }
            semaphore.wait()
        }
        return (newRequest, returnError)
    }

    override func modifyRequestForRetryAsync(client: APIClient, request: URLRequest, error: NetworkError) async throws -> URLRequest {
        var newRequest = request
        do {
            let newToken = try await asyncRefreshToken(client: client)
            syncQueue.sync {
                // Save your token here
            }
            newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        } catch let error as NetworkError {
            throw error
        }
        return newRequest
    }

    // MARK: Private

    private var cancellabels = Set<AnyCancellable>()
    private let syncQueue = DispatchQueue(label: "com.networkInterceptor.syncQueue")
}

extension NetworkInterceptor {
    func refreshToken(client: APIClient) -> AnyPublisher<RefreshTokenModel, NetworkError>? {
        return RefreshTokenServices(client: client).refreshToken(token: "YOUR_REFRESH_TOKEN").eraseToAnyPublisher()
    }

    @MainActor
    func asyncRefreshToken(client: APIClient) async throws -> String {
        do {
            let refresh = try await RefreshTokenServices(client: client).asyncRefreshToken(token: "YOUR_REFRESH_TOKEN")
            return refresh.token ?? ""
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}