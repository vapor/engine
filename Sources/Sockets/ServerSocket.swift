import Dispatch

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/// A server socket can accept peers. Each accepted peer get's it own socket after accepting.
public final class ServerSocket : TCPSocket {
    /// A closure to call with each new connected client
    public var onConnect: ((RemoteClient) -> ())? = nil
    
    /// The dispatch queue that peers are accepted on.
    let queue: DispatchQueue
    
    /// Creates a new Server Socket
    ///
    /// - parameter hostname: The hostname to listen to. By default, all hostnames will be accepted
    /// - parameter port: The port to listen on.
    /// - throws: If reserving a socket failed.
    public init(hostname: String = "0.0.0.0", port: UInt16) throws {
        // Default to `.userInteractive` because this is a single thread responsible for *all* incoming connections
        self.queue = DispatchQueue(label: "codes.vapor.clientConnectQueue", qos: .userInteractive)
        
        try super.init(hostname: hostname, port: port, server: true, dispatchQueue: queue)
    }
    
    /// Starts listening for peers asynchronously
    ///
    /// - parameter maxIncomingConnections: The maximum backlog of incoming connections. Defaults to 4096.
    public func start(maxIncomingConnections: Int32 = 4096) throws {
        // Cast the address
        let addr =  UnsafeMutablePointer<sockaddr>(OpaquePointer(self.socketAddress))
        let addrSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        // Bind to the address
        guard bind(self.descriptor, addr, addrSize) > -1 else {
            throw TCPError.bindFailure
        }
        
        // Start listening on the address
        guard listen(self.descriptor, maxIncomingConnections) > -1 else {
            throw TCPError.bindFailure
        }
        
        // Stores all clients so they won't be deallocated in the async process
        // Refers to clients by their file descriptor
        var clients = [Int32 : RemoteClient]()
        
        // For every connected client, this closure triggers
        readSource.setEventHandler {
            // Prepare for a client's connection
            let addr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
            let addrSockAddr = UnsafeMutablePointer<sockaddr>(OpaquePointer(addr))
            var a = socklen_t(MemoryLayout<sockaddr_storage>.size)
            
            // Accept the new client
            let clientDescriptor = accept(self.descriptor, addrSockAddr, &a)
            
            // If the accept failed, deallocate the reserved address memory and return
            guard clientDescriptor > -1 else {
                addr.deallocate(capacity: 1)
                return
            }
            
            let client = RemoteClient(descriptor: clientDescriptor, addr: addr) {
                self.queue.sync {
                    clients[clientDescriptor] = nil
                    addr.deallocate(capacity: 1)
                }
            }
            
            self.queue.sync {
                clients[clientDescriptor] = client
            }
            
            self.onConnect?(client)
        }
        
        self.readSource.resume()
    }
}