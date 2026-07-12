import Foundation
import CryptoKit

enum S3Error: LocalizedError {
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case invalidCredentials
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Endpoint URL: \(url)"
        case .requestFailed(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidCredentials:
            return "Invalid AWS Credentials"
        case .unknown(let msg):
            return "Unknown Error: \(msg)"
        }
    }
}

struct S3Object: Identifiable {
    var id: String { key }
    let key: String
    let size: Int64
    let lastModified: String
    let isVirtualFolder: Bool

    init(key: String, size: Int64 = 0, lastModified: String = "", isVirtualFolder: Bool = false) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.isVirtualFolder = isVirtualFolder
    }
}

class S3Client {
    let endpoint: String   // bare host e.g. "s3.us-west-004.backblazeb2.com"
    let bucket: String
    let accessKey: String
    let secretKey: String
    let region: String

    init(endpoint: String, bucket: String, accessKey: String, secretKey: String) {
        var sanitized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.hasSuffix("/") { sanitized.removeLast() }
        if !sanitized.lowercased().hasPrefix("http://") && !sanitized.lowercased().hasPrefix("https://") {
            sanitized = "https://" + sanitized
        }

        if let host = URL(string: sanitized)?.host {
            self.endpoint = host
            let parts = host.split(separator: ".")
            self.region = (parts.count >= 2 && parts[0] == "s3") ? String(parts[1]) : "us-east-1"
        } else {
            self.endpoint = sanitized.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            self.region = "us-east-1"
        }

        self.bucket   = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core Signing

    @discardableResult
    func execute(method: String, path: String, queryItems: [URLQueryItem] = [], payload: Data?, contentType: String = "application/octet-stream") async throws -> Data {

        let safePath = path == "/" || path.isEmpty ? "" : "/" + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host   = endpoint
        urlComponents.path   = "/\(bucket)\(safePath)"
        if !queryItems.isEmpty { urlComponents.queryItems = queryItems }

        guard let url = urlComponents.url else { throw S3Error.invalidURL("/\(bucket)\(safePath)") }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Dates
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate   = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        let body = payload ?? Data()
        let payloadHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()
        let contentLength = "\(body.count)"

        // Set headers
        request.setValue(endpoint,      forHTTPHeaderField: "host")
        request.setValue(amzDate,       forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash,   forHTTPHeaderField: "x-amz-content-sha256")

        // AWS SigV4 strictly requires percent encoding everything except A-Z, a-z, 0-9, -, _, ., and ~
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        
        let canonicalURI = url.path.isEmpty ? "/" : url.path.components(separatedBy: "/").map { $0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0 }.joined(separator: "/")
        
        let canonicalQuery = queryItems.isEmpty ? "" : queryItems
            .sorted { $0.name < $1.name }
            .map { "\($0.name.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0.name)=\(($0.value ?? "").addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")

        let canonicalHeaders: String
        let signedHeaders: String

        if method == "PUT" || method == "POST" {
            request.setValue(contentType,    forHTTPHeaderField: "content-type")
            request.setValue(contentLength,  forHTTPHeaderField: "content-length")
            canonicalHeaders = "content-length:\(contentLength)\ncontent-type:\(contentType)\nhost:\(endpoint)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
            signedHeaders    = "content-length;content-type;host;x-amz-content-sha256;x-amz-date"
        } else {
            canonicalHeaders = "host:\(endpoint)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
            signedHeaders    = "host;x-amz-content-sha256;x-amz-date"
        }

        let canonicalRequest = [method, canonicalURI, canonicalQuery, canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).compactMap { String(format: "%02x", $0) }.joined()

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, credentialScope, canonicalRequestHash].joined(separator: "\n")

        let kSecret  = Data("AWS4\(secretKey)".utf8)
        let kDate    = hmac(key: kSecret,  data: dateStamp)
        let kRegion  = hmac(key: kDate,    data: region)
        let kService = hmac(key: kRegion,  data: "s3")
        let kSigning = hmac(key: kService, data: "aws4_request")
        let signature = hmac(key: kSigning, data: stringToSign).compactMap { String(format: "%02x", $0) }.joined()

        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, response): (Data, URLResponse)

