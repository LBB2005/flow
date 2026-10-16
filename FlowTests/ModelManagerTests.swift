import Testing
@testable import Flow

actor FakeBackend: ModelBackend {
    nonisolated let displayName = "Fake"
    private var downloaded: Bool
    private var failDownload: Bool
    private var failLoad = false
    private(set) var downloads = 0
    private(set) var loads = 0
    private(set) var unloads = 0

    init(downloaded: Bool, failDownload: Bool = false) {
        self.downloaded = downloaded
        self.failDownload = failDownload
    }

    func setFailDownload(_ value: Bool) { failDownload = value }
    func setFailLoad(_ value: Bool) { failLoad = value }

    func isDownloaded() -> Bool { downloaded }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        downloads += 1
        if failDownload { throw FakeError.boom }
        progress(0.5)
        downloaded = true
    }
    func load() async throws {
        loads += 1
        if failLoad { throw FakeError.boom }
    }
    func unload() async { unloads += 1 }
}

@MainActor
struct ModelManagerTests {
    let gate = Gate()

    private func manager(_ t: FakeBackend, _ c: FakeBackend, keepWarm: KeepWarm = .tenMinutes) -> ModelManager {
        let gate = self.gate
        return ModelManager(transcriber: t, cleaner: c, keepWarm: { keepWarm },
                            idleTimer: IdleTimer(sleep: { _ in await gate.wait() }))
    }

    @Test func alreadyDownloadedModelsJustLoad() async {
        let t = FakeBackend(downloaded: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        await m.prepare(.transcriber).value
        #expect(m.status(of: .transcriber) == .ready)
        #expect(await t.downloads == 0)
        #expect(await t.loads == 1)
    }

    @Test func missingModelDownloadsThenLoads() async {
        let t = FakeBackend(downloaded: false), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        await m.prepare(.transcriber).value
        #expect(m.status(of: .transcriber) == .ready)
        #expect(await t.downloads == 1)
        #expect(await t.loads == 1)
    }

    @Test func downloadFailureIsReportedAndRetryWorks() async {
        let t = FakeBackend(downloaded: false, failDownload: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        await m.prepare(.transcriber).value
        guard case .failed = m.status(of: .transcriber) else { Issue.record("expected failed"); return }
        await t.setFailDownload(false)
        await m.prepare(.transcriber).value
        #expect(m.status(of: .transcriber) == .ready)
    }

    @Test func idleTimeoutUnloadsBothModels() async {
        let t = FakeBackend(downloaded: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        m.touch()
        #expect(await eventually { await gate.waiterCount == 1 })
        await gate.open()
        #expect(await eventually {
            let transcriberUnloads = await t.unloads
            let cleanerUnloads = await c.unloads
            return transcriberUnloads == 1 && cleanerUnloads == 1
        })
    }

    @Test func keepWarmAlwaysNeverUnloads() async {
        let t = FakeBackend(downloaded: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c, keepWarm: .always)
        m.touch()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await gate.waiterCount == 0)
        #expect(await t.unloads == 0)
    }

    @Test func replaceUnloadsOldAndPreparesNew() async {
        let old = FakeBackend(downloaded: true), new = FakeBackend(downloaded: false), c = FakeBackend(downloaded: true)
        let m = manager(old, c)
        await m.replace(.transcriber, with: new).value
        #expect(await eventually { await old.unloads == 1 })
        #expect(await new.downloads == 1)
        #expect(m.status(of: .transcriber) == .ready)
    }

    @Test func warmUpLoadsBothReadyModelsAndRestartsKeepWarm() async {
        let t = FakeBackend(downloaded: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        await m.prepare(.transcriber).value
        await m.prepare(.cleaner).value
        #expect(await eventually { await gate.waiterCount == 2 })
        await m.warmUp().value
        #expect(await t.loads == 2)
        #expect(await c.loads == 2)
        #expect(await eventually { await gate.waiterCount == 3 })
    }

    @Test func warmUpSkipsModelsThatAreNotReady() async {
        let t = FakeBackend(downloaded: false), c = FakeBackend(downloaded: false)
        let m = manager(t, c)
        await m.warmUp().value
        #expect(await t.loads == 0)
        #expect(await c.loads == 0)
        #expect(await t.downloads == 0)
    }

    @Test func warmUpLoadFailureIsHarmless() async {
        let t = FakeBackend(downloaded: true), c = FakeBackend(downloaded: true)
        let m = manager(t, c)
        await m.prepare(.transcriber).value
        await m.prepare(.cleaner).value
        await t.setFailLoad(true)
        await m.warmUp().value
        #expect(await t.loads == 2)
        #expect(await c.loads == 2)
        #expect(m.status(of: .transcriber) == .ready)
    }
}
