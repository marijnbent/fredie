import Foundation

struct FFmpegInstallation: Sendable {
    let ffmpeg: URL
    let ffprobe: URL

    static func find() -> FFmpegInstallation? {
        let directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        for directory in directories {
            let ffmpeg = URL(fileURLWithPath: directory).appendingPathComponent("ffmpeg")
            let ffprobe = URL(fileURLWithPath: directory).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path),
               FileManager.default.isExecutableFile(atPath: ffprobe.path) {
                return FFmpegInstallation(ffmpeg: ffmpeg, ffprobe: ffprobe)
            }
        }
        return nil
    }
}

final class FFmpegService: @unchecked Sendable {
    private struct ProbePayload: Decodable {
        struct Format: Decodable {
            let duration: String?
            let tags: [String: String]?
        }
        let format: Format
    }

    private let installation: FFmpegInstallation?
    private let processLock = NSLock()
    private var activeProcesses: [UUID: ImportProcessOperation] = [:]

    init(installation: FFmpegInstallation? = .find()) {
        self.installation = installation
    }

    var isAvailable: Bool { installation != nil }
    var executablePath: String? { installation?.ffmpeg.path }

    func inspect(_ url: URL) async throws -> FFprobeResult {
        guard let installation else { throw ImportieError.ffmpegMissing }
        let output = try await run(
            executable: installation.ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration:format_tags=creation_time,date,com.apple.quicktime.creationdate",
                "-of", "json",
                url.path,
            ]
        )
        let payload = try JSONDecoder().decode(ProbePayload.self, from: output)
        let duration = payload.format.duration.flatMap(Double.init) ?? 0
        let tags = payload.format.tags ?? [:]
        let dateValue = tags["creation_time"]
            ?? tags["date"]
            ?? tags["com.apple.quicktime.creationdate"]
        return FFprobeResult(duration: duration, creationDate: Self.parseDate(dateValue))
    }

    func thumbnail(_ url: URL) async throws -> Data {
        guard let installation else { throw ImportieError.ffmpegMissing }
        return try await run(
            executable: installation.ffmpeg,
            arguments: [
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-i", url.path,
                "-ss", "0.2",
                "-frames:v", "1",
                "-vf", "scale=320:-2",
                "-f", "image2pipe",
                "-vcodec", "png",
                "pipe:1",
            ]
        )
    }

    func convertToMP4(source: URL, destination: URL, duration: TimeInterval = 0, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let installation else { throw ImportieError.ffmpegMissing }
        let parser = FFmpegProgressParser(duration: duration, progress: progress)
        let commonArguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-progress", "pipe:1", "-nostats",
            "-i", source.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map_metadata", "0",
        ]
        do {
            _ = try await run(
                executable: installation.ffmpeg,
                arguments: commonArguments + [
                    "-c:v", "copy",
                    "-c:a", "aac", "-b:a", "256k",
                    "-movflags", "+faststart",
                    destination.path,
                ],
                onOutput: { parser.consume($0) }
            )
        } catch {
            try Task.checkCancellation()
            guard Self.canRetryWithEncoding(error) else { throw error }
            try? FileManager.default.removeItem(at: destination)
            _ = try await run(
                executable: installation.ffmpeg,
                arguments: commonArguments + [
                    "-c:v", "libx264", "-preset", "medium", "-crf", "18",
                    "-c:a", "aac", "-b:a", "256k",
                    "-movflags", "+faststart",
                    destination.path,
                ],
                onOutput: { parser.consume($0) }
            )
        }
    }

    private static func canRetryWithEncoding(_ error: Error) -> Bool {
        guard case ImportieError.processFailed(_, let message) = error else { return false }
        let detail = message.lowercased()
        return detail.contains("codec not currently supported in container")
            || (detail.contains("could not find tag for codec") && detail.contains("stream #0"))
    }

    func cancelAll() {
        processLock.lock()
        let processes = Array(activeProcesses.values)
        processLock.unlock()
        processes.forEach { $0.cancel() }
    }

    private func run(executable: URL, arguments: [String], onOutput: (@Sendable (Data) -> Void)? = nil) async throws -> Data {
        try Task.checkCancellation()
        let processID = UUID()
        let operation = ImportProcessOperation()
        processLock.withLock { activeProcesses[processID] = operation }
        defer { removeProcess(processID) }
        return try await withTaskCancellationHandler {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            let exit = try operation.start(process)
            let output = Task.detached(priority: .userInitiated) {
                var data = Data()
                while true {
                    let chunk = outputPipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    onOutput?(chunk)
                }
                return data
            }
            let errors = Task.detached(priority: .utility) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }
            await Task.detached(priority: .utility) { exit.wait() }.value
            let data = await output.value
            let errorData = await errors.value
            try operation.checkCancellation()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ImportieError.processFailed(tool: executable.lastPathComponent,
                    message: message?.isEmpty == false ? message! : "Exit code \(process.terminationStatus)")
            }
            return data
        } onCancel: {
            operation.cancel()
        }
    }

    private func removeProcess(_ id: UUID) {
        processLock.lock()
        activeProcesses[id] = nil
        processLock.unlock()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

final class ImportProcessOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    @discardableResult
    func start(_ process: Process) throws -> ProcessExit {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        self.process = process
        return try process.runObservingExit()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if let process, process.isRunning {
            process.terminate()
        }
    }

    func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled { throw CancellationError() }
    }
}

final class FFmpegProgressParser: @unchecked Sendable {
    private var buffer = Data()
    private let duration: TimeInterval
    private let progress: @Sendable (Double) -> Void

    init(duration: TimeInterval, progress: @escaping @Sendable (Double) -> Void) {
        self.duration = duration
        self.progress = progress
    }

    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            guard duration > 0, line.hasPrefix("out_time_us="),
                  let microseconds = Double(line.dropFirst("out_time_us=".count)),
                  microseconds.isFinite else { continue }
            progress(min(0.99, max(0, microseconds / 1_000_000 / duration)))
        }
    }
}
