//  Streams a Telegram video into AVPlayer before it has finished downloading.
//
//  AVPlayer asks for byte ranges as it plays and seeks; this answers each one
//  by having TDLib fetch exactly that range and reading it back. Seeking to
//  any point therefore starts playback there without waiting for the bytes
//  before it — which is what makes "skip 10 seconds" and resuming mid-video
//  instant on a long file.

import AVFoundation
import Foundation
import UniformTypeIdentifiers
import NodogramDomain

public final class StreamingAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    public static let scheme = "nodogram-stream"

    private let source: MediaByteSource
    private let fileID: Int
    private let size: Int64
    private let contentType: String
    private let gate = AsyncGate()
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// TDLib fetches parts of up to 512 KB; 1 MB per answer keeps the number of
    /// round trips low without delaying the first frame.
    private static let chunk: Int64 = 1 << 20

    public let queue = DispatchQueue(label: "app.nodogram.streaming")

    /// TDLib download priority for this asset's ranges: 32 for playback the
    /// user is watching, low for background work like poster frames.
    private let priority: Int

    public init(source: MediaByteSource, fileID: Int, size: Int64, mimeType: String, priority: Int = 32) {
        self.source = source
        self.priority = priority
        self.fileID = fileID
        self.size = size
        self.contentType = UTType(mimeType: mimeType)?.identifier ?? UTType.mpeg4Movie.identifier
    }

    /// An asset whose bytes are served by this loader. The loader must be
    /// kept alive for as long as the asset is in use.
    public func makeAsset(fileExtension: String) -> AVURLAsset {
        let url = URL(string: "\(Self.scheme)://file/\(fileID).\(fileExtension.isEmpty ? "mp4" : fileExtension)")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = size
            info.isByteRangeAccessSupported = true
        }
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        let request = UncheckedBox(loadingRequest)
        let data = UncheckedBox(dataRequest)
        let key = ObjectIdentifier(loadingRequest)

        let task = Task { [weak self] in
            guard let self else { return }
            await self.serve(request: request, data: data)
            self.lock.withLock { _ = self.tasks.removeValue(forKey: key) }
        }
        lock.withLock { tasks[key] = task }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // A seek cancels in-flight requests; stopping them frees TDLib to fetch
        // the new position immediately.
        let key = ObjectIdentifier(loadingRequest)
        lock.withLock { tasks.removeValue(forKey: key) }?.cancel()
    }

    private func serve(request: UncheckedBox<AVAssetResourceLoadingRequest>, data: UncheckedBox<AVAssetResourceLoadingDataRequest>) async {
        let dataRequest = data.value
        var offset = dataRequest.currentOffset != 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let end = dataRequest.requestsAllDataToEndOfResource
            ? size
            : min(size, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))

        do {
            while offset < end {
                try Task.checkCancellation()
                let start = offset
                let length = min(Self.chunk, end - start)
                let source = self.source, fileID = self.fileID, priority = self.priority
                // One range at a time per file: TDLib re-targets a download when
                // a second request with a different range arrives, so letting
                // them race would make both slower.
                let bytes: Data = try await gate.run {
                    try Task.checkCancellation()
                    try await source.prepareRange(fileID: fileID, offset: start, length: length, priority: priority)
                    return try await source.readRange(fileID: fileID, offset: start, count: length)
                }
                guard !bytes.isEmpty else { break }
                queue.sync { dataRequest.respond(with: bytes) }
                offset += Int64(bytes.count)
            }
            queue.async { request.value.finishLoading() }
        } catch is CancellationError {
            // Cancelled by AVPlayer; it no longer wants this range.
        } catch {
            queue.async { request.value.finishLoading(with: error) }
        }
    }
}

/// Serialises async work: one operation at a time, in arrival order.
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

/// AVFoundation's loading requests are not `Sendable`, but they are documented
/// as usable from any thread; responses are funnelled through the loader's
/// queue regardless.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