            if (method == "PUT" || method == "POST") && !body.isEmpty {
                // Use upload(for:from:) which correctly sets Content-Length
                (data, response) = try await URLSession.shared.upload(for: request, from: body)
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
                throw S3Error.requestFailed(statusCode: http.statusCode, message: bodyStr)
            }
            return data
        } catch let e as S3Error { throw e }
        catch { throw S3Error.unknown(error.localizedDescription) }
    }

    private func hmac(key: Data, data: String) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))
        return Data(mac)
    }

    // MARK: - Operations

    func headBucket() async throws {
        try await execute(method: "HEAD", path: "/", payload: nil)
    }

    func putObject(path: String, fileURL: URL, contentType: String) async throws {
        let fileData = try Data(contentsOf: fileURL)
        try await execute(method: "PUT", path: path, payload: fileData, contentType: contentType)
    }

    func deleteObject(path: String) async throws {
        try await execute(method: "DELETE", path: path, payload: nil)
    }

    /// Delete all objects whose key starts with the given prefix (used to "delete" a virtual folder).
    func deleteFolder(prefix: String) async throws {
        // List ALL objects under this prefix (no delimiter – recurse fully)
        let allItems: [URLQueryItem] = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "max-keys",  value: "1000"),
            URLQueryItem(name: "prefix",    value: prefix),
        ]
        let data = try await execute(method: "GET", path: "/", queryItems: allItems, payload: nil)
        let parser = S3ListXMLParser(data: data)
        let objects = parser.parseAll()   // parse without delimiter so we get all keys
        
        for obj in objects {
            try await execute(method: "DELETE", path: obj.key, payload: nil)
        }
    }

    /// List objects using delimiter to get virtual folders at the given prefix.
    func listObjects(prefix: String = "") async throws -> [S3Object] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "list-type",  value: "2"),
            URLQueryItem(name: "max-keys",   value: "1000"),
            URLQueryItem(name: "delimiter",  value: "/"),
        ]
        if !prefix.isEmpty {
            items.append(URLQueryItem(name: "prefix", value: prefix))
        }

        let data = try await execute(method: "GET", path: "/", queryItems: items, payload: nil)
        return parseListObjectsXML(data)
    }

    private func parseListObjectsXML(_ data: Data) -> [S3Object] {
        let parser = S3ListXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - XML Parser helper

private class S3ListXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var objects: [S3Object] = []
    // Contents
    private var currentKey      = ""
    private var currentSize     = ""
    private var currentModified = ""
    private var currentElement  = ""
    private var inContents      = false
    private var inCommonPrefixes = false

    init(data: Data) { self.data = data }

    func parse() -> [S3Object] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        // Sort: folders first, then files alphabetically
        return objects.sorted {
            if $0.isVirtualFolder != $1.isVirtualFolder { return $0.isVirtualFolder }
            return $0.key < $1.key
        }
    }
    
    /// Parse all objects (including nested) without virtual-folder grouping — used for recursive deletes.
    func parseAll() -> [S3Object] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return objects.filter { !$0.isVirtualFolder }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Contents" {
            inContents = true
            currentKey = ""; currentSize = ""; currentModified = ""
        }
        if elementName == "CommonPrefixes" {
            inCommonPrefixes = true
            currentKey = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "Key":          currentKey      += s
        case "Size":         currentSize     += s
        case "LastModified": currentModified += s
        case "Prefix":
            if inCommonPrefixes { currentKey += s }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Contents" && inContents {
            // Skip folder-marker objects (zero-byte objects whose key ends with /)
            if !currentKey.hasSuffix("/") || Int64(currentSize) ?? 0 > 0 {
                objects.append(S3Object(key: currentKey, size: Int64(currentSize) ?? 0, lastModified: currentModified))
            }
            inContents = false
        }
        if elementName == "CommonPrefixes" && inCommonPrefixes {
            if !currentKey.isEmpty {
                objects.append(S3Object(key: currentKey, isVirtualFolder: true))
            }
            inCommonPrefixes = false
        }
        currentElement = ""
    }
}
