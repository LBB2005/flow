import AppKit

/// Pauses the Spotify app and playing `<video>`/`<audio>` in Chrome tabs (YouTube, Netflix, HBO),
/// then resumes only those. Each step shells out to `osascript` (~100 ms), so the steps run in order
/// on a background queue and the hotkey never waits for them.
///
/// Needs Automation permission for each app (macOS asks the first time) and, for Chrome,
/// View → Developer → Allow JavaScript from Apple Events.
nonisolated final class SystemMediaPauser: MediaPauser, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.liamblackshawbrown.flow.media")
    // Only touched on `queue`.
    private var pausedSpotify = false
    private var pausedChrome = false

    func pause() {
        queue.async { [self] in
            pausedSpotify = Self.isRunning(MediaScripts.spotifyBundleID)
                && Self.run(MediaScripts.spotifyPause) == "paused"
            pausedChrome = Self.isRunning(MediaScripts.chromeBundleID)
                && Self.pauseChrome() > 0
            if pausedSpotify || pausedChrome {
                Log.media.notice("paused media (spotify: \(self.pausedSpotify, privacy: .public), chrome: \(self.pausedChrome, privacy: .public))")
            }
        }
    }

    func resume() {
        queue.async { [self] in
            if pausedSpotify { _ = Self.run(MediaScripts.spotifyResume) }
            if pausedChrome { _ = Self.run(MediaScripts.chromeResume) }
            if pausedSpotify || pausedChrome { Log.media.notice("resumed media") }
            pausedSpotify = false
            pausedChrome = false
        }
    }

    /// Returns how many media elements were paused across all tabs.
    private static func pauseChrome() -> Int {
        guard let output = run(MediaScripts.chromePause) else { return 0 }
        let (count, error) = MediaScripts.parseChromePause(output)
        if count == 0, let error {
            // Usually "Allow JavaScript from Apple Events" is off.
            Log.media.notice("chrome tabs not scriptable: \(error, privacy: .public)")
        }
        return count
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs an AppleScript and returns its trimmed output, or nil if it failed.
    private static func run(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            Log.media.error("osascript failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // -1743 means the user hasn't allowed Flow to control the app (System Settings → Privacy → Automation).
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.media.error("media script failed: \(message, privacy: .public)")
            return nil
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The AppleScript and page JavaScript behind `SystemMediaPauser`.
enum MediaScripts {
    static let spotifyBundleID = "com.spotify.client"
    static let chromeBundleID = "com.google.Chrome"

    // `is running` checks keep the scripts from launching an app that quit in the meantime.
    static let spotifyPause = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    pause
                    return "paused"
                end if
            end tell
        end if
        return ""
        """

    static let spotifyResume = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is paused then play
            end tell
        end if
        """

    /// Pauses playing media in a page and tags it so resume only touches what Flow paused.
    /// Returns the number paused. Uses no double quotes so it can sit inside an AppleScript string.
    static let pageJSPause = """
        (function(){var n=0;document.querySelectorAll('video,audio').forEach(function(m){\
        if(!m.paused&&!m.ended){m.pause();m.dataset.flowPaused='1';n++;}});return n;})()
        """

    /// Plays tagged media that is still paused (skips anything the user already resumed).
    static let pageJSResume = """
        (function(){var n=0;document.querySelectorAll('[data-flow-paused]').forEach(function(m){\
        delete m.dataset.flowPaused;if(m.paused){var p=m.play();if(p)p.catch(function(){});n++;}});return n;})()
        """

    static let chromePause = chromeEveryTab(pageJSPause)
    static let chromeResume = chromeEveryTab(pageJSResume)

    /// Runs `js` in every tab and prints "<sum of results>\t<first error, if any>".
    private static func chromeEveryTab(_ js: String) -> String {
        """
        set total to 0
        set firstError to ""
        if application "Google Chrome" is running then
            with timeout of 3 seconds
                tell application "Google Chrome"
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                set total to total + (execute t javascript "\(js)")
                            on error message
                                if firstError is "" then set firstError to message
                            end try
                        end repeat
                    end repeat
                end tell
            end timeout
        end if
        return (total as text) & tab & firstError
        """
    }

    /// Splits the output of `chromePause` into the paused count and the first tab error.
    static func parseChromePause(_ output: String) -> (count: Int, error: String?) {
        let parts = output.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let count = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        let error = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return (count, error)
    }
}
