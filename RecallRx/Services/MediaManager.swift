import Foundation
import SwiftUI
import AVFoundation

/// Media Storage & Audio Playback Manager for RecallRx
/// Manages local persistent flashcard media (images, diagrams, audio recordings)
/// extracted from .apkg archives or user imports.
final class MediaManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MediaManager()
    
    @Published var isPlayingAudio: Bool = false
    @Published var currentPlayingAudioName: String? = nil
    
    private var audioPlayer: AVAudioPlayer?
    
    // Directory where media files are stored: Library/Application Support/RecallRx/Media/
    private let mediaDirectoryURL: URL

    /// Read-only access for portable backups and transactional imports.
    var directoryURL: URL { mediaDirectoryURL }

    enum MediaError: LocalizedError {
        case invalidFilename
        case symbolicLink

        var errorDescription: String? {
            switch self {
            case .invalidFilename: return "Media filenames must be safe relative paths."
            case .symbolicLink: return "Symbolic links cannot be used for card media."
            }
        }
    }

    /// An isolated directory can be supplied by tests without touching a user's media.
    init(mediaDirectoryURL: URL) {
        self.mediaDirectoryURL = mediaDirectoryURL
        super.init()
        try? FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
    }

    static func validatedRelativePath(_ filename: String) throws -> String {
        guard !filename.isEmpty, !filename.hasPrefix("/"), !filename.contains("\\"), !filename.contains("\0") else {
            throw MediaError.invalidFilename
        }
        let components = filename.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MediaError.invalidFilename
        }
        return filename
    }

    static func mediaURL(for filename: String, in directory: URL) throws -> URL {
        let path = try validatedRelativePath(filename)
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        var current = base
        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component))
            if let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                throw MediaError.symbolicLink
            }
        }
        guard current.standardizedFileURL.path.hasPrefix(base.path + "/") else {
            throw MediaError.invalidFilename
        }
        return current
    }
    
    private override init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recallRxURL = appSupportURL.appendingPathComponent("RecallRx", isDirectory: true)
        self.mediaDirectoryURL = recallRxURL.appendingPathComponent("Media", isDirectory: true)
        
        super.init()
        
        // Ensure directories exist
        try? fileManager.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    // MARK: - Media Access
    
    /// Returns the file URL for a given media name if it exists on disk
    func getMediaURL(for filename: String) -> URL? {
        let candidates = [filename, filename.removingPercentEncoding].compactMap { $0 }
        for candidate in candidates {
            guard let url = try? Self.mediaURL(for: candidate, in: mediaDirectoryURL),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            return url
        }
        return nil
    }

    /// Checks if a media asset exists in local storage
    func mediaExists(for filename: String) -> Bool {
        return getMediaURL(for: filename) != nil
    }
    
    /// Saves media data under a specific filename
    func saveMedia(data: Data, named filename: String) throws {
        let destination = try Self.mediaURL(for: filename, in: mediaDirectoryURL)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    /// Read first, then replace atomically, so a failed copy cannot delete an existing image.
    func copyMediaFile(from sourceURL: URL, named destinationName: String) throws {
        let data = try Data(contentsOf: sourceURL)
        try saveMedia(data: data, named: destinationName)
    }

    /// Returns total media storage size in bytes
    func totalMediaSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: mediaDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Returns total number of media files saved
    func mediaFileCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: mediaDirectoryURL.path)) ?? []
        return files.count
    }
    
    /// Deletes a specific media file
    func deleteMedia(named filename: String) {
        if let url = getMediaURL(for: filename) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Deletes all cached media
    func clearAllMedia() {
        let files = (try? FileManager.default.contentsOfDirectory(at: mediaDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    // MARK: - Audio Playback
    
    /// Plays an audio file from the media folder or bundle
    func playAudio(named filename: String) {
        stopAudio()
        
        guard let url = getMediaURL(for: filename) else {
            // Check bundle as fallback
            let nameWithoutExt = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            if let bundleURL = Bundle.main.url(forResource: nameWithoutExt, withExtension: ext) {
                startPlaying(url: bundleURL, name: filename)
            }
            return
        }
        
        startPlaying(url: url, name: filename)
    }
    
    private func startPlaying(url: URL, name: String) {
        do {
            #if canImport(AVFoundation)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            isPlayingAudio = true
            currentPlayingAudioName = name
        } catch {
            print("MediaManager audio playback failed: \(error.localizedDescription)")
            stopAudio()
        }
    }
    
    /// Stops any ongoing audio playback
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        currentPlayingAudioName = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopAudio()
        }
    }
}
