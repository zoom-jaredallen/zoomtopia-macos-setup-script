import Foundation

public final class PackageDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let spec: PackageSpec
    private let latest: Bool
    private var limit: Int64 { latest ? 1_999_999_999 : spec.size }
    private let destination: URL
    private let configuration: URLSessionConfiguration
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var failure: Error?
    private var redirects = 0
    private var downloaded = false

    public init(spec: PackageSpec, destination: URL, configuration: URLSessionConfiguration = .ephemeral, latest: Bool = false, progress: @escaping @Sendable (Double) -> Void) {
        self.latest = latest; self.spec = spec; self.destination = destination; self.configuration = configuration; self.progress = progress
    }
    public func run() async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = configuration
                config.timeoutIntervalForRequest = 45
                config.timeoutIntervalForResource = 900
                config.urlCache = nil
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: spec.url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url, DownloadPolicy.allows(url, hosts: spec.allowedHosts) else {
            failure = SetupFailure("Download redirected outside approved HTTPS hosts")
            completionHandler(nil); task.cancel(); return
        }
        completionHandler(request)
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            failure = SetupFailure("\(spec.name) download exceeds the approved package size")
            downloadTask.cancel(); return
        }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : limit)))
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  let url = response.url, DownloadPolicy.allows(url, hosts: spec.allowedHosts) else {
                throw SetupFailure("\(spec.name) download failed (HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)). Check network access or obtain a newer setup app.")
            }
            try SafeFiles.copyVerified(from: location, to: destination, sha256: latest ? SafeFiles.hash(location, maxBytes: limit) : spec.sha256, maxBytes: limit)
            downloaded = true
        } catch { failure = error }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation; self.continuation = nil
        let wasCancelled = cancelled
        lock.unlock()
        session.finishTasksAndInvalidate()
        if wasCancelled { continuation?.resume(throwing: CancellationError()) }
        else if let error = failure ?? error { continuation?.resume(throwing: error) }
        else if !downloaded { continuation?.resume(throwing: SetupFailure("Download did not produce a complete package")) }
        else { continuation?.resume() }
    }
}
