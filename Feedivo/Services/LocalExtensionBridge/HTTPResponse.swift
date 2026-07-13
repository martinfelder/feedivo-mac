import Foundation

struct HTTPResponse {
    var statusCode: Int
    var statusText: String
    var body: Data
    var contentType: String = "application/json"

    static func json(statusCode: Int, statusText: String, object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, statusText: statusText, body: body)
    }

    func serialize() -> Data {
        var head = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
