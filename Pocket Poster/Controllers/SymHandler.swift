//
//  SymHandler.swift
//  EmPoster
//
//  Created by lemin on 5/31/25.
//

import Foundation

class SymHandler {
    // MARK: URL Getter Operations
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    static func getPosterBoardHashURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent("NuggetPosterBoardHash")
    }
    static func getCarPlayHashURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent("NuggetCarPlayWallpaperHash")
    }
    
    private static func getSymlinkURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent(".Trash", conformingTo: .symbolicLink)
    }
    
    /// Prefer bad_query (iOS 26/27 sandbox escape); fall back to .Trash symlink exploit.
    static var prefersBadQuery: Bool {
        BadQuery.isAvailable
    }
    
    // MARK: Symlink Creation (legacy exploit for older iOS)
    static func createSymlink(to path: String) throws -> URL {
        // returns the url of the symlink
        let symURL = getSymlinkURL()
        cleanup()
        
        // create the symlink to the hashed app folder
        try FileManager.default.createSymbolicLink(at: symURL, withDestinationURL: URL(fileURLWithPath: path, isDirectory: true))
        
        return symURL
    }
    
    static func createAppSymlink(for appHash: String) throws -> URL {
        return try createSymlink(to: "/var/mobile/Containers/Data/Application/\(appHash)")
    }
    
    static func getExtensionVersion() -> String {
        if #available(iOS 17.0, *) {
            return "61"
        }
        return "59"
    }
    
    static func createDescriptorsSymlink(appHash: String, ext: String) throws -> URL {
        // create a symlink directly to the descriptors
        let extVer = SymHandler.getExtensionVersion()
        print("linking to \(appHash)/Library/Application Support/PRBPosterExtensionDataStore/\(extVer)/Extensions/\(ext)/descriptors")
        return try createAppSymlink(for: "\(appHash)/Library/Application Support/PRBPosterExtensionDataStore/\(extVer)/Extensions/\(ext)/descriptors")
    }
    
    // MARK: Direct write via bad_query
    
    /// Copy descriptor folders into PosterBoard descriptors using sandbox escape.
    static func writeDescriptorsViaBadQuery(appHash: String, ext: String, descriptorFolders: [URL]) throws {
        let destPath = BadQuery.descriptorsPath(appHash: appHash, ext: ext)
        print("bad_query writing to \(destPath)")
        
        // Ensure descriptors directory exists (open parent chain if needed)
        try BadQuery.ensureDirectory(at: destPath)
        
        let handle = try BadQuery.consume(path: destPath, create: true)
        defer { handle.release() }
        
        let fm = FileManager.default
        for descr in descriptorFolders {
            guard descr.lastPathComponent != "__MACOSX" else { continue }
            let destName = UUID().uuidString
            let destURL = URL(fileURLWithPath: destPath).appendingPathComponent(destName)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: descr, to: destURL)
        }
    }
    
    /// Copy files into an absolute directory under an app container via bad_query.
    static func writeFilesViaBadQuery(toDirectory destPath: String, files: [URL]) throws {
        try BadQuery.ensureDirectory(at: destPath)
        let handle = try BadQuery.consume(path: destPath, create: true)
        defer { handle.release() }
        
        let fm = FileManager.default
        for file in files {
            let destURL = URL(fileURLWithPath: destPath).appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: file, to: destURL)
        }
    }
    
    static func cleanup() {
        // remove the symlink if it exists
        let symURL = getSymlinkURL()
        // remove existing symlink
        try? FileManager.default.removeItem(at: symURL)
    }
}
