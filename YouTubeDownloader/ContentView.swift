import SwiftUI
import AVKit

struct VideoInfo: Identifiable, Codable {
    let id: UUID = UUID()
    let title: String
    let uploader: String
    let channel: String
    let views: Int
    let filePath: String
}

class VideoDownloader: ObservableObject {
    @Published var videos: [VideoInfo] = []
    @Published var videoURL: String = ""
    
    let savePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/YoutubeDownloads")
    
    init() {
        loadVideos()
    }
    
    func downloadVideo() {
        guard !videoURL.isEmpty else { return }
        let url = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let savePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/YoutubeDownloads")
        let command: String = """
        export PATH="/opt/homebrew/bin:$PATH"; \
        yt-dlp -f best --merge-output-format mp4 \
        --write-info-json -o "\(savePath.path)/%(title)s.%(ext)s" "\(url)"; \
        ffmpeg -i "\(savePath.path)/%(title)s.mp4" -vcodec h264 -acodec aac -strict -2 -movflags faststart "\(savePath.path)/%(title)s-qt.mp4"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()  // Ensure the process finishes

            let jsonPath = savePath.appendingPathComponent("video_info.json")
            if let jsonData = try? Data(contentsOf: jsonPath),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                let title = json["title"] as? String ?? "Unknown"
                let uploader = json["uploader"] as? String ?? "Unknown"
                let channel = json["uploader_id"] as? String ?? "Unknown"
                let views = json["view_count"] as? Int ?? 0
                let filePath = savePath.appendingPathComponent("\(title).mp4").path
                
                let video = VideoInfo(title: title, uploader: uploader, channel: channel, views: views, filePath: filePath)
                DispatchQueue.main.async {
                    self.videos.append(video)
                    self.saveVideos()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Wait for file to be written
                self.loadVideos()
            }
        } catch {
            print("Error downloading video: \(error)")
        }
    }
    
    func loadVideos() {
        videos.removeAll() // Clear the list before loading new data
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: savePath, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        
        for jsonFile in jsonFiles {
            do {
                let data = try Data(contentsOf: jsonFile)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let title = json["title"] as? String ?? "Unknown"
                    let uploader = json["uploader"] as? String ?? "Unknown"
                    let channel = json["uploader_id"] as? String ?? "Unknown"
                    let views = json["view_count"] as? Int ?? 0
                    let videoPath = savePath.appendingPathComponent("\(title).mp4").path
                    
                    let video = VideoInfo(title: title, uploader: uploader, channel: channel, views: views, filePath: videoPath)
                    videos.append(video)
                }
            } catch {
                print("❌ Error loading video info from \(jsonFile.lastPathComponent): \(error)")
            }
        }
        
        // Save to a single JSON file for later use
        saveVideos()
    }
    
    func saveVideos() {
        let jsonPath = savePath.appendingPathComponent("video_list.json")
        if let encoded = try? JSONEncoder().encode(videos) {
            try? encoded.write(to: jsonPath)
        }
    }
    
    func removeVideoInfo(at offsets: IndexSet) {
        videos.remove(atOffsets: offsets)
        saveVideos()
    }
}

struct ContentView: View {
    @StateObject private var downloader = VideoDownloader()
    
    var body: some View {
        VStack {
            TextField("Enter YouTube URL", text: $downloader.videoURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Download Video") {
                downloader.downloadVideo()
            }
            .padding()
            
            List {
                ForEach(downloader.videos) { video in
                    VStack(alignment: .leading) {
                        Text(video.title).font(.headline)
                        Text("By: \(video.uploader) (\(video.channel))").font(.subheadline)
                        Text("Views: \(video.views)")
                        Button("Open in QuickTime") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: video.filePath))
                        }
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: downloader.removeVideoInfo)
            }
        }
        .padding()
    }
}
