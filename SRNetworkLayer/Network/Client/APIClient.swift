

import Combine
import Foundation
import UIKit

// MARK: - APIClientRequestProtocol

protocol APIClientRequestProtocol {
    func request<T: Codable>(_ endpoint: NetworkRouter) -> AnyPublisher<T, NetworkError>
}

// MARK: - APIClientAsyncAwaitRequestProtocol

protocol APIClientAsyncAwaitRequestProtocol {
    func asyncRequest<T: Codable>(_ endpoint: NetworkRouter) async throws -> T
}

// MARK: - APIClientUploadRequestProtocol

protocol APIClientUploadRequestProtocol {
    func uploadRequest<T: Codable>(_ endpoint: NetworkRouter, withName: String, file: Data?, progressCompletion: @escaping (Double) -> Void) -> AnyPublisher<T, NetworkError>
}

// MARK: - APIClientAsyncAwaitUploadRequestProtocol

protocol APIClientAsyncAwaitUploadRequestProtocol {
    func asyncUploadRequest<T: Codable>(_ endpoint: NetworkRouter, withName: String, file: Data?, progressCompletion: @escaping (Double) -> Void) async throws -> T
}

// MARK: - APIClient

class APIClient {
    private let apiQueue = DispatchQueue(label: "com.apiQueue", qos: .background)
    private var retryHandler: Interceptor = .init(numberOfRetries: 0)
    private var requestsToRetry: [URLRequest] = []
}

// MARK: - APIClient+Interceptor

extension APIClient {
    @discardableResult
    func set(interceptor: Interceptor) -> Self {
        apiQueue.sync(flags: .barrier) {
            retryHandler = interceptor
        }
        return self
    }
}

// MARK: APIClientRequestProtocol

extension APIClient: APIClientRequestProtocol {
    // MARK: - Combine Network Request

    func request<T: Codable>(_ endpoint: NetworkRouter) -> AnyPublisher<T, NetworkError> {
        guard let urlRequest = try? endpoint.asURLRequest() else {
            return Fail(error: NetworkError.unknown).eraseToAnyPublisher()
        }

        return makeRequest(urlRequest: urlRequest, retryCount: 3)
    }

    private func makeRequest<T: Codable>(urlRequest: URLRequest, retryCount: Int) -> AnyPublisher<T, NetworkError> {
        URLSessionLogger.shared.logRequest(urlRequest)

        let session = configuredSession()

        return session.dataTaskPublisher(for: urlRequest)
            .subscribe(on: apiQueue)
            .tryMap { [weak self] output in
                URLSessionLogger.shared.logResponse(output.response, data: output.data, error: nil)
                guard let httpResponse = output.response as? HTTPURLResponse else {
                    throw NetworkError.unknown
                }
                if 200 ..< 300 ~= httpResponse.statusCode {
                    return output.data
                } else {
                    guard let error = self?.mapErrorResponse(output.data, statusCode: httpResponse.statusCode) else {
                        throw NetworkError.unknown
                    }
                    URLSessionLogger.shared.logResponse(output.response, data: output.data, error: error)
                    throw error
                }
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { [weak self] error -> NetworkError in
                URLSessionLogger.shared.logResponse(nil, data: nil, error: error)
                return self?.mapErrorToNetworkError(error) ?? .unknown
            }
            .catch { [weak self] error -> AnyPublisher<T, NetworkError> in
                guard let self else {
                    return Fail(error: NetworkError.unknown).eraseToAnyPublisher()
                }
                return self.handleRetry(urlRequest: urlRequest, retryCount: retryCount, error: error)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private func handleRetry<T: Codable>(urlRequest: URLRequest, retryCount: Int, error: NetworkError) -> AnyPublisher<T, NetworkError> {
        if retryCount > 0 && retryHandler.shouldRetry(request: urlRequest, error: error) {
            apiQueue.sync(flags: .barrier) {
                requestsToRetry.append(urlRequest)
            }
            let newUrlRequest = retryHandler.modifyRequestForRetry(client: self, request: requestsToRetry.last ?? urlRequest, error: error)
            if newUrlRequest.1 != nil {
                return Fail(error: newUrlRequest.1 ?? .unknown).eraseToAnyPublisher()
            }
            apiQueue.sync(flags: .barrier) {
                requestsToRetry.removeAll()
            }
            return makeRequest(urlRequest: newUrlRequest.0, retryCount: retryCount - 1)
        } else {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }
}

// MARK: APIClientAsyncAwaitRequestProtocol

extension APIClient: APIClientAsyncAwaitRequestProtocol {
    // MARK: - Async/Await Network Request

    func asyncRequest<T: Codable>(_ endpoint: NetworkRouter) async throws -> T {
        guard let urlRequest = try? endpoint.asURLRequest() else {
            throw NetworkError.unknown
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: NetworkError.unknown)
                return
            }
            apiQueue.async {
                Task {
                    do {
                        let result: T = try await self.makeAsyncRequest(urlRequest: urlRequest, retryCount: 3)
                        continuation.resume(returning: result)
                    } catch let error as NetworkError {
                        continuation.resume(throwing: error)
                    }catch{
                        continuation.resume(throwing: NetworkError.unknown)
                    }
                }
            }
        }
    }

    private func makeAsyncRequest<T: Codable>(urlRequest: URLRequest, retryCount: Int) async throws -> T {
        URLSessionLogger.shared.logRequest(urlRequest)

        let session = configuredSession()

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown
            }

            URLSessionLogger.shared.logResponse(response, data: data, error: nil)

            if 200 ..< 300 ~= httpResponse.statusCode {
                do {
                    let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                    return decodedResponse
                } catch {
                    throw mapErrorToNetworkError(error)
                }
            } else {
                let error = mapErrorResponse(data, statusCode: httpResponse.statusCode)
                throw error
            }
        } catch {
            return try await handleAsyncRetry(urlRequest: urlRequest, retryCount: retryCount, error: error)
        }
    }

