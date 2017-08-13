import Debugging
import HTTP

/// A basic conformance to `AbortError` for
/// convenient error throwing
public struct Abort: AbortError, Debuggable {
    public let status: Status
    public let metadata: Node?

    // MARK: Debuggable

    /// See Debuggable.readableName
    public static let readableName = "Abort request error"

    /// See AbortError.reason
    public let reason: String

    /// See Debuggable.identifier
    public let identifier: String

    /// See Debuggable.possibleCauses
    public let possibleCauses: [String]

    /// See Debuggable.possibleCauses
    public let suggestedFixes: [String]

    /// See Debuggable.documentationLinks
    public let documentationLinks: [String]

    /// See Debuggable.stackOverflowQuestions
    public let stackOverflowQuestions: [String]

    /// See Debuggable.gitHubIssues
    public let gitHubIssues: [String]
    
    /// File in which the error was thrown
    public let file: String
    
    /// Line number at which the error was thrown
    public let line: Int
    
    /// The column at which the error was thrown
    public let column: Int
    
    /// The function in which the error was thrown
    /// TODO: waiting on https://bugs.swift.org/browse/SR-5380
    /// public let function: String

    public init(
        _ status: Status,
        metadata: Node? = nil,
        // Debuggable
        reason: String? = nil,
        identifier: String? = nil,
        possibleCauses: [String]? = nil,
        suggestedFixes: [String]? = nil,
        documentationLinks: [String]? = nil,
        stackOverflowQuestions: [String]? = nil,
        gitHubIssues: [String]? = nil,
        file: String = #file,
        line: Int = #line,
        column: Int = #column
        /// See TODO in property decl
        /// function: String = #function
    ) {
        self.status = status
        self.metadata = metadata
        self.reason = reason ?? status.reasonPhrase
        self.identifier = identifier ?? "\(status)"
        self.possibleCauses = possibleCauses ?? []
        self.suggestedFixes = suggestedFixes ?? []
        self.documentationLinks = documentationLinks ?? []
        self.stackOverflowQuestions = stackOverflowQuestions ?? []
        self.gitHubIssues = gitHubIssues ?? []
        self.file = file
        self.line = line
        self.column = column
        /// See TODO in property decl
        /// self.function = function
    }

    // most common
    public static let badRequest = Abort(.badRequest)
    public static let unauthorized = Abort(.unauthorized)
    public static let notFound = Abort(.notFound)
    public static let serverError = Abort(.internalServerError)
}
