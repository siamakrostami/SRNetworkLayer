import Foundation

class NetworkRepositories {
    // MARK: Lifecycle

    init(client: APIClient) {
        self.client = client
    }

    // MARK: Internal

    var loginServices: LoginService? {
        initializationQueue.sync {
            if _loginServices == nil {
                _loginServices = LoginService(client: client)
            }
            return _loginServices
        }
    }

    // MARK: Private

    private let client: APIClient
    private let initializationQueue = DispatchQueue(label: "com.networkRepositories.initializationQueue")
    
    // MARK: - Auth

    private var _loginServices: LoginService?
}