    private func handleAsyncRetry<T: Codable>(urlRequest: URLRequest, retryCount: Int, error: Error) async throws -> T {
        let shouldRetry = await retryHandler.shouldRetryAsync(request: urlRequest, error: error as? NetworkError ?? .unknown)
        if retryCount > 0 && shouldRetry {
            apiQueue.sync(flags: .barrier) {
                requestsToRetry.append(urlRequest)
            }
            let newUrlRequest = try await retryHandler.modifyRequestForRetryAsync(client: self, request: requestsToRetry.last ?? urlRequest, error: error as? NetworkError ?? .unknown)
            apiQueue.sync(flags: .barrier) {
                requestsToRetry.removeAll()
            }
            return try await makeAsyncRequest(urlRequest: newUrlRequest, retryCount: retryCount - 1)
        } else {
            throw error
        }
    }
}

// MARK: APIClientUploadRequestProtocol

extension APIClient: APIClientUploadRequestProtocol {
    // MARK: - Upload Request

    func uploadRequest<T>(_ endpoint: NetworkRouter, withName: String, file: Data?, progressCompletion: @escaping (Double) -> Void) -> AnyPublisher<T, NetworkError> where T: Codable {
        guard let urlRequest = try? endpoint.asURLRequest(), let file else {
            return Fail(error: NetworkError.unknown).eraseToAnyPublisher()
        }

        return makeUploadRequest(urlRequest: urlRequest, params: endpoint.params, withName: withName, file: file, progressCompletion: progressCompletion, retryCount: 3).subscribe(on: apiQueue).eraseToAnyPublisher()
    }

