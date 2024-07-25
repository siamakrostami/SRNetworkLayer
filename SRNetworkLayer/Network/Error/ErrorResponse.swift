
import Foundation

struct ErrorResponse: Codable {
    let code: String
    let details: String
    let message: String
    let path: String
    let suggestion: String
    let timestamp: String
}
