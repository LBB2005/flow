/// Stand-in until the real overlay exists (Task 13).
@MainActor
final class LogPillPresenter: PillPresenter {
    func show(_ state: PillState) { Log.pipeline.info("pill: \(String(describing: state))") }
    func hide() { Log.pipeline.info("pill: hidden") }
}
