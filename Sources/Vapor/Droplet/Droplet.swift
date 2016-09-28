import HTTP
import Console
import Cache
import Sessions
import HMAC
import Cipher
import Fluent

public let VERSION = "1.0.2"

public class Droplet {
    /**
     The arguments passed to the droplet.
     */
    public let arguments: [String]

    /**
        The work directory of your droplet is
        the directory in which your Resources, Public, etc
        folders are stored. This is normally `./` if
        you are running Vapor using `.build/xxx/drop`
    */
    public let workDir: String

    /**
        Resources directory relative to workDir
    */
    public var resourcesDir: String {
        return workDir + "Resources/"
    }

    public var viewsDir: String {
        return resourcesDir + "Views/"
    }

    /**
        The current droplet environment
    */
    public let environment: Environment

    /**
        Provides access to config settings.
    */
    public let config: Settings.Config

    /**
        Provides access to language specific
        strings and defaults.
    */
    public let localization: Localization



    /**
        The router driver is responsible
        for returning registered `Route` handlers
        for a given request.
    */
    public var router: Router

    /**
        The server that will accept requesting
        connections and return the desired
        response.
    */
    public var server: ServerProtocol.Type

    /**
        Expose to end users to customize driver
        Make outgoing requests
    */
    public var client: ClientProtocol.Type

    /**
        `Middleware` will be applied in the order
        it is set in this array.

        Make sure to append your custom `Middleware`
        if you don't want to overwrite default behavior.
    */
    public var middleware: [Middleware]


    /**
        Send informational and error logs.
        Defaults to the console.
     */
    public var log: Log

    /**
        Provides access to the underlying
        `HashProtocol` for hashing data.
    */
    public var hash: HashProtocol

    /**
        Provides access to the underlying
        `CipherProtocol` for encrypting and
        decrypting data.
    */
    public var cipher: CipherProtocol


    /**
        Available Commands to use when starting
        the droplet.
    */
    public var commands: [Command]

    /**
         Send output and receive input from the console
         using the underlying `ConsoleDriver`.
    */
    public var console: ConsoleProtocol

    /**
        Render static and templated views.
    */
    public var view: ViewRenderer

    /**
        Store and retreive key:value
        pair information.
    */
    public var cache: CacheProtocol

    /**
        The Database for this Droplet
        to run preparations on, if supplied.
    */
    public var database: Database?

    /**
        Preparations for using the database.
    */
    public var preparations: [Preparation.Type]

    /**
        Storage to add/manage dependencies, identified by a string
    */
    public var storage: [String: Any]

    /**
        The providers that have been added.
    */
    public internal(set) var providers: [Provider]

    internal private(set) lazy var routerResponder: Request.Handler = Request.Handler { [weak self] request in
        // Routed handler
        if let handler = self?.router.route(request, with: request) {
            return try handler.respond(to: request)
        } else {
            // Default not found handler
            let normal: [HTTP.Method] = [.get, .post, .put, .patch, .delete]

            if normal.contains(request.method) {
                throw Abort.notFound
            } else if case .options = request.method {
                return Response(status: .ok, headers: [
                    "Allow": "OPTIONS"
                    ])
            } else {
                return Response(status: .notImplemented)
            }
        }
    }

