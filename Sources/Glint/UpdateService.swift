import AppKit
import Observation
import CryptoKit
import GlintCore

@MainActor @Observable
final class UpdateService {
    var message = ""
    var latest = ""
    var progress = 0.0
    var checking = false
    var downloading = false
    var ready = false
    var releaseURL = AppVersion.repository + "/releases/latest"
    var onChange: () -> Void = {}
    private var staged: URL?
    private let settings: () -> AppSettings
    private let directory: URL
    init(directory: URL, settings: @escaping () -> AppSettings) { self.directory = directory; self.settings = settings }
    struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int; let digest: String? }
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }
    func check() async {
        guard !checking && !downloading else { return }
        checking = true; message = "检查中…"
        defer { checking = false; onChange() }
        do {
            let client = try HTTPClient(proxy: settings().proxy)
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/Skywalker144/Glint/releases/latest")!)
            request.setValue("Glint", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let release = try JSONDecoder().decode(Release.self, from: await client.data(for: request))
            let version = release.tag_name.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            guard AppVersion.isNewer(version, than: AppVersion.current) else { message = "已是最新版 v" + AppVersion.current; return }
            if ready && latest == version { message = "新版 v\(latest) 已下载"; return }
            latest = version; releaseURL = release.html_url; ready = false; staged = nil
            guard Bundle.main.bundleURL.pathExtension == "app" else { message = "发现新版 v\(latest)"; return }
            guard let asset = release.assets.first(where: { $0.name.hasSuffix("-mac.zip") }) else { throw GlintError.message("未找到 Mac 更新包") }
            downloading = true; progress = 0; onChange()
            defer { downloading = false }
            let observer = DownloadProgress { [weak self] value in
                Task { @MainActor in self?.progress = value; self?.message = "发现新版 v\(version)，下载中 \(Int(value * 100))%…" }
            }
            let (download, response) = try await client.session.download(from: asset.browser_download_url, delegate: observer)
            try HTTPClient.validate(response, data: Data())
            let data = try Data(contentsOf: download, options: .mappedIfSafe)
            guard data.count == asset.size else { throw GlintError.message("更新包大小不匹配，请重试") }
            if let digest = asset.digest, digest.hasPrefix("sha256:") {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == String(digest.dropFirst(7)) else { throw GlintError.message("更新包校验失败") }
            }
            let work = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let archive = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: archive)
            try await NativeProcess.run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
            let bundleURL = work.appendingPathComponent("Glint.app")
            guard let bundle = Bundle(url: bundleURL), bundle.bundleIdentifier == "com.skywalker144.glint",
                  bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version else { throw GlintError.message("更新包应用标识或版本不匹配") }
            try await NativeProcess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundleURL.path])
            staged = bundleURL; ready = true; progress = 1; message = "新版 v\(version) 已下载"
        } catch { message = "检查或下载失败：" + error.localizedDescription }
    }
    func apply() {
        guard ready, let staged, let executable = Bundle.main.executableURL else { return }
        do {
            let helper = staged.deletingLastPathComponent().appendingPathComponent("GlintInstaller")
            try FileManager.default.copyItem(at: executable, to: helper)
            let process = Process(); process.executableURL = helper
            process.arguments = ["--install-update", staged.path, Bundle.main.bundleURL.path, String(getpid())]
            process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); NSApp.terminate(nil)
        } catch { message = "安装更新失败：" + error.localizedDescription }
    }
    nonisolated static func install(arguments: [String]) -> Int32 {
        guard arguments.count == 5, let pid = Int32(arguments[4]), pid > 0 else { return 1 }
        let staged = URL(fileURLWithPath: arguments[2]), target = URL(fileURLWithPath: arguments[3])
        guard staged.pathExtension == "app", target.pathExtension == "app", staged != target,
              Bundle(url: staged)?.bundleIdentifier == "com.skywalker144.glint",
              Bundle(url: target)?.bundleIdentifier == "com.skywalker144.glint" else { return 1 }
        let fm = FileManager.default
        let next = target.deletingLastPathComponent().appendingPathComponent(".Glint-next-\(UUID().uuidString).app")
        let backup = target.deletingLastPathComponent().appendingPathComponent(".Glint-backup-\(UUID().uuidString).app")
        do {
            try fm.copyItem(at: staged, to: next)
            for _ in 0..<600 { if kill(pid, 0) != 0 { break }; usleep(100_000) }
            guard kill(pid, 0) != 0 else { try fm.removeItem(at: next); return 1 }
            try fm.moveItem(at: target, to: backup)
            do { try fm.moveItem(at: next, to: target) }
            catch { try fm.moveItem(at: backup, to: target); throw error }
            let open = Process(); open.executableURL = URL(fileURLWithPath: "/usr/bin/open"); open.arguments = [target.path]
            try open.run(); open.waitUntilExit()
            guard open.terminationStatus == 0 else {
                try fm.removeItem(at: target); try fm.moveItem(at: backup, to: target); return 1
            }
            try? fm.removeItem(at: backup)
            return 0
        } catch { try? fm.removeItem(at: next); return 1 }
    }
}

final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}

enum NativeProcess {
    static func run(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: GlintError.message("\(URL(fileURLWithPath: executable).lastPathComponent) 失败（\(process.terminationStatus)）")) }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
