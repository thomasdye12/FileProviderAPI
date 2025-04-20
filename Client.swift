//
//  APIClient.swift
//  TDS Cloud
//
//  Created by Thomas Dye on 20/04/2025.
//

import Foundation
import FileProvider

// 1) Helper to do URL‑safe Base64 encoding
extension String {
    var base64URLEncoded: String {
        let data = Data(self.utf8)
        var str = data.base64EncodedString()
        // make URL‑safe
        str = str
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return str
    }
}




// 4) A tiny API client that injects the auth header
class APIClient {
    static let shared = APIClient()
    private init() {}

    private func makeRequest(to url: URL,
                             method: String,
                             body: Data? = nil,
                             contentType: String? = nil) -> URLRequest
    {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(AuthManager.shared.bearerToken)",
                     forHTTPHeaderField: "Authorization")
        if let ct = contentType {
            req.setValue(ct, forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = body
        return req
    }

    func listItems(parentId: NSFileProviderItemIdentifier?,
                   completion: @escaping (Result<[[String:Any]], Error>) -> Void)
    {
        let url = URLs.list(parentId: parentId)
        let req = makeRequest(to: url, method: "GET")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String:Any]]
            else {
                return completion(.failure(NSError()))
            }
            completion(.success(json))
        }.resume()
    }

    func getMetadata(itemId: NSFileProviderItemIdentifier,
                     completion: @escaping (Result<[String:Any], Error>) -> Void)
    {
        let url = URLs.metadata(itemId: itemId)
        let req = makeRequest(to: url, method: "GET")
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            // 1) Network error
            if let err = err {
                return completion(.failure(err))
            }
            // 2) Must have data
            guard let data = data else {
                let e = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"]
                )
                return completion(.failure(e))
            }
            // 3) Parse JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else {
                let e = NSError(
                    domain: "APIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
                )
                return completion(.failure(e))
            }
            // 4) Validate “id” field
            guard let idString = json["id"] as? String, !idString.isEmpty else {
                let e = NSError(
                    domain: "APIClient",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid 'id' in metadata"]
                )
                return completion(.failure(e))
            }
            // 5) All good
            completion(.success(json))
        }
        .resume()
    }


    func downloadContent(itemId: NSFileProviderItemIdentifier,
                         to localURL: URL,
                         completion: @escaping (Result<URL, Error>) -> Void)
    {
        let url = URLs.content(itemId: itemId)
        let req = makeRequest(to: url, method: "GET")
        URLSession.shared.downloadTask(with: req) { tmp, _, err in
            if let err = err { return completion(.failure(err)) }
            guard let tmp = tmp else {
                return completion(.failure(NSError()))
            }
            do {
                try FileManager.default.moveItem(at: tmp, to: localURL)
                completion(.success(localURL))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func createItem(parentId: NSFileProviderItemIdentifier?,
                    name: String,
                    type: String, // "file" or "folder"
                    completion: @escaping (Result<[String:Any], Error>) -> Void)
    {
        let url = URLs.create
        var body: [String:Any] = ["name": name, "type": type]
        if let pid = parentId, pid != .rootContainer {
            body["parentId"] = pid.rawValue.base64URLEncoded
        }
        let data = try? JSONSerialization.data(withJSONObject: body)
        var req = makeRequest(to: url, method: "POST", body: data, contentType: "application/json")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            // 1) Network error
            if let err = err {
                return completion(.failure(err))
            }
            // 2) Must have data
            guard let data = data else {
                let e = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"]
                )
                return completion(.failure(e))
            }
            // 3) Parse JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else {
                let e = NSError(
                    domain: "APIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
                )
                return completion(.failure(e))
            }
            // 4) Validate “id” field
            guard let idString = json["id"] as? String, !idString.isEmpty else {
                let e = NSError(
                    domain: "APIClient",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid 'id' in metadata"]
                )
                return completion(.failure(e))
            }
            // 5) All good
            completion(.success(json))
        }
        .resume()
    }

    func updateItem(itemId: NSFileProviderItemIdentifier,
                    newName: String?,
                    newParent: NSFileProviderItemIdentifier?,
                    completion: @escaping (Result<[String:Any], Error>) -> Void)
    {
        let url = URLs.update(itemId: itemId)
        var body = [String:Any]()
        if let n = newName        { body["name"]     = n }
        if let p = newParent,
           p != .rootContainer    { body["parentId"] = p.rawValue.base64URLEncoded }
        let data = try? JSONSerialization.data(withJSONObject: body)
        let req = makeRequest(to: url, method: "POST", body: data, contentType: "application/json")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            // 1) Network error
            if let err = err {
                return completion(.failure(err))
            }
            // 2) Must have data
            guard let data = data else {
                let e = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"]
                )
                return completion(.failure(e))
            }
            // 3) Parse JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else {
                let e = NSError(
                    domain: "APIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
                )
                return completion(.failure(e))
            }
            // 4) Validate “id” field
            guard let idString = json["id"] as? String, !idString.isEmpty else {
                let e = NSError(
                    domain: "APIClient",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid 'id' in metadata"]
                )
                return completion(.failure(e))
            }
            // 5) All good
            completion(.success(json))
        }
        .resume()
    }

    func deleteItem(itemId: NSFileProviderItemIdentifier,
                    completion: @escaping (Result<Void, Error>) -> Void)
    {
        let url = URLs.delete(itemId: itemId)
        let req = makeRequest(to: url, method: "DELETE")
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { return completion(.failure(err)) }
            completion(.success(()))
        }.resume()
    }

    func uploadContent(itemId: NSFileProviderItemIdentifier,
                       fileURL: URL,
                       completion: @escaping (Result<[String:Any], Error>) -> Void)
    {
        let url = URLs.upload(itemId: itemId)
        var req = makeRequest(to: url, method: "POST")
        // multipart/form-data boundary
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        // build body
        var data = Data()
        let fname = fileURL.lastPathComponent
        data.append("--\(boundary)\r\n".data(using:.utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fname)\"\r\n\r\n".data(using:.utf8)!)
        data.append(try! Data(contentsOf: fileURL))
        data.append("\r\n--\(boundary)--\r\n".data(using:.utf8)!)
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { return completion(.failure(err)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any]
            else {
                return completion(.failure(NSError()))
            }
            completion(.success(json))
        }.resume()
    }
}

extension FileProviderItem {
    // These keys match your JSON format:
    var lastUsedDate: Date? {
        guard let ts = info["lastUsedDate"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var tagData: Data? {
        return info["tagData"] as? Data
    }

    var favoriteRank: Int? {
        return info["favoriteRank"] as? Int
    }

    var creationDate: Date? {
        guard let ts = info["createdAt"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var contentModificationDate: Date? {
        guard let ts = info["contentModificationDate"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var fileSystemFlags: Int? {
        return info["fileSystemFlags"] as? Int
    }

    var extendedAttributes: [String: String]? {
        return info["extendedAttributes"] as? [String:String]
    }

    @available(iOS 16.0, *)
    var typeAndCreator: (type: String, creator: String)? {
        guard let t = info["typeAndCreator"] as? [String:String],
              let type = t["type"], let creator = t["creator"]
        else { return nil }
        return (type, creator)
    }
}

extension APIClient {
    /// Updates *any* changed field on the server, per the File Provider spec.
    func updateItem(itemId: NSFileProviderItemIdentifier,
                    changedFields: NSFileProviderItemFields,
                    item:          NSFileProviderItem,
                    newContents:   URL?,
                    completion: @escaping (Result<[String:Any], Error>) -> Void)
    {
        let url = URLs.update(itemId: itemId)
        var body = [String:Any]()

        // Filename change
        if changedFields.contains(.filename) {
            body["name"] = item.filename
        }
        // Move / reparent
        if changedFields.contains(.parentItemIdentifier) {
            let pid = item.parentItemIdentifier.rawValue.base64URLEncoded
            body["parentId"] = pid
        }
        // Timestamps
        if changedFields.contains(.lastUsedDate), let d = item.lastUsedDate, let time = d?.timeIntervalSince1970 {
            body["lastUsedDate"] = time
        }
        if changedFields.contains(.creationDate), let d = item.creationDate, let time = d?.timeIntervalSince1970 {
            body["createdAt"] = time
        }
        if changedFields.contains(.contentModificationDate),
           let d = item.contentModificationDate, let time = d?.timeIntervalSince1970  {
            body["contentModificationDate"] = time
        }
        // Tagging & favorites
        if changedFields.contains(.tagData), let data = item.tagData, let data1 = data?.base64EncodedString() {
            body["tagData"] = data1
        }
        if changedFields.contains(.favoriteRank), let rank = item.favoriteRank {
            body["favoriteRank"] = rank
        }
        // File system flags (e.g. hidden/excluded)
        if changedFields.contains(.fileSystemFlags),
           let flags = item.fileSystemFlags {
            body["fileSystemFlags"] = flags
        }
        // Extended attributes
        if changedFields.contains(.extendedAttributes),
           let attrs = item.extendedAttributes {
            body["extendedAttributes"] = attrs
        }
        // Type & Creator (iOS 16+)
        if #available(iOS 16.0, *),
           changedFields.contains(.typeAndCreator),
           let tc = item.typeAndCreator {
            body["typeAndCreator"] = ["type": tc.type, "creator": tc.creator]
        }

        // If there’s new contents on disk, do a separate upload call after
        // the metadata sync. We’ll ignore it here.
        let req = makeRequest(to: url,
                              method: "POST",
                              body: try? JSONSerialization.data(withJSONObject: body),
                              contentType: "application/json")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            // 1) Network error
            if let err = err {
                return completion(.failure(err))
            }
            // 2) Must have data
            guard let data = data else {
                let e = NSError(
                    domain: "APIClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"]
                )
                return completion(.failure(e))
            }
            // 3) Parse JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else {
                let e = NSError(
                    domain: "APIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
                )
                return completion(.failure(e))
            }
            // 4) Validate “id” field
            guard let idString = json["id"] as? String, !idString.isEmpty else {
                let e = NSError(
                    domain: "APIClient",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid 'id' in metadata"]
                )
                return completion(.failure(e))
            }
            // 5) All good
            completion(.success(json))
        }
        .resume()
    }
}
 //
//  AuthManager.swift
//  TDS Cloud
//
//  Created by Thomas Dye on 20/04/2025.
//

import Foundation
import FileProvider


// 3) Simple Auth manager
class AuthManager {
    static let shared = AuthManager()
    var AuthToken:Auth_token_Saveing
    private init() {
        AuthToken = Auth_token_Saveing(suitname: "group.net.thomasdye.Auth_Creds", BundleID: "net.thomasdye.TDS-Cloud")
        
    }
    

    /// Replace with your real token‐fetching logic
    var bearerToken: String {
        // e.g. read from Keychain or your app’s user session
        return AuthToken.getToken()?.Token ?? ""
    }
}
//
//  FileProviderEnumerator.swift
//  TDS Cloud file Provider
//
//  Created by Thomas Dye on 20/04/2025.
//

import FileProvider

// MARK: –– The Enumerator

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
    }
    
    func invalidate() {
        // cancel any network calls if needed
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage)
    {
        
//        if observer == .tra {
//            let error = NSFileProviderError(.noSuchItem)
//            completionHandler(nil, error)
//            return Progress()
//        }
        
        APIClient.shared.listItems(parentId: enumeratedItemIdentifier) { result in
            switch result {
            case .failure(let err):
                observer.finishEnumeratingWithError(err)
            case .success(let array):
                let items = array.map { FileProviderItem(from: $0) }
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor)
    {
        // You’d call your “/changes?since=…” endpoint here; for now we’re a no‑op:
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Return the last anchor you persisted
        completionHandler(nil)
    }
}
//
//  FileProviderExtension.swift
//  TDS Cloud file Provider
//
//  Created by Thomas Dye on 20/04/2025.
//

import FileProvider
import UniformTypeIdentifiers

// MARK: –– Your FileProviderExtension

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    
    let domain: NSFileProviderDomain
    var manager:   NSFileProviderManager
    
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.manager  = NSFileProviderManager(for: domain)!
        super.init()
        
    }
    
    func invalidate() {
        // Clean up any in‑flight network calls if you like
    }
    
    // Resolve an identifier → metadata
    func item(for identifier: NSFileProviderItemIdentifier,
              request:    NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void)
              -> Progress
    {
        
    
//        if identifier == .trashContainer {
//            let error = NSFileProviderError(.noSuchItem)
//            completionHandler(nil, error)
//            return Progress()
//        }
        
        APIClient.shared.getMetadata(itemId: identifier) { result in
            switch result {
            case .failure(let err):
                completionHandler(nil, err)
            case .success(let dict):
                if dict["id"] as? String == nil {
                    completionHandler(nil, nil)
                    return
                }
                let item = FileProviderItem(from: dict)
                completionHandler(item, nil)
            }
        }
        return Progress()
    }
    
    // Download the bytes, write to a local URL, then hand it back
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version:          NSFileProviderItemVersion?,
                       request:          NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void)
                       -> Progress
    {
        let localURL = FileManager.default.temporaryDirectory
                       .appendingPathComponent(itemIdentifier.rawValue)

        // 1) Download the raw bytes
        APIClient.shared.downloadContent(itemId: itemIdentifier, to: localURL) { downloadResult in
            switch downloadResult {
            case .failure(let downloadError):
                completionHandler(nil, nil, downloadError)

            case .success:
                // 2) Now fetch the metadata so we can create a FileProviderItem(from: dict)
                APIClient.shared.getMetadata(itemId: itemIdentifier) { metaResult in
                    switch metaResult {
                    case .failure(let metaError):
                        // At least hand back the file on disk, even if metadata failed
                        completionHandler(localURL, nil, metaError)

                    case .success(let dict):
                        let item = FileProviderItem(from: dict)
                        completionHandler(localURL, item, nil)
                    }
                }
            }
        }

        return Progress()
    }

    
    // Called when Files.app creates a new file or folder on disk
    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields:    NSFileProviderItemFields,
                    contents:  URL?,
                    options:   NSFileProviderCreateItemOptions = [],
                    request:   NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void)
                    -> Progress
    {
        // 1) Create folder or empty file
        APIClient.shared.createItem(
            parentId: itemTemplate.parentItemIdentifier,
            name:     itemTemplate.filename,
            type:     fields.contains(.contents) ? "file" : "folder"
        ) { result in
            switch result {
            case .failure(let err):
                completionHandler(nil, [], false, err)
            case .success(let dict):
                let newItemId = NSFileProviderItemIdentifier(dict["id"] as! String)
                let newItem   = FileProviderItem(from: dict)
                
                // 2) If there's new contents on disk, upload them
                if let contentsURL = contents {
                    APIClient.shared.uploadContent(itemId: newItemId, fileURL: contentsURL) { _ in
                        // ignore result for now
                        completionHandler(newItem, fields, false, nil)
                    }
                } else {
                    completionHandler(newItem, [], false, nil)
                }
            }
        }
        return Progress()
    }
    
    // Called on renames/moves or content edits
    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void)
                    -> Progress
    {
//        guard let fpItem = item as? FileProviderItem else {
//            completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: -1))
//            return Progress()
//        }

        APIClient.shared.updateItem(itemId: item.itemIdentifier,
                                    changedFields: changedFields,
                                    item:          item,
                                    newContents:   newContents) { result in
            switch result {
            case .failure(let err):
                completionHandler(nil, [], false, err)
            case .success(let dict):
                if dict["id"] as? String == nil {
                    completionHandler(nil, [], false, nil)
                    return
                }
                let updated = FileProviderItem(from: dict)
                completionHandler(updated, changedFields, false, nil)
            }
        }

        return Progress()
    }

    
    // Called when Files.app trashes/deletes
    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion: NSFileProviderItemVersion,
                    options:     NSFileProviderDeleteItemOptions = [],
                    request:     NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void)
                    -> Progress
    {
        APIClient.shared.deleteItem(itemId: identifier) { result in
            switch result {
            case .failure(let err):
                completionHandler(err)
            case .success:
                completionHandler(nil)
            }
        }
        return Progress()
    }
    
    // Folder enumerator
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request:  NSFileProviderRequest) throws -> NSFileProviderEnumerator
    {
//        if containerItemIdentifier == .trashContainer  {
//                let error = NSFileProviderError(.noSuchItem)
//                throw error
//        }
        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
    }
}



//
//  FileProviderItem.swift
//  TDS Cloud file Provider
//
//  Created by Thomas Dye on 20/04/2025.
//

import FileProvider
import UniformTypeIdentifiers

/// A File Provider item that decodes URL-encoded names and infers contentType from file extension.
class FileProviderItem: NSObject, NSFileProviderItem {
    let id: NSFileProviderItemIdentifier
    let info: [String: Any]

    init(from dict: [String: Any]) {
        self.id = NSFileProviderItemIdentifier(dict["id"] as! String)
        self.info = dict
        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier { id }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let p = info["parentId"] as? String {
            return NSFileProviderItemIdentifier(p)
        }
        return .rootContainer
    }

    /// Decode URL-encoded filename and default to the identifier if missing
    var filename: String {
        let raw = info["name"] as? String ?? id.rawValue
        return raw.removingPercentEncoding ?? raw
    }

    /// Versioning from your backend
    var itemVersion: NSFileProviderItemVersion {
        let cv = (info["contentVersion"] as? String)?.data(using: .utf8) ?? Data()
        let mv = (info["metadataVersion"] as? String)?.data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(contentVersion: cv, metadataVersion: mv)
    }

    
    var isTrashed: Bool {
        let t = info["Trash"] as? Bool ?? false
        return t
    }
    /// Allowed operations
    var capabilities: NSFileProviderItemCapabilities {
        // common to both files & folders:
        var caps: NSFileProviderItemCapabilities = [
            .allowsReading,
            .allowsRenaming,
            .allowsTrashing,
            .allowsDeleting
        ]

        let type = info["type"] as? String

        if type == "folder" {
            // Allow Files.app to create/move items into this folder:
            caps.insert(.allowsAddingSubItems)
            caps.insert(.allowsReparenting)
        } else if type == "file" {
            // Allow editing a file’s contents:
            caps.insert(.allowsWriting)
            // Allow dragging a file into another folder:
            caps.insert(.allowsReparenting)
        }

        return caps
    }

    /// Infer contentType from file extension
    var contentType: UTType {
        if (info["type"] as? String) == "folder" {
            return .folder
        }
        let name = filename
        if let ext = name.split(separator: ".").last.map(String.init),
           let ut = UTType(filenameExtension: ext) {
            return ut
        }
        // fallback to generic data
        return .data
    }
}