    /**
        Initialize the Droplet.
    */
    public init(
        arguments: [String]? = nil,
        workDir workDirProvided: String? = nil,
        environment environmentProvided: Environment? = nil,
        config configProvided: Settings.Config? = nil,
        localization localizationProvided: Localization? = nil
    ) {
        // use arguments provided in init or
        // default to the arguments provided
        // via the command line interface
        let arguments = arguments ?? CommandLine.arguments
        self.arguments = arguments

        // logging is needed for emitting errors
        let console = Terminal(arguments: arguments)
        let log = ConsoleLogger(console: console)

        // use the working directory provided
        // or attempt to find a working directory
        // from the command line arguments or #file.
        let workDir: String
        if let provided = workDirProvided {
            workDir = provided.finished(with: "/")
        } else {
            workDir = Droplet.workingDirectory(from: arguments).finished(with: "/")
        }
        self.workDir = workDir.finished(with: "/")

        // the current droplet environment
        let environment: Environment
        if let provided = environmentProvided {
            environment = provided
        } else {
            environment = CommandLine.environment ?? .development
        }
        self.environment = environment

        // use the config item provided or
        // attempt to create a config from
        // the working directory and arguments
        let config: Settings.Config
        if let provided = configProvided {
            config = provided
        } else {
            do {
                let configDirectory = workDir.finished(with: "/") + "Config/"
                config = try Settings.Config(
                    prioritized: [
                        .commandLine,
                        .directory(root: configDirectory + "secrets"),
                        .directory(root: configDirectory + environment.description),
                        .directory(root: configDirectory)
                    ]
                )
            } catch {
                log.error("Could not load configuration files: \(error)")
                config = Config([:])
            }
        }
        self.config = config

        // use the provided localization or
        // initialize one from the working directory.
        let localization: Localization
        if let provided = localizationProvided {
            localization = provided
        } else {
            do {
                localization = try Localization(localizationDirectory: workDir + "Localization/")
            } catch {
                log.error("Could not load localization files: \(error)")
                localization = Localization()
            }
        }
        self.localization = localization

        router = Router()
        server = BasicServer.self
        client = BasicClient.self
        middleware = []
        self.log = log
        self.console = console
        commands = []
        view = LeafRenderer(viewsDir: workDir + "Resources/Views")
        cache = MemoryCache()
        database = nil
        storage = [:]
        preparations = []
        providers = []

        // hash
        let hashMethod: HMAC.Method
        if let method = config["crypto", "hash", "method"]?.string {
            switch method {
            case "sha1":
                hashMethod = .sha1
            case "sha224":
                hashMethod = .sha224
            case "sha256":
                hashMethod = .sha256
            case "sha384":
                hashMethod = .sha384
            case "sha512":
                hashMethod = .sha512
            case "md4":
                hashMethod = .md4
            case "md5":
                hashMethod = .md5
            case "ripemd160":
                hashMethod = .ripemd160
            default:
                log.error("Unsupported hash method: \(method), using SHA-256.")
                hashMethod = .sha256
            }
        } else {
            hashMethod = .sha256
        }
        let hashKey = config["crypto", "hash", "key"]?.string?.bytes
        hash = CryptoHasher(method: hashMethod, defaultKey: hashKey)

        // cipher
        let cipherMethod: Cipher.Method
        if let method = config["crypto", "cipher", "method"]?.string {
            switch method {
            case "chacha20":
                cipherMethod = .chacha20
            case "aes128":
                cipherMethod = .aes128(.cbc)
            case "aes256":
                cipherMethod = .aes256(.cbc)
            default:
                log.error("Unsupported cipher method: \(method), using Chacha20.")
                cipherMethod = .chacha20
            }
        } else {
            cipherMethod = .chacha20
        }
        let cipherKey: Bytes
        if let k = config["crypto", "cipher", "key"]?.string {
            cipherKey = k.bytes
        } else {
            log.error("No cipher key was set, using blank key.")
            cipherKey = Bytes(repeating: 0, count: 32)
        }
        let cipherIV = config["crypto", "cipher", "iv"]?.string?.bytes
        cipher = CryptoCipher(method: cipherMethod, defaultKey: cipherKey, defaultIV: cipherIV)

        // verify cipher
        if let c = cipher as? CryptoCipher {
            switch c.method {
            case .chacha20:
                if cipherKey.count != 32 {
                    log.error("Chacha20 cipher key must be 32 bytes.")
                }
                if cipherIV == nil {
                    log.error("Chacha20 cipher requires an initialization vector (iv).")
                } else if cipherIV?.count != 8 {
                    log.error("Chacha20 initialization vector (iv) must be 8 bytes.")
                }
            case .aes128:
                if cipherKey.count != 16 {
                    log.error("AES-128 cipher key must be 16 bytes.")
                }
            case .aes256:
                if cipherKey.count != 16 {
                    log.error("AES-256 cipher key must be 16 bytes.")
                }
            default:
                log.warning("Using unofficial cipher, ensure key and possibly initialization vector (iv) are set properly.")
                break
            }
        }


        // add in middleware depending on config
        var configurableMiddleware: [String: Middleware] = [
            "file": FileMiddleware(workDir: workDir),
            "validation": ValidationMiddleware(),
            "date": DateMiddleware(),
            "type-safe": TypeSafeErrorMiddleware(),
            "abort": AbortMiddleware(),
            "sessions": SessionsMiddleware(sessions: MemorySessions())
        ]

        if let array = config["middleware", "server"]?.array {
            // add all middleware specified by
            // config files
            for item in array {
                if let name = item.string, let m = configurableMiddleware[name] {
                    middleware.append(m)
                } else {
                    log.error("Invalid server middleware: \(item.string ?? "unknown")")
                }
            }
        } else {
            // if not config was supplied,
            // use whatever middlewares were
            // provided
            middleware += Array(configurableMiddleware.values)
        }

        // prepare for production mode
        if environment == .production {
            console.output("Production mode enabled, disabling informational logs.", style: .info)
            log.enabled = [.error, .fatal]
        }

        // hook into all providers after init
        for provider in providers {
            provider.afterInit(self)
        }
    }

    func serverErrors(error: ServerError) {
        log.error("Server error: \(error)")
    }
}
