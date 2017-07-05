/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import GCDWebServers

class WebServer {
    static let WebServerSharedInstance = WebServer()

    class var sharedInstance: WebServer {
        return WebServerSharedInstance
    }

    let server: GCDWebServer = GCDWebServer()

    var base: String {
        return "http://localhost:\(server.port)"
    }

    static var port = 5309
    static let kMaxPortNum = 5400

    func start() throws -> Bool{
        if !server.isRunning {
          do {
            try server.start(options: [GCDWebServerOption_Port: WebServer.port, GCDWebServerOption_BindToLocalhost: true, GCDWebServerOption_AutomaticallySuspendInBackground: true])
          } catch {
            if (WebServer.port < WebServer.kMaxPortNum) {
                WebServer.port += 1
                return try start()
            }
          }
        }
        return server.isRunning
    }

    /// Convenience method to register a dynamic handler. Will be mounted at $base/$module/$resource
    func registerHandlerForMethod(_ method: String, module: String, resource: String, handler: @escaping (_ request: GCDWebServerRequest?) -> GCDWebServerResponse!) {
        server.addHandler(forMethod: method, path: "/\(module)/\(resource)", request: GCDWebServerRequest.self, processBlock: handler)
    }

    /// Convenience method to register a resource in the main bundle. Will be mounted at $base/$module/$resource
    func registerMainBundleResource(_ resource: String, module: String) {
        if let path = Bundle.main.path(forResource: resource, ofType: nil) {
            server.addGETHandler(forPath: "/\(module)/\(resource)", filePath: path, isAttachment: false, cacheAge: UInt.max, allowRangeRequests: true)
        }
    }

    /// Convenience method to register all resources in the main bundle of a specific type. Will be mounted at $base/$module/$resource
    func registerMainBundleResourcesOfType(_ type: String, module: String) {
        for path in Bundle.paths(forResourcesOfType: type, inDirectory: Bundle.main.bundlePath) {
            let resource = URL(string: path)?.lastPathComponent ?? ""
            server.addGETHandler(forPath: "/\(module)/\(resource)", filePath: path, isAttachment: false, cacheAge: UInt.max, allowRangeRequests: true)
        }
    }

    /// Return a full url, as a string, for a resource in a module. No check is done to find out if the resource actually exist.
    func URLForResource(_ resource: String, module: String) -> String {
        return "\(base)/\(module)/\(resource)"
    }

    /// Return a full url, as an NSURL, for a resource in a module. No check is done to find out if the resource actually exist.
    func URLForResource(_ resource: String, module: String) -> URL {
        return URL(string: "\(base)/\(module)/\(resource)")!
    }

    func updateLocalURL(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.host == "localhost" && components?.scheme == "http" {
            components?.port = Int(WebServer.sharedInstance.server.port)
        }
        return components?.url
    }
}