    private func makeUploadRequest<T>(urlRequest: URLRequest, params: [String: Any]?, withName: String, file: Data, progressCompletion: @escaping (Double) -> Void, retryCount: Int) -> AnyPublisher<T, NetworkError> where T: Codable {
        URLSessionLogger.shared.logRequest(urlRequest)
        let (newUrlRequest, bodyData) = createBody(urlRequest: urlRequest, parameters: params, data: file, filename: withName)

        return Future<Data, NetworkError> { [weak self] promise in
            guard let self else {
                return
            }
            let progressDelegate = UploadProgressDelegate()
            progressDelegate.progressHandler = progressCompletion
            let session = configuredSession(delegate: progressDelegate)

            let task = session.uploadTask(with: newUrlRequest, from: bodyData) { data, response, error in
                URLSessionLogger.shared.logResponse(response, data: data, error: error)
                if let error = error {
                    promise(.failure(NetworkError.urlError(URLError(_nsError: error as NSError))))
                } else if let httpResponse = response as? HTTPURLResponse, let responseData = data {
                    if 200 ..< 300 ~= httpResponse.statusCode {
                        promise(.success(responseData))
                    } else {
                        URLSessionLogger.shared.logResponse(response, data: data, error: error)
                        promise(.failure(self.mapErrorResponse(responseData, statusCode: httpResponse.statusCode)))
                    }
                } else {
                    URLSessionLogger.shared.logResponse(response, data: data, error: error)
                    promise(.failure(NetworkError.unknown))
                }
            }
            task.resume()
        }
        .flatMap { [weak self] data -> AnyPublisher<T, NetworkError> in
            Just(data)
                .decode(type: T.self, decoder: JSONDecoder())
                .mapError { [weak self] error -> NetworkError in
                    URLSessionLogger.shared.logResponse(nil, data: nil, error: error)
                    return self?.mapErrorToNetworkError(error) ?? .unknown
                }
                .catch { [weak self] error -> AnyPublisher<T, NetworkError> in
                    guard let self else {
                        return Fail(error: NetworkError.unknown).eraseToAnyPublisher()
                    }
                    return self.handleRetry(urlRequest: urlRequest, retryCount: retryCount, error: error)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}

// MARK: APIClientAsyncAwaitUploadRequestProtocol

extension APIClient: APIClientAsyncAwaitUploadRequestProtocol {
    // MARK: - Async/Await Upload Request

    func asyncUploadRequest<T: Codable>(_ endpoint: NetworkRouter, withName: String, file: Data?, progressCompletion: @escaping (Double) -> Void) async throws -> T {
        guard let urlRequest = try? endpoint.asURLRequest(), let file else {
            throw NetworkError.unknown
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: NetworkError.unknown)
                return
            }
            apiQueue.async {
                Task {
                    do {
                        let result: T = try await self.makeAsyncUploadRequest(urlRequest: urlRequest, params: endpoint.params, withName: withName, file: file, progressCompletion: progressCompletion, retryCount: 3)
                        continuation.resume(returning: result)
                    } catch let error as NetworkError {
                        continuation.resume(throwing: error)
                    }catch{
                        continuation.resume(throwing: NetworkError.unknown)
                    }
                }
            }
        }
    }

    private func makeAsyncUploadRequest<T: Codable>(urlRequest: URLRequest, params: [String: Any]?, withName: String, file: Data, progressCompletion: @escaping (Double) -> Void, retryCount: Int) async throws -> T {
        URLSessionLogger.shared.logRequest(urlRequest)
        let (newUrlRequest, bodyData) = createBody(urlRequest: urlRequest, parameters: params, data: file, filename: withName)

        let progressDelegate = UploadProgressDelegate()
        progressDelegate.progressHandler = progressCompletion
        let session = configuredSession(delegate: progressDelegate)

        do {
            let (data, response) = try await session.upload(for: newUrlRequest, from: bodyData)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown
            }

            URLSessionLogger.shared.logResponse(response, data: data, error: nil)

            if 200 ..< 300 ~= httpResponse.statusCode {
                do {
                    let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                    return decodedResponse
                } catch {
                    throw mapErrorToNetworkError(error)
                }
            } else {
                let error = mapErrorResponse(data, statusCode: httpResponse.statusCode)
                throw error
            }
        } catch {
            return try await handleAsyncRetry(urlRequest: urlRequest, retryCount: retryCount, error: error)
        }
    }
}

// MARK: - Initialize Session

extension APIClient {
    private func configuredSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.default // Start with the default configuration
        // Modify the configuration as needed:
        configuration.timeoutIntervalForRequest = 120 // Set the request timeout to 30 seconds
        configuration.timeoutIntervalForResource = 120 // Set the resource timeout to 60 seconds
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Use the default caching
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

// MARK: - Error Handling

extension APIClient {
    private func mapErrorToNetworkError(_ error: Error) -> NetworkError {
        switch error {
            case let urlError as URLError:
                return NetworkError.urlError(urlError)
            case let decodingError as DecodingError:
                return NetworkError.decodingError(decodingError)
            case let error as NetworkError:
                return error
            default:
                return NetworkError.unknown
        }
    }

    // Convert error response to NetworkError
    private func mapErrorResponse(_ data: Data, statusCode: Int) -> NetworkError {
        do {
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            return NetworkError.customError(errorResponse)
        } catch {
            return NetworkError.decodingError(error)
        }
    }
}

// MARK: - Multipart Boundary

extension APIClient {
    private func createBody(urlRequest: URLRequest, parameters: [String: Any]?, data: Data, filename: String) -> (URLRequest, Data) {
        var newUrlRequest = urlRequest
        let boundary = "Boundary-\(UUID().uuidString)"
        let mime = Swime.mimeType(data: data)
        newUrlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        if let parameters = parameters, !parameters.isEmpty {
            for (key, value) in parameters {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
        }

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename).\(mime?.ext ?? "")\"\r\n")
        body.appendString("Content-Type: \(mime?.mime ?? "")\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        return (newUrlRequest, body)
    }
}
