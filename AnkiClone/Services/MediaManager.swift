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
        let cleanName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        
        let fileURL = mediaDirectoryURL.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        // Check URL-encoded or decoded variants
        if let decoded = cleanName.removingPercentEncoding {
            let altURL = mediaDirectoryURL.appendingPathComponent(decoded)
            if FileManager.default.fileExists(atPath: altURL.path) {
                return altURL
            }
        }
        
        return nil
    }
    
    /// Checks if a media asset exists in local storage
    func mediaExists(for filename: String) -> Bool {
        return getMediaURL(for: filename) != nil
    }
    
    /// Saves media data under a specific filename
    func saveMedia(data: Data, named filename: String) throws {
        let cleanName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        let destinationURL = mediaDirectoryURL.appendingPathComponent(cleanName)
        try data.write(to: destinationURL, options: .atomic)
    }
    
    /// Copies a file into the media directory
    func copyMediaFile(from sourceURL: URL, named destinationName: String) throws {
        let cleanName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        let destinationURL = mediaDirectoryURL.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
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
