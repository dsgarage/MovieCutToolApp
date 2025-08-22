import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var downloadURL: String = ""
    @State private var isProcessing = false
    @State private var isDownloading = false
    @State private var outputLog = ""
    @State private var silenceThreshold: Double = -30
    @State private var minSilenceDuration: Double = 0.3
    @State private var selectedTab = 0
    @State private var downloadCommentsEnabled = true
    
    var body: some View {
        HSplitView {
            // 左側：コントロールパネル
            VStack(alignment: .leading, spacing: 20) {
                Text("MovieCutTool")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // タブビュー
                TabView(selection: $selectedTab) {
                    // ローカルファイルタブ
                    VStack(alignment: .leading) {
                        GroupBox("入力ビデオ") {
                            VStack(alignment: .leading) {
                                if let url = videoURL {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button("ビデオを選択...") {
                                    selectVideo()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .tabItem {
                        Label("ローカルファイル", systemImage: "folder")
                    }
                    .tag(0)
                    
                    // ダウンロードタブ
                    VStack(alignment: .leading) {
                        GroupBox("動画ダウンロード (yt-dlp)") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("動画URL", text: $downloadURL)
                                    .textFieldStyle(.roundedBorder)
                                
                                Toggle("コメントも取得", isOn: $downloadCommentsEnabled)
                                    .padding(.vertical, 5)
                                
                                Button(action: downloadVideo) {
                                    Label("ダウンロード", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(downloadURL.isEmpty || isDownloading)
                                
                                if isDownloading {
                                    ProgressView("ダウンロード中...")
                                        .progressViewStyle(.linear)
                                }
                            }
                        }
                    }
                    .tabItem {
                        Label("ダウンロード", systemImage: "arrow.down.circle")
                    }
                    .tag(1)
                }
                
                // パラメータ設定
                GroupBox("無音検出設定") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ノイズレベル (dB):")
                            Slider(value: $silenceThreshold, in: -60...(-20))
                            Text(String(format: "%.0f", silenceThreshold))
                                .monospacedDigit()
                        }
                        
                        HStack {
                            Text("最小無音時間 (秒):")
                            Slider(value: $minSilenceDuration, in: 0.1...2.0)
                            Text(String(format: "%.1f", minSilenceDuration))
                                .monospacedDigit()
                        }
                    }
                }
                
                // 処理ボタン
                Button(action: processVideo) {
                    Label("無音カット実行", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(videoURL == nil || isProcessing)
                
                // Whisper文字起こしボタン
                Button(action: transcribeWithWhisper) {
                    Label("文字起こし (Whisper)", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(videoURL == nil || isProcessing)
                
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 300)
            
            // 右側：ログ出力
            VStack(alignment: .leading) {
                HStack {
                    Text("処理ログ")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(outputLog, forType: .string)
                    }) {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
                
                ScrollView {
                    Text(outputLog)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
    
    func selectVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            videoURL = panel.url
            outputLog += "選択されたファイル: \(panel.url?.path ?? "")\n"
        }
    }
    
    func processVideo() {
        guard let inputURL = videoURL else { return }
        
        isProcessing = true
        outputLog += "\n処理を開始します...\n"
        
        Task {
            do {
                // 出力ファイル名を生成
                let outputURL = inputURL.deletingPathExtension().appendingPathExtension("cut").appendingPathExtension("mp4")
                
                // Pythonスクリプトを実行
                let result = try await runPythonScript(
                    input: inputURL.path,
                    output: outputURL.path,
                    threshold: silenceThreshold,
                    duration: minSilenceDuration
                )
                
                await MainActor.run {
                    outputLog += result
                    outputLog += "\n処理が完了しました！\n"
                    outputLog += "出力ファイル: \(outputURL.path)\n"
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    outputLog += "エラー: \(error.localizedDescription)\n"
                    isProcessing = false
                }
            }
        }
    }
    
    func runPythonScript(input: String, output: String, threshold: Double, duration: Double) async throws -> String {
        let process = Process()
        // 直接pyenvのPythonパスを使用
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let pythonPath = "\(homeDir)/.pyenv/shims/python3"
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-m", "vedit.jetcut",
            "-i", input,
            "-o", output,
            "--noise", String(format: "%.0f", threshold),
            "--min-dur", String(format: "%.1f", duration)
        ]
        
        // PYTHONPATHを設定
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = "\(homeDir)/Documents/dsgarageScript/MovieCutTool/src"
        process.environment = environment
        
        // 作業ディレクトリを設定
        process.currentDirectoryURL = URL(fileURLWithPath: "\(homeDir)/Documents/dsgarageScript/MovieCutTool")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func downloadVideo() {
        isDownloading = true
        outputLog += "\n動画のダウンロードを開始します...\n"
        outputLog += "URL: \(downloadURL)\n"
        
        Task {
            do {
                // ダウンロード先ディレクトリ
                let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let baseOutputPath = downloadDir.appendingPathComponent("MovieCutTool_Downloads", isDirectory: true)
                
                // 動画IDを取得してフォルダ名にする
                let videoId = extractVideoId(from: downloadURL) ?? "video_\(Date().timeIntervalSince1970)"
                let outputPath = baseOutputPath.appendingPathComponent(videoId, isDirectory: true)
                
                // ディレクトリ作成
                try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
                
                // yt-dlpを実行
                try await runYtDlp(url: downloadURL, outputDir: outputPath.path)
                
                // ダウンロードしたファイルを検索
                var downloadedFile: URL?
                if let file = findLatestVideoFile(in: outputPath) {
                    downloadedFile = file
                }
                
                // コメントも取得する場合
                if downloadCommentsEnabled && downloadedFile != nil {
                    await MainActor.run {
                        outputLog += "\nコメントを取得中...\n"
                    }
                    do {
                        try await runChatDownloader(url: downloadURL, outputDir: outputPath.path)
                    } catch {
                        await MainActor.run {
                            outputLog += "コメント取得エラー: \(error.localizedDescription)\n"
                        }
                    }
                }
                
                await MainActor.run {
                    
                    if let downloadedFile = downloadedFile {
                        videoURL = downloadedFile
                        outputLog += "\nダウンロード完了: \(downloadedFile.lastPathComponent)\n"
                        
                        // コメント取得の結果は既にリアルタイムで表示されているのでここでは追加しない
                        
                        selectedTab = 0 // ローカルファイルタブに切り替え
                    } else {
                        outputLog += "\nエラー: ダウンロードしたファイルが見つかりません\n"
                        outputLog += "ダウンロードフォルダ: \(outputPath.path)\n"
                        // フォルダ内のファイルをリスト
                        if let files = try? FileManager.default.contentsOfDirectory(at: outputPath, includingPropertiesForKeys: nil) {
                            outputLog += "フォルダ内のファイル:\n"
                            for file in files {
                                outputLog += "  - \(file.lastPathComponent)\n"
                            }
                        }
                    }
                    
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    outputLog += "ダウンロードエラー: \(error.localizedDescription)\n"
                    isDownloading = false
                }
            }
        }
    }
    
    func runYtDlp(url: String, outputDir: String) async throws -> String {
        let process = Process()
        
        // Homebrewのyt-dlpを直接使用
        let ytDlpPath = findExecutable(name: "yt-dlp") ?? "/opt/homebrew/bin/yt-dlp"
        
        // デバッグ: 使用するyt-dlpパスをログに出力
        await MainActor.run {
            outputLog += "使用するyt-dlp: \(ytDlpPath)\n"
        }
        
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        
        process.arguments = [
            url,
            "-f", "best[height<=720]/best", // 720p以下の最高品質
            "-o", "\(outputDir)/%(title)s.%(ext)s",
            "--no-playlist", // プレイリストの場合は最初の動画のみ
            "--merge-output-format", "mp4", // MP4形式で保存
            "--live-from-start", // ライブ配信を最初から取得
            "--progress" // プログレス表示を有効化
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // リアルタイムでログを更新
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                    // 自動スクロール（最後の行を表示）
                }
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                }
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        // ハンドラをクリーンアップ
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        
        return ""
    }
    
    func findExecutable(name: String) -> String? {
        // pyenvとHomebrewのパスも含める
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(homeDir)/.pyenv/shims",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin"
        ]
        for path in paths {
            let fullPath = "\(path)/\(name)"
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }
    
    func findLatestVideoFile(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let videoExtensions = ["mp4", "mkv", "webm", "mov", "avi", "m4v", "flv"]
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, 
                                                           includingPropertiesForKeys: [.creationDateKey],
                                                           options: .skipsHiddenFiles)
            
            let videoFiles = files.filter { url in
                videoExtensions.contains(url.pathExtension.lowercased())
            }
            
            // 最新のファイルを返す
            return videoFiles.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }.first
            
        } catch {
            return nil
        }
    }
    
    func downloadComments() {
        guard !downloadURL.isEmpty else { return }
        
        isProcessing = true
        outputLog += "\nコメントのダウンロードを開始します...\n"
        outputLog += "URL: \(downloadURL)\n"
        
        Task {
            do {
                // 出力ディレクトリ
                let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let outputPath = downloadDir.appendingPathComponent("MovieCutTool_Downloads", isDirectory: true)
                
                // ディレクトリ作成
                try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
                
                // chat-downloaderを実行
                let result = try await runChatDownloader(url: downloadURL, outputDir: outputPath.path)
                
                await MainActor.run {
                    outputLog += result
                    outputLog += "\nコメントのダウンロードが完了しました\n"
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    outputLog += "コメント取得エラー: \(error.localizedDescription)\n"
                    isProcessing = false
                }
            }
        }
    }
    
    func runChatDownloader(url: String, outputDir: String) async throws -> String {
        let process = Process()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let pythonPath = "\(homeDir)/.pyenv/shims/python3"
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        
        // まずJSONファイルとして保存
        let jsonFile = "\(outputDir)/comments_raw.json"
        
        process.arguments = [
            "-m", "chat_downloader",
            url,
            "-o", jsonFile
        ]
        
        // PYTHONPATHを設定
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = "\(homeDir)/Documents/dsgarageScript/MovieCutTool/third_party/chat-downloader"
        process.environment = environment
        
        process.currentDirectoryURL = URL(fileURLWithPath: "\(homeDir)/Documents/dsgarageScript/MovieCutTool")
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // リアルタイムでログを更新
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                }
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                }
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        // ハンドラをクリーンアップ
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        
        // JSONを解析してタイムスタンプ付きコメントのみをCSVに変換
        if process.terminationStatus == 0 {
            await MainActor.run {
                outputLog += "コメントをCSV形式に変換中...\n"
            }
            try await convertCommentsToCSV(jsonFile: jsonFile, outputDir: outputDir)
            await MainActor.run {
                outputLog += "コメント保存完了: \(outputDir)/comments.csv\n"
            }
        }
        
        return ""
    }
    
    func convertCommentsToCSV(jsonFile: String, outputDir: String) async throws {
        // JSONファイルを読み込み
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonFile))
        
        // JSONをパース
        if let jsonArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
            var csvContent = "timestamp,author,message\n"
            var commentCount = 0
            
            for comment in jsonArray {
                // time_in_seconds または timestamp_usec を確認
                var timestamp: TimeInterval? = nil
                
                if let timeInSeconds = comment["time_in_seconds"] as? Double {
                    timestamp = timeInSeconds
                } else if let timestampUsec = comment["timestamp_usec"] as? String,
                          let usec = Double(timestampUsec) {
                    timestamp = usec / 1000000.0 // マイクロ秒を秒に変換
                }
                
                // タイムスタンプがあるコメントのみ処理
                if let timestamp = timestamp,
                   let authorDict = comment["author"] as? [String: Any],
                   let authorName = authorDict["name"] as? String {
                    
                    // メッセージの取得（文字列または配列の場合がある）
                    var messageText = ""
                    if let message = comment["message"] as? String {
                        messageText = message
                    } else if let messageArray = comment["message_fragments"] as? [[String: Any]] {
                        // message_fragmentsから文字列を結合
                        messageText = messageArray.compactMap { fragment in
                            fragment["text"] as? String
                        }.joined()
                    }
                    
                    // 空のメッセージはスキップ
                    if messageText.isEmpty {
                        continue
                    }
                    
                    // タイムスタンプを時:分:秒形式に変換
                    let hours = Int(timestamp) / 3600
                    let minutes = (Int(timestamp) % 3600) / 60
                    let seconds = Int(timestamp) % 60
                    let timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                    
                    // CSVエスケープ処理
                    let escapedAuthor = escapeCSV(authorName)
                    let escapedMessage = escapeCSV(messageText)
                    
                    csvContent += "\(timeString),\(escapedAuthor),\(escapedMessage)\n"
                    commentCount += 1
                }
            }
            
            // CSVファイルとして保存
            let csvFile = "\(outputDir)/comments.csv"
            try csvContent.write(toFile: csvFile, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                outputLog += "タイムスタンプ付きコメント数: \(commentCount)\n"
            }
        }
    }
    
    func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }
    
    func transcribeWithWhisper() {
        guard let inputURL = videoURL else { return }
        
        isProcessing = true
        outputLog += "\n音声認識を開始します...\n"
        
        Task {
            do {
                // 出力ファイル名を生成（同じフォルダにSRTファイルとして保存）
                let outputURL = inputURL.deletingPathExtension().appendingPathExtension("srt")
                
                // Whisperを実行
                try await runWhisper(input: inputURL.path, output: outputURL.path)
                
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    outputLog += "音声認識エラー: \(error.localizedDescription)\n"
                    isProcessing = false
                }
            }
        }
    }
    
    func runWhisper(input: String, output: String) async throws -> String {
        let process = Process()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        // whisper.cppのパス
        let whisperPath = "\(homeDir)/Documents/dsgarageScript/MovieCutTool/third_party/whisper.cpp/build/bin/whisper-cli"
        let modelPath = "\(homeDir)/Documents/dsgarageScript/MovieCutTool/third_party/whisper.cpp/models/ggml-base.bin"
        
        // パスの存在確認
        await MainActor.run {
            outputLog += "\nWhisperパス確認中...\n"
            outputLog += "実行ファイル: \(whisperPath)\n"
            outputLog += "モデルファイル: \(modelPath)\n"
        }
        
        if !FileManager.default.fileExists(atPath: whisperPath) {
            throw NSError(domain: "WhisperError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper実行ファイルが見つかりません: \(whisperPath)"])
        }
        
        if !FileManager.default.fileExists(atPath: modelPath) {
            throw NSError(domain: "WhisperError", code: 2, userInfo: [NSLocalizedDescriptionKey: "モデルファイルが見つかりません: \(modelPath)"])
        }
        
        // 出力ディレクトリとベース名を準備
        let outputURL = URL(fileURLWithPath: output)
        let outputDir = outputURL.deletingLastPathComponent().path
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath,      // モデルファイル
            "-l", "ja",           // 日本語
            "-f", input,          // 入力ファイル
            "-osrt",              // SRT形式で出力
            "-of", "\(outputDir)/\(baseName)",  // 出力ファイルのベース名
            "-pp"                 // プログレス表示
        ]
        
        await MainActor.run {
            outputLog += "\nWhisperコマンド実行中...\n"
            outputLog += "入力: \(input)\n"
            outputLog += "出力: \(outputDir)/\(baseName).srt\n"
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // リアルタイムでログを更新
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                }
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self.outputLog += output
                }
            }
        }
        
        try process.run()
        
        // プロセスの終了を待つ
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        
        // ハンドラをクリーンアップ
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        
        if process.terminationStatus == 0 {
            // 出力ファイルの存在確認
            let srtPath = "\(outputDir)/\(baseName).srt"
            if FileManager.default.fileExists(atPath: srtPath) {
                await MainActor.run {
                    outputLog += "\n✅ SRTファイルが生成されました: \(srtPath)\n"
                }
                return ""
            } else {
                throw NSError(domain: "WhisperError", code: 3, userInfo: [NSLocalizedDescriptionKey: "SRTファイルが生成されませんでした"])
            }
        } else {
            throw NSError(domain: "WhisperError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Whisperプロセスがエラーで終了しました (code: \(process.terminationStatus))"])
        }
    }
    
    func extractVideoId(from url: String) -> String? {
        // YouTube URLからビデオIDを抽出
        if let urlComponents = URLComponents(string: url),
           let queryItems = urlComponents.queryItems,
           let vParam = queryItems.first(where: { $0.name == "v" })?.value {
            return vParam
        }
        
        // youtu.be形式
        if url.contains("youtu.be/") {
            let components = url.components(separatedBy: "youtu.be/")
            if components.count > 1 {
                return components[1].components(separatedBy: "?")[0]
            }
        }
        
        return nil
    }
}