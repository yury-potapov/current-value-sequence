import Foundation

/// CurrentValue AsyncSequence
///
///  Producer:
///    ```
///       public final class Service: Sendable {
///          public func currentValueSequence() -> CurrentValueSequence<Int> {
///              subject.makeSequenceSync()
///          }
///
///          private func produceElement() {
///              subject.send(1)
///          }
///
///          private let subject = CurrentValueSequenceSubject<Int>(0)
///       }
///    ```
///
///  Consumer:
///   ```
///       let sequence = service.currentValueSequence()
///       let asyncValue = await sequence.currentValue // initial value
///
///       for await newValue in sequence {
///           print("new value \(newValue)")
///       }
///   ```
public struct CurrentValueSequence<Element: Sendable>: AsyncSequence, Sendable {

    public typealias AsyncIterator = AsyncStream<Element>.Iterator

    public var currentValue: Element {
        get async {
            await subject.currentValue()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    // MARK: - Fileprivate

    fileprivate init(
        subject: CurrentValueSequenceSubject<Element>,
        stream: AsyncStream<Element>
    ) {
        self.subject = subject
        self.stream = stream
    }

    // MARK: - Private

    private let subject: CurrentValueSequenceSubject<Element>
    private let stream: AsyncStream<Element>
}

public actor CurrentValueSequenceSubject<Element: Sendable> {

    public init(_ initialValue: Element) {
        self.value = initialValue
    }

    public func send(_ value: Element) {
        guard !isFinished else { return }
        self.value = value
        resumeContinuations(with: value)
    }

    public func finish() {
        isFinished = true
        finishContinuations()
    }

    public func currentValue() -> Element {
        value
    }

    // MARK: - Private

    private func appendContinuation(
        _ uuid: UUID,
        continuation: AsyncStream<Element>.Continuation,
        skipFirstValue: Bool
    ) {
        if !skipFirstValue {
            continuation.yield(value)
        }
        if isFinished {
            continuation.finish()
        } else {
            continuations[uuid] = continuation
        }
    }

    private func resetForIterator(_ uuid: UUID) {
        continuations[uuid] = nil
    }

    private func resumeContinuations(with value: Element) {
        continuations.forEach {
            let result = $0.1.yield(value)
            if case .terminated = result {
                continuations.removeValue(forKey: $0.0)
            }
        }
    }

    private func finishContinuations() {
        continuations.forEach {
            $0.1.finish()
        }
        continuations.removeAll()
    }

    private var value: Element
    private var continuations: [UUID : AsyncStream<Element>.Continuation] = [:]
    private var isFinished: Bool = false
}

extension CurrentValueSequenceSubject {

    /// Async constructor for CurrentValueSequence.
    /// Waits for the actual subscription to avoid skipping any values.
    ///
    ///  - Parameters:
    ///    - subject: `CurrentValueSequenceSubject` that produces elements.
    ///    - skipFirstValue: `true` when initial value is not needed. Subscribe only for updates.
    ///    - bufferringAllValues: `true` when you need all the history of updates.
    ///    Prevents skipping intermediate updates on slow consumers. May reduce performance.
    public func makeSequence(
        skipFirstValue: Bool = false,
        bufferringAllValues: Bool = false
    ) -> CurrentValueSequence<Element> {
        let updates = AsyncStream<Element>.makeStream(
            bufferingPolicy: bufferringAllValues ? .unbounded : .bufferingNewest(1)
        )

        let uuid = UUID()
        appendContinuation(
            uuid,
            continuation: updates.continuation,
            skipFirstValue: skipFirstValue
        )
        updates.continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.resetForIterator(uuid)
            }
        }

        return CurrentValueSequence(subject: self, stream: updates.stream)
    }

    /// Sync constructor for CurrentValueSequence.
    /// May skip some values, but the last value has to be sent.
    ///
    ///  - Parameters:
    ///    - subject: `CurrentValueSequenceSubject` that produces elements.
    ///    - skipFirstValue: `true` when initial value is not needed. Subscribe only for updates.
    ///    - bufferringAllValues: `true` when you need all the history of updates.
    ///    Prevents skipping intermediate updates on slow consumers. May reduce performance.
    public nonisolated func makeSequenceSync(
        skipFirstValue: Bool = false,
        bufferringAllValues: Bool = false
    ) -> CurrentValueSequence<Element> {
        let updates = AsyncStream<Element>.makeStream(
            bufferingPolicy: bufferringAllValues ? .unbounded : .bufferingNewest(1)
        )

        Task { [weak self] in
            guard let self else { return }
            let uuid = UUID()
            await appendContinuation(
                uuid,
                continuation: updates.continuation,
                skipFirstValue: skipFirstValue
            )
            updates.continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.resetForIterator(uuid)
                }
            }
        }

        return CurrentValueSequence(subject: self, stream: updates.stream)
    }

}

extension CurrentValueSequence {
    public static func constant(_ value: Element) -> CurrentValueSequence<Element> {
        let subject = CurrentValueSequenceSubject(value)
        return subject.makeSequenceSync()
    }
}
