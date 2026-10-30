import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// "What am I looking at?" — captures the front window or a whole display for the AI to see.
enum ScreenTools {
    static func all() -> [Tool] { [lookAtScreen] }

    static let lookAtScreen = Tool.rich(
        name: "look_at_screen",
        description: "Take a screenshot so you can see what the user is looking at, then answer about it. Use for 'what am I looking at', 'what does this error mean', 'summarise this page', 'read this to me', etc. Defaults to the frontmost window.",
        properties: [
            "target": P.oneOf(["window", "screen"], "'window' = the frontmost window (default), 'screen' = the whole display under the mouse"),
        ]
    ) { args in
        guard await ScreenCapture.hasPermission() else {
            await ScreenCapture.requestPermission()
            throw TESSError("I need Screen Recording permission. I've opened the request — allow TESS in System Settings, Privacy and Security, Screen Recording, then quit and reopen TESS.")
        }
        let wantScreen = args.string("target") == "screen"
        let capture = try await ScreenCapture.capture(screen: wantScreen)
        let what = capture.description
        return ToolOutput(text: "Screenshot of \(what) is attached. Describe or answer from what you see; don't mention that it's a screenshot unless helpful.",
                          image: capture.jpeg)
    }
}

enum ScreenCapture {
    struct Result {
        let jpeg: Data
        let description: String
    }

    @MainActor static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }
    @MainActor static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    @MainActor static func capture(screen: Bool) async throws -> Result {
        let path = NSTemporaryDirectory() + "tess-capture-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: path) }

        var description = "the screen"
        var arguments = ["-x", "-t", "png"]
        if !screen, let window = frontWindow() {
            arguments += ["-o", "-l", String(window.id), path]
            description = window.title.isEmpty ? "the \(window.app) window" : "the \(window.app) window “\(window.title)”"
        } else {
            arguments += ["-D", String(displayIndexUnderMouse()), path]
        }
        try await Shell.run("/usr/sbin/screencapture", arguments)
        guard let jpeg = ImageTools.jpeg(fromFile: URL(fileURLWithPath: path)) else {
            throw TESSError("The screenshot came back empty.")
        }
        return Result(jpeg: jpeg, description: description)
    }

    struct WindowInfo {
        let id: CGWindowID
        let app: String
        let title: String
    }

    /// Topmost normal window that doesn't belong to TESS.
    @MainActor static func frontWindow() -> WindowInfo? {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for window in list {
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            guard layer == 0, pid != me, width > 80, height > 80,
                  let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
            return WindowInfo(id: CGWindowID(number.uint32Value),
                              app: window[kCGWindowOwnerName as String] as? String ?? "front",
                              title: window[kCGWindowName as String] as? String ?? "")
        }
        return nil
    }

    /// screencapture's -D index (1 = main display) of the display under the mouse.
    @MainActor static func displayIndexUnderMouse() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        // CoreGraphics uses a top-left origin; NSEvent uses bottom-left.
        let mouse = NSEvent.mouseLocation
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let point = CGPoint(x: mouse.x, y: mainHeight - mouse.y)
        for (index, display) in displays.enumerated() where CGDisplayBounds(display).contains(point) {
            return index + 1
        }
        return 1
    }
}

enum ImageTools {
    /// Longest side sent to the AI; larger images cost more without helping much.
    static let maxPixels = 1568

    static func jpeg(fromFile url: URL, maxPixels: Int = maxPixels) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image)
    }

    static func jpeg(_ image: CGImage, maxPixels: Int = maxPixels) -> Data? {
        var cgImage = image
        let longest = max(image.width, image.height)
        if longest > maxPixels {
            let scale = Double(maxPixels) / Double(longest)
            let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let scaled = context.makeImage() { cgImage = scaled }
            }
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
