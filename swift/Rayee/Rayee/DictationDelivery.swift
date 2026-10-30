//
//  DictationDelivery.swift
//  Rayee
//
//  The rules that keep several dictations in order when one is still being cleaned up
//  while the next is spoken. Pure logic (no AppKit), so it can be tested.
//  - DeliveryLine: texts are pasted strictly in the order they were spoken.
//  - CleanupQueue: Smart Dictation clean-ups run one at a time.
//  - ModifierWait: a paste waits while a modifier key is held down.
//

import Foundation

/// One ordered line of texts waiting to be pasted. A dictation reserves a place the moment its
/// transcription succeeds, and later fills it with its text (or drops it). Texts are pasted
/// strictly in the order the places were reserved, one at a time. Use from the main thread.
final class DeliveryLine {
    typealias Slot = Int

    private enum Entry {
        case waiting
        case ready(String)
        case dropped
    }

    private var entries: [Slot: Entry] = [:]
    private var nextToReserve: Slot = 0
    private var nextToPaste: Slot = 0
    private var drainTask: Task<Void, Never>?
    private let paste: @MainActor (String) async -> Void

    /// - Parameter paste: pastes one text and returns when it is completely done
    ///   (including giving the user's clipboard back).
    init(paste: @escaping @MainActor (String) async -> Void) {
        self.paste = paste
    }

    /// Takes the next place in line.
    func reserve() -> Slot {
        let slot = nextToReserve
        nextToReserve += 1
        entries[slot] = .waiting
        return slot
    }

    /// The text for a place is ready.
    func fill(_ slot: Slot, _ text: String) {
        guard case .waiting? = entries[slot] else { return }
        entries[slot] = .ready(text)
        drain()
    }

    /// Nothing will be pasted for this place.
    func drop(_ slot: Slot) {
        guard case .waiting? = entries[slot] else { return }
        entries[slot] = .dropped
        drain()
    }

    /// Returns when everything that can be pasted right now has been.
    func idle() async {
        while let task = drainTask { await task.value }
    }

    private func drain() {
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor in
            loop: while let entry = entries[nextToPaste] {
                switch entry {
                case .waiting:
                    break loop
                case .dropped:
                    entries[nextToPaste] = nil
                    nextToPaste += 1
                case .ready(let text):
                    entries[nextToPaste] = nil
                    nextToPaste += 1
                    await paste(text)
                }
            }
            drainTask = nil
        }
    }
}

/// Runs jobs one after another, in the order they were added (the text model must not run twice at once).
/// A job that was cancelled while waiting should check `Task.isCancelled` first thing.
final class CleanupQueue {
    private var last: Task<Void, Never>?

    @discardableResult
    func enqueue(_ job: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = last
        let task = Task { @MainActor in
            await previous?.value
            await job()
        }
        last = task
        return task
    }
}

/// Waits for modifier keys to be let go before a paste, so ⌘V isn't turned into something else.
enum ModifierWait {
    static let pollInterval: Duration = .milliseconds(20)
    static let maxWait: Duration = .milliseconds(1000)

    /// Checks every 20 ms; gives up after 1 s and returns anyway.
    static func untilReleased(
        isHeld: () -> Bool,
        sleep: (Duration) async -> Void
    ) async {
        var waited: Duration = .zero
        while isHeld() && waited < maxWait {
            await sleep(pollInterval)
            waited += pollInterval
        }
    }
}
