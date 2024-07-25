
import Foundation

// MARK: - AppEnvironment

struct AppEnvironment {
    private static let setupQueue = DispatchQueue(label: "com.appEnvironment.setupQueue")
}

extension AppEnvironment {
    static func setup() -> Self {
        setupQueue.sync {
            Dependency.register(NetworkRepositories(client: APIClient().set(interceptor: NetworkInterceptor(numberOfRetries: 3))))
        }
        return AppEnvironment()
    }
}
