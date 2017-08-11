import SMTP
import URI
import FormData
import Multipart
import Service
import HTTP
import JSON

public final class Mailgun: MailProtocol {
    public let clientFactory: ClientFactoryProtocol
    public let apiURI: URI
    public let apiKey: String
    
    public init(
        domain: String,
        apiKey: String,
        _ clientFactory: ClientFactoryProtocol
    ) throws {
        self.apiURI = try URI("https://api.mailgun.net/v3/\(domain)/")
        self.clientFactory = clientFactory
        self.apiKey = apiKey
    }
    
    public func send(_ emails: [Email]) throws {
        try emails.forEach(_send)
    }
    
    private func _send(_ mail: Email) throws {
        let uri = apiURI.appendingPathComponent("messages")
        let req = Request(method: .post, uri: uri)
        
        let basic = "api:\(apiKey)".makeBytes().base64Encoded.makeString()
        req.headers["Authorization"] = "Basic \(basic)"
        
        var json = JSON()
        try json.set("subject", to: mail.subject)
        switch mail.body.type {
        case .html:
            try json.set("html", to: mail.body.content)
        case .plain:
            try json.set("text", to: mail.body.content)
        }
        
        let fromName = mail.from.name ?? "Vapor Mailgun"
        let from = FormData.Field(
            name: "from",
            filename: nil,
            part: Part(
                headers: [:],
                body: "\(fromName) <\(mail.from.address)>".makeBytes()
            )
        )
        
        let to = FormData.Field(
            name: "to",
            filename: nil,
            part: Part(
                headers: [:],
                body: mail.to.map({ $0.address }).joined(separator: ", ").makeBytes()
            )
        )
        
        let subject = FormData.Field(
            name: "subject",
            filename: nil,
            part: Part(
                headers: [:],
                body: mail.subject.makeBytes()
            )
        )
        
        let bodyKey: String
        switch mail.body.type {
        case .html:
            bodyKey = "html"
        case .plain:
            bodyKey = "text"
        }
        
        let body = FormData.Field(
            name: bodyKey,
            filename: nil,
            part: Part(
                headers: [:],
                body: mail.body.content.makeBytes()
            )
        )
        
        req.formData = [
            "from": from,
            "to": to,
            "subject": subject,
            bodyKey: body
        ]
        
        if let replyTo = mail.extendedFields["h:Reply-To"] {
            let part = Part(headers: [:], body: replyTo.makeBytes())
            req.formData?["h:Reply-To"] = Field(name: "h:Reply-To", filename: nil, part: part)
        }
        
        let client = try clientFactory.makeClient(
            hostname: apiURI.hostname,
            port: apiURI.port ?? 443,
            securityLayer: .tls(EngineClient.defaultTLSContext())
        )
        let res = try client.respond(to: req)
        guard res.status.statusCode < 400 else {
            throw Abort.badRequest
        }
    }
}

// MARK: Service

extension Mailgun: ServiceType {
    /// See Service.serviceSupports
    public static var serviceSupports: [Any.Type] {
        return [MailProtocol.self]
    }

    /// See Service.make
    public static func makeService(for container: Container) throws -> Mailgun? {
        guard let mailgun = container.config["mailgun"] else {
            throw ConfigError.missingFile("mailgun")
        }
        
        guard let domain = mailgun["domain"]?.string else {
            throw ConfigError.missing(key: ["domain"], file: "mailgun", desiredType: String.self)
        }
        
        guard let apiKey = mailgun["key"]?.string else {
            throw ConfigError.missing(key: ["key"], file: "mailgun", desiredType: String.self)
        }
        
        let client = try container.make(ClientFactoryProtocol.self)
        return try .init(domain: domain, apiKey: apiKey, client)
    }
}
