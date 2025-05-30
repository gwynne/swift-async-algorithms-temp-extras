//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if compiler(>=6.1)
import DequeModule

extension MultiProducerSingleConsumerAsyncChannel {
  @usableFromInline
  enum _InternalBackpressureStrategy: Sendable, CustomStringConvertible {
    @usableFromInline
    struct _Watermark: Sendable, CustomStringConvertible {
      /// The low watermark where demand should start.
      @usableFromInline
      let _low: Int

      /// The high watermark where demand should be stopped.
      @usableFromInline
      let _high: Int

      /// The current watermark level.
      @usableFromInline
      var _currentWatermark: Int = 0

      /// A closure that can be used to calculate the watermark impact of a single element
      @usableFromInline
      let _waterLevelForElement: (@Sendable (borrowing Element) -> Int)?

      @usableFromInline
      var description: String {
        "watermark(\(self._currentWatermark))"
      }

      init(low: Int, high: Int, waterLevelForElement: (@Sendable (borrowing Element) -> Int)?) {
        precondition(low <= high)
        self._low = low
        self._high = high
        self._waterLevelForElement = waterLevelForElement
      }

      @inlinable
      mutating func didSend(elements: Deque<Element>.SubSequence) -> Bool {
        if let waterLevelForElement = self._waterLevelForElement {
          for element in elements {
            self._currentWatermark += waterLevelForElement(element)
          }
        } else {
          self._currentWatermark += elements.count
        }
        precondition(self._currentWatermark >= 0)
        // We are demanding more until we reach the high watermark
        return self._currentWatermark < self._high
      }

      @inlinable
      mutating func didConsume(element: Element) -> Bool {
        if let waterLevelForElement = self._waterLevelForElement {
          self._currentWatermark -= waterLevelForElement(element)
        } else {
          self._currentWatermark -= 1
        }
        precondition(self._currentWatermark >= 0)
        // We start demanding again once we are below the low watermark
        return self._currentWatermark < self._low
      }
    }

    @usableFromInline
    struct _Unbounded: Sendable, CustomStringConvertible {
      @usableFromInline
      var description: String {
        "unbounded"
      }

      init() {}

      @inlinable
      mutating func didSend(elements: Deque<Element>.SubSequence) -> Bool {
        true
      }

      @inlinable
      mutating func didConsume(element: Element) -> Bool {
        true
      }
    }

    /// A watermark based strategy.
    case watermark(_Watermark)
    /// An unbounded based strategy.
    case unbounded(_Unbounded)

    @usableFromInline
    var description: String {
      switch consume self {
      case .watermark(let strategy):
        return strategy.description
      case .unbounded(let unbounded):
        return unbounded.description
      }
    }

    @inlinable
    mutating func didSend(elements: Deque<Element>.SubSequence) -> Bool {
      switch consume self {
      case .watermark(var strategy):
        let result = strategy.didSend(elements: elements)
        self = .watermark(strategy)
        return result
      case .unbounded(var strategy):
        let result = strategy.didSend(elements: elements)
        self = .unbounded(strategy)
        return result
      }
    }

    @inlinable
    mutating func didConsume(element: Element) -> Bool {
      switch consume self {
      case .watermark(var strategy):
        let result = strategy.didConsume(element: element)
        self = .watermark(strategy)
        return result
      case .unbounded(var strategy):
        let result = strategy.didConsume(element: element)
        self = .unbounded(strategy)
        return result
      }
    }
  }
}

extension MultiProducerSingleConsumerAsyncChannel {
  @usableFromInline
  final class _Storage: Sendable {
    @usableFromInline
    nonisolated(unsafe) let _stateMachine: NIOLockedValueBox<_StateMachine>

    var onTermination: (@Sendable () -> Void)? {
      set {
        self._stateMachine.withLockedValue {
          $0._onTermination = newValue
        }
      }
      get {
        self._stateMachine.withLockedValue {
          $0._onTermination
        }
      }
    }

    @inlinable
    init(
      backpressureStrategy: _InternalBackpressureStrategy
    ) {
      self._stateMachine = .init(_StateMachine(backpressureStrategy: backpressureStrategy))
    }

    func channelDeinitialized() {
      let action = self._stateMachine.withLockedValue {
        $0.channelDeinitialized()
      }

      switch action {
      case .callOnTermination(let onTermination):
        onTermination?()

      case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
        for producerContinuation in producerContinuations {
          switch producerContinuation {
          case .closure(let onProduceMore):
            onProduceMore(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
          case .continuation(let continuation):
            continuation.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
          }
        }
        onTermination?()

      case .none:
        break
      }
    }

    func sequenceInitialized() {
      self._stateMachine.withLockedValue {
        $0.sequenceInitialized()
      }
    }

    func sequenceDeinitialized() {
      let action = self._stateMachine.withLockedValue {
        $0.sequenceDeinitialized()
      }

      switch action {
      case .callOnTermination(let onTermination):
        onTermination?()

      case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
        for producerContinuation in producerContinuations {
          switch producerContinuation {
          case .closure(let onProduceMore):
            onProduceMore(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
          case .continuation(let continuation):
            continuation.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
          }
        }
        onTermination?()

      case .none:
        break
      }
    }

    func iteratorInitialized() {
      self._stateMachine.withLockedValue {
        $0.iteratorInitialized()
      }
    }

    func iteratorDeinitialized() {
      let action = self._stateMachine.withLockedValue {
        $0.iteratorDeinitialized()
      }

      switch action {
      case .callOnTermination(let onTermination):
        onTermination?()

      case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
        for producerContinuation in producerContinuations {
          switch producerContinuation {
          case .closure(let onProduceMore):
            onProduceMore(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
          case .continuation(let continuation):
            continuation.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
          }
        }
        onTermination?()

      case .none:
        break
      }
    }

    func sourceInitialized() {
      self._stateMachine.withLockedValue {
        $0.sourceInitialized()
      }
    }

    func sourceDeinitialized() {
      let action = self._stateMachine.withLockedValue {
        $0.sourceDeinitialized()
      }

      switch action {
      case .resumeConsumerAndCallOnTermination(let consumerContinuation, let failure, let onTermination):
        switch failure {
        case .some(let error):
          consumerContinuation.resume(throwing: error)
        case .none:
          consumerContinuation.resume(returning: nil)
        }

        onTermination?()

      case .none:
        break
      }
    }

    @inlinable
    func send(
      contentsOf sequence: sending some Sequence<Element>
    ) throws -> MultiProducerSingleConsumerAsyncChannel<Element, Failure>.Source.SendResult {
      let action = self._stateMachine.withLockedValue {
        $0.send(sequence)
      }

      switch action {
      case .returnProduceMore:
        return .produceMore

      case .returnEnqueue(let callbackToken):
        return .enqueueCallback(.init(id: callbackToken))

      case .resumeConsumerAndReturnProduceMore(let continuation, let element):
        continuation.resume(returning: element)
        return .produceMore

      case .resumeConsumerAndReturnEnqueue(let continuation, let element, let callbackToken):
        continuation.resume(returning: element)
        return .enqueueCallback(.init(id: callbackToken))

      case .throwFinishedError:
        throw MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()
      }
    }

    @inlinable
    func enqueueProducer(
      callbackToken: UInt64,
      continuation: UnsafeContinuation<Void, any Error>
    ) {
      let action = self._stateMachine.withLockedValue {
        $0.enqueueContinuation(callbackToken: callbackToken, continuation: continuation)
      }

      switch action {
      case .resumeProducer(let continuation):
        continuation.resume()

      case .resumeProducerWithError(let continuation, let error):
        continuation.resume(throwing: error)

      case .none:
        break
      }
    }

    @inlinable
    func enqueueProducer(
      callbackToken: UInt64,
      onProduceMore: sending @escaping (Result<Void, any Error>) -> Void
    ) {
      let action = self._stateMachine.withLockedValue {
        $0.enqueueProducer(callbackToken: callbackToken, onProduceMore: onProduceMore)
      }

      switch action {
      case .resumeProducer(let onProduceMore):
        onProduceMore(Result<Void, any Error>.success(()))

      case .resumeProducerWithError(let onProduceMore, let error):
        onProduceMore(Result<Void, any Error>.failure(error))

      case .none:
        break
      }
    }

    @inlinable
    func cancelProducer(
      callbackToken: UInt64
    ) {
      let action = self._stateMachine.withLockedValue {
        $0.cancelProducer(callbackToken: callbackToken)
      }

      switch action {
      case .resumeProducerWithCancellationError(let onProduceMore):
        switch onProduceMore {
        case .closure(let onProduceMore):
          onProduceMore(.failure(CancellationError()))
        case .continuation(let continuation):
          continuation.resume(throwing: CancellationError())
        }

      case .none:
        break
      }
    }

    @inlinable
    func finish(_ failure: Failure?) {
      let action = self._stateMachine.withLockedValue {
        $0.finish(failure)
      }

      switch action {
      case .callOnTermination(let onTermination):
        onTermination?()

      case .resumeConsumerAndCallOnTermination(let consumerContinuation, let failure, let onTermination):
        switch failure {
        case .some(let error):
          consumerContinuation.resume(throwing: error)
        case .none:
          consumerContinuation.resume(returning: nil)
        }

        onTermination?()

      case .resumeProducers(let producerContinuations):
        for producerContinuation in producerContinuations {
          switch producerContinuation {
          case .closure(let onProduceMore):
            onProduceMore(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
          case .continuation(let continuation):
            continuation.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
          }
        }

      case .none:
        break
      }
    }

    @inlinable
    func next(isolation: isolated (any Actor)? = #isolation) async throws -> Element? {
      let action = self._stateMachine.withLockedValue() {
        $0.next()
      }

      switch action {
      case .returnElement(let element):
        return element

      case .returnElementAndResumeProducers(let element, let producerContinuations):
        for producerContinuation in producerContinuations {
          switch producerContinuation {
          case .closure(let onProduceMore):
            onProduceMore(.success(()))
          case .continuation(let continuation):
            continuation.resume()
          }
        }

        return element

      case .returnFailureAndCallOnTermination(let failure, let onTermination):
        onTermination?()
        switch failure {
        case .some(let error):
          throw error

        case .none:
          return nil
        }

      case .returnNil:
        return nil

      case .suspendTask:
        return try await self.suspendNext()
      }
    }

    @inlinable
    func suspendNext(isolation: isolated (any Actor)? = #isolation) async throws -> Element? {
      try await withTaskCancellationHandler {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Element?, Error>) in
          let action = self._stateMachine.withLockedValue {
            $0.suspendNext(continuation: continuation)
          }

          switch action {
          case .resumeConsumerWithElement(let continuation, let element):
            continuation.resume(returning: element)

          case .resumeConsumerWithElementAndProducers(
            let continuation,
            let element,
            let producerContinuations
          ):
            continuation.resume(returning: element)
            for producerContinuation in producerContinuations {
              switch producerContinuation {
              case .closure(let onProduceMore):
                onProduceMore(.success(()))
              case .continuation(let continuation):
                continuation.resume()
              }
            }

          case .resumeConsumerWithFailureAndCallOnTermination(
            let continuation,
            let failure,
            let onTermination
          ):
            switch failure {
            case .some(let error):
              continuation.resume(throwing: error)

            case .none:
              continuation.resume(returning: nil)
            }
            onTermination?()

          case .resumeConsumerWithNil(let continuation):
            continuation.resume(returning: nil)

          case .none:
            break
          }
        }
      } onCancel: {
        let action = self._stateMachine.withLockedValue {
          $0.cancelNext()
        }

        switch action {
        case .resumeConsumerWithNilAndCallOnTermination(let continuation, let onTermination):
          continuation.resume(returning: nil)
          onTermination?()

        case .failProducersAndCallOnTermination(let producerContinuations, let onTermination):
          for producerContinuation in producerContinuations {
            switch producerContinuation {
            case .closure(let onProduceMore):
              onProduceMore(.failure(MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError()))
            case .continuation(let continuation):
              continuation.resume(throwing: MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
            }
          }
          onTermination?()

        case .none:
          break
        }
      }
    }
  }
}

extension MultiProducerSingleConsumerAsyncChannel._Storage {
  /// The state machine of the channel.
  @usableFromInline
  struct _StateMachine {
    /// The state machine's current state.
    @usableFromInline
    var _state: _State

    @inlinable
    var _onTermination: (@Sendable () -> Void)? {
      set {
        switch self._state {
        case .channeling(var channeling):
          channeling.onTermination = newValue
          self = .init(state: .channeling(channeling))

        case .sourceFinished(var sourceFinished):
          sourceFinished.onTermination = newValue
          self = .init(state: .sourceFinished(sourceFinished))

        case .finished(let finished):
          self = .init(state: .finished(finished))
        }
      }
      get {
        switch self._state {
        case .channeling(let channeling):
          return channeling.onTermination

        case .sourceFinished(let sourceFinished):
          return sourceFinished.onTermination

        case .finished:
          return nil
        }
      }
    }

    @usableFromInline
    init(
      backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy
    ) {
      self._state = .channeling(
        .init(
          backpressureStrategy: backpressureStrategy,
          iteratorInitialized: false,
          sequenceInitialized: false,
          buffer: .init(),
          producerContinuations: .init(),
          cancelledAsyncProducers: .init(),
          hasOutstandingDemand: true,
          activeProducers: 0,
          nextCallbackTokenID: 0
        )
      )
    }

    @inlinable
    init(state: consuming _State) {
      self._state = state
    }

    @inlinable
    mutating func sourceInitialized() {
      switch self._state {
      case .channeling(var channeling):
        channeling.activeProducers += 1
        self = .init(state: .channeling(channeling))

      case .sourceFinished(let sourceFinished):
        self = .init(state: .sourceFinished(sourceFinished))

      case .finished(let finished):
        self = .init(state: .finished(finished))
      }
    }

    /// Actions returned by `sourceDeinitialized()`.
    @usableFromInline
    enum SourceDeinitialized {
      /// Indicates that the consumer  should be resumed with the failure, the producers
      /// should be resumed with an error and `onTermination` should be called.
      case resumeConsumerAndCallOnTermination(
        consumerContinuation: UnsafeContinuation<Element?, any Error>,
        failure: Failure?,
        onTermination: (() -> Void)?
      )
    }

    @inlinable
    mutating func sourceDeinitialized() -> SourceDeinitialized? {
      switch self._state {
      case .channeling(var channeling):
        channeling.activeProducers -= 1

        guard channeling.activeProducers == 0 else {
          // We still have more producers
          self = .init(state: .channeling(channeling))

          return nil
        }
        // This was the last producer so we can transition to source finished now

        guard let consumerContinuation = channeling.consumerContinuation else {
          // We don't have a suspended consumer so we are just going to mark
          // the source as finished.
          self = .init(
            state: .sourceFinished(
              .init(
                iteratorInitialized: channeling.iteratorInitialized,
                sequenceInitialized: channeling.sequenceInitialized,
                buffer: channeling.buffer,
                failure: nil,
                onTermination: channeling.onTermination
              )
            )
          )

          return nil
        }
        // We have a continuation, this means our buffer must be empty
        // Furthermore, we can now transition to finished
        // and resume the continuation with the failure
        precondition(channeling.buffer.isEmpty, "Expected an empty buffer")

        self = .init(
          state: .finished(
            .init(
              iteratorInitialized: channeling.iteratorInitialized,
              sequenceInitialized: channeling.sequenceInitialized,
              sourceFinished: true
            )
          )
        )

        return .resumeConsumerAndCallOnTermination(
          consumerContinuation: consumerContinuation,
          failure: nil,
          onTermination: channeling.onTermination
        )

      case .sourceFinished(let sourceFinished):
        // If the source has finished, finishing again has no effect.
        self = .init(state: .sourceFinished(sourceFinished))

        return .none

      case .finished(var finished):
        finished.sourceFinished = true
        self = .init(state: .finished(finished))
        return .none
      }
    }

    @inlinable
    mutating func sequenceInitialized() {
      switch self._state {
      case .channeling(var channeling):
        channeling.sequenceInitialized = true
        self = .init(state: .channeling(channeling))

      case .sourceFinished(var sourceFinished):
        sourceFinished.sequenceInitialized = true
        self = .init(state: .sourceFinished(sourceFinished))

      case .finished(var finished):
        finished.sequenceInitialized = true
        self = .init(state: .finished(finished))
      }
    }

    /// Actions returned by `sequenceDeinitialized()`.
    @usableFromInline
    enum ChannelOrSequenceDeinitializedAction {
      /// Indicates that `onTermination` should be called.
      case callOnTermination((@Sendable () -> Void)?)
      /// Indicates that all producers should be failed and `onTermination` should be called.
      case failProducersAndCallOnTermination(
        _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>,
        (@Sendable () -> Void)?
      )
    }

    @inlinable
    mutating func sequenceDeinitialized() -> ChannelOrSequenceDeinitializedAction? {
      switch self._state {
      case .channeling(let channeling):
        guard channeling.iteratorInitialized else {
          precondition(channeling.sequenceInitialized, "Sequence was not initialized")
          // No iterator was created so we can transition to finished right away.
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: false,
                sequenceInitialized: true,
                sourceFinished: false
              )
            )
          )

          return .failProducersAndCallOnTermination(
            .init(channeling.suspendedProducers.lazy.map { $0.1 }),
            channeling.onTermination
          )
        }
        // An iterator was created and we deinited the sequence.
        // This is an expected pattern and we just continue on normal.
        self = .init(state: .channeling(channeling))

        return .none

      case .sourceFinished(let sourceFinished):
        guard sourceFinished.iteratorInitialized else {
          precondition(sourceFinished.sequenceInitialized, "Sequence was not initialized")
          // No iterator was created so we can transition to finished right away.
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: false,
                sequenceInitialized: true,
                sourceFinished: true
              )
            )
          )

          return .callOnTermination(sourceFinished.onTermination)
        }
        // An iterator was created and we deinited the sequence.
        // This is an expected pattern and we just continue on normal.
        self = .init(state: .sourceFinished(sourceFinished))

        return .none

      case .finished(let finished):
        // We are already finished so there is nothing left to clean up.
        // This is just the references dropping afterwards.
        self = .init(state: .finished(finished))

        return .none
      }
    }

    @inlinable
    mutating func channelDeinitialized() -> ChannelOrSequenceDeinitializedAction? {
      switch self._state {
      case .channeling(let channeling):
        guard channeling.sequenceInitialized else {
          // No async sequence was created so we can transition to finished
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: channeling.iteratorInitialized,
                sequenceInitialized: channeling.sequenceInitialized,
                sourceFinished: true
              )
            )
          )

          return .failProducersAndCallOnTermination(
            .init(channeling.suspendedProducers.lazy.map { $0.1 }),
            channeling.onTermination
          )
        }
        // An async sequence was created so we need to ignore this deinit
        self = .init(state: .channeling(channeling))
        return nil

      case .sourceFinished(let sourceFinished):
        guard sourceFinished.sequenceInitialized else {
          // No async sequence was created so we can transition to finished
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: sourceFinished.iteratorInitialized,
                sequenceInitialized: sourceFinished.sequenceInitialized,
                sourceFinished: true
              )
            )
          )

          return .callOnTermination(sourceFinished.onTermination)
        }
        // An async sequence was created so we need to ignore this deinit
        self = .init(state: .sourceFinished(sourceFinished))
        return nil

      case .finished(let finished):
        // We are already finished so there is nothing left to clean up.
        // This is just the references dropping afterwards.
        self = .init(state: .finished(finished))

        return .none
      }
    }

    @inlinable
    mutating func iteratorInitialized() {
      switch self._state {
      case .channeling(var channeling):
        if channeling.iteratorInitialized {
          // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
          fatalError("Only a single AsyncIterator can be created")
        } else {
          // The first and only iterator was initialized.
          channeling.iteratorInitialized = true
          self = .init(state: .channeling(channeling))
        }

      case .sourceFinished(var sourceFinished):
        if sourceFinished.iteratorInitialized {
          // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
          fatalError("Only a single AsyncIterator can be created")
        } else {
          // The first and only iterator was initialized.
          sourceFinished.iteratorInitialized = true
          self = .init(state: .sourceFinished(sourceFinished))
        }

      case .finished(let finished):
        if finished.iteratorInitialized {
          // Our sequence is a unicast sequence and does not support multiple AsyncIterator's
          fatalError("Only a single AsyncIterator can be created")
        } else {
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: true,
                sequenceInitialized: true,
                sourceFinished: finished.sourceFinished
              )
            )
          )
        }
      }
    }

    /// Actions returned by `iteratorDeinitialized()`.
    @usableFromInline
    enum IteratorDeinitializedAction {
      /// Indicates that `onTermination` should be called.
      case callOnTermination((@Sendable () -> Void)?)
      /// Indicates that  all producers should be failed and `onTermination` should be called.
      case failProducersAndCallOnTermination(
        _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>,
        (@Sendable () -> Void)?
      )
    }

    @inlinable
    mutating func iteratorDeinitialized() -> IteratorDeinitializedAction? {
      switch self._state {
      case .channeling(let channeling):
        if channeling.iteratorInitialized {
          // An iterator was created and deinited. Since we only support
          // a single iterator we can now transition to finish.
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: true,
                sequenceInitialized: true,
                sourceFinished: false
              )
            )
          )

          return .failProducersAndCallOnTermination(
            .init(channeling.suspendedProducers.lazy.map { $0.1 }),
            channeling.onTermination
          )
        } else {
          // An iterator needs to be initialized before it can be deinitialized.
          fatalError("MultiProducerSingleConsumerAsyncChannel internal inconsistency")
        }

      case .sourceFinished(let sourceFinished):
        if sourceFinished.iteratorInitialized {
          // An iterator was created and deinited. Since we only support
          // a single iterator we can now transition to finish.
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: true,
                sequenceInitialized: true,
                sourceFinished: true
              )
            )
          )

          return .callOnTermination(sourceFinished.onTermination)
        } else {
          // An iterator needs to be initialized before it can be deinitialized.
          fatalError("MultiProducerSingleConsumerAsyncChannel internal inconsistency")
        }

      case .finished(let finished):
        // We are already finished so there is nothing left to clean up.
        // This is just the references dropping afterwards.
        self = .init(state: .finished(finished))

        return .none
      }
    }

    /// Actions returned by `send()`.
    @usableFromInline
    enum SendAction {
      /// Indicates that the producer should be notified to produce more.
      case returnProduceMore
      /// Indicates that the producer should be suspended to stop producing.
      case returnEnqueue(
        callbackToken: UInt64
      )
      /// Indicates that the consumer should be resumed and the producer should be notified to produce more.
      case resumeConsumerAndReturnProduceMore(
        continuation: UnsafeContinuation<Element?, any Error>,
        element: Element
      )
      /// Indicates that the consumer should be resumed and the producer should be suspended.
      case resumeConsumerAndReturnEnqueue(
        continuation: UnsafeContinuation<Element?, any Error>,
        element: Element,
        callbackToken: UInt64
      )
      /// Indicates that the producer has been finished.
      case throwFinishedError

      @inlinable
      init(
        callbackToken: UInt64?,
        continuationAndElement: (UnsafeContinuation<Element?, any Error>, Element)? = nil
      ) {
        switch (callbackToken, continuationAndElement) {
        case (.none, .none):
          self = .returnProduceMore

        case (.some(let callbackToken), .none):
          self = .returnEnqueue(callbackToken: callbackToken)

        case (.none, .some((let continuation, let element))):
          self = .resumeConsumerAndReturnProduceMore(
            continuation: continuation,
            element: element
          )

        case (.some(let callbackToken), .some((let continuation, let element))):
          self = .resumeConsumerAndReturnEnqueue(
            continuation: continuation,
            element: element,
            callbackToken: callbackToken
          )
        }
      }
    }

    @inlinable
    mutating func send(_ sequence: sending some Sequence<Element>) -> SendAction {
      switch self._state {
      case .channeling(var channeling):
        // We have an element and can resume the continuation
        let bufferEndIndexBeforeAppend = channeling.buffer.endIndex
        channeling.buffer.append(contentsOf: sequence)
        var shouldProduceMore = channeling.backpressureStrategy.didSend(
          elements: channeling.buffer[bufferEndIndexBeforeAppend...]
        )
        channeling.hasOutstandingDemand = shouldProduceMore

        guard let consumerContinuation = channeling.consumerContinuation else {
          // We don't have a suspended consumer so we just buffer the elements
          let callbackToken = shouldProduceMore ? nil : channeling.nextCallbackToken()
          self = .init(state: .channeling(channeling))

          return .init(
            callbackToken: callbackToken
          )
        }
        guard let element = channeling.buffer.popFirst() else {
          // We got a send of an empty sequence. We just tolerate this.
          let callbackToken = shouldProduceMore ? nil : channeling.nextCallbackToken()
          self = .init(state: .channeling(channeling))

          return .init(callbackToken: callbackToken)
        }
        // We need to tell the back pressure strategy that we consumed
        shouldProduceMore = channeling.backpressureStrategy.didConsume(element: element)
        channeling.hasOutstandingDemand = shouldProduceMore

        // We got a consumer continuation and an element. We can resume the consumer now
        channeling.consumerContinuation = nil
        let callbackToken = shouldProduceMore ? nil : channeling.nextCallbackToken()
        self = .init(state: .channeling(channeling))

        return .init(
          callbackToken: callbackToken,
          continuationAndElement: (consumerContinuation, element)
        )

      case .sourceFinished(let sourceFinished):
        // If the source has finished we are dropping the elements.
        self = .init(state: .sourceFinished(sourceFinished))

        return .throwFinishedError

      case .finished(let finished):
        // If the source has finished we are dropping the elements.
        self = .init(state: .finished(finished))

        return .throwFinishedError
      }
    }

    /// Actions returned by `enqueueProducer()`.
    @usableFromInline
    enum EnqueueProducerAction {
      /// Indicates that the producer should be notified to produce more.
      case resumeProducer((Result<Void, any Error>) -> Void)
      /// Indicates that the producer should be notified about an error.
      case resumeProducerWithError((Result<Void, any Error>) -> Void, any Error)
    }

    @inlinable
    mutating func enqueueProducer(
      callbackToken: UInt64,
      onProduceMore: sending @escaping (Result<Void, any Error>) -> Void
    ) -> EnqueueProducerAction? {
      switch self._state {
      case .channeling(var channeling):
        if let index = channeling.cancelledAsyncProducers.firstIndex(of: callbackToken) {
          // Our producer got marked as cancelled.
          channeling.cancelledAsyncProducers.remove(at: index)
          self = .init(state: .channeling(channeling))

          return .resumeProducerWithError(onProduceMore, CancellationError())
        } else if channeling.hasOutstandingDemand {
          // We hit an edge case here where we wrote but the consuming thread got interleaved
          self = .init(state: .channeling(channeling))

          return .resumeProducer(onProduceMore)
        } else {
          channeling.suspendedProducers.append((callbackToken, .closure(onProduceMore)))
          self = .init(state: .channeling(channeling))

          return .none
        }

      case .sourceFinished(let sourceFinished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .sourceFinished(sourceFinished))

        return .resumeProducerWithError(onProduceMore, MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())

      case .finished(let finished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .finished(finished))

        return .resumeProducerWithError(onProduceMore, MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
      }
    }

    /// Actions returned by `enqueueContinuation()`.
    @usableFromInline
    enum EnqueueContinuationAction {
      /// Indicates that the producer should be notified to produce more.
      case resumeProducer(UnsafeContinuation<Void, any Error>)
      /// Indicates that the producer should be notified about an error.
      case resumeProducerWithError(UnsafeContinuation<Void, any Error>, any Error)
    }

    @inlinable
    mutating func enqueueContinuation(
      callbackToken: UInt64,
      continuation: UnsafeContinuation<Void, any Error>
    ) -> EnqueueContinuationAction? {
      switch self._state {
      case .channeling(var channeling):
        if let index = channeling.cancelledAsyncProducers.firstIndex(of: callbackToken) {
          // Our producer got marked as cancelled.
          channeling.cancelledAsyncProducers.remove(at: index)
          self = .init(state: .channeling(channeling))

          return .resumeProducerWithError(continuation, CancellationError())
        } else if channeling.hasOutstandingDemand {
          // We hit an edge case here where we wrote but the consuming thread got interleaved
          self = .init(state: .channeling(channeling))

          return .resumeProducer(continuation)
        } else {
          channeling.suspendedProducers.append((callbackToken, .continuation(continuation)))
          self = .init(state: .channeling(channeling))

          return .none
        }

      case .sourceFinished(let sourceFinished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .sourceFinished(sourceFinished))

        return .resumeProducerWithError(continuation, MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())

      case .finished(let finished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .finished(finished))

        return .resumeProducerWithError(continuation, MultiProducerSingleConsumerAsyncChannelAlreadyFinishedError())
      }
    }

    /// Actions returned by `cancelProducer()`.
    @usableFromInline
    enum CancelProducerAction {
      /// Indicates that the producer should be notified about cancellation.
      case resumeProducerWithCancellationError(_MultiProducerSingleConsumerSuspendedProducer)
    }

    @inlinable
    mutating func cancelProducer(
      callbackToken: UInt64
    ) -> CancelProducerAction? {
      switch self._state {
      case .channeling(var channeling):
        guard let index = channeling.suspendedProducers.firstIndex(where: { $0.0 == callbackToken }) else {
          // The task that sends was cancelled before sending elements so the cancellation handler
          // got invoked right away
          channeling.cancelledAsyncProducers.append(callbackToken)
          self = .init(state: .channeling(channeling))

          return .none
        }
        // We have an enqueued producer that we need to resume now
        let continuation = channeling.suspendedProducers.remove(at: index).1
        self = .init(state: .channeling(channeling))

        return .resumeProducerWithCancellationError(continuation)

      case .sourceFinished(let sourceFinished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .sourceFinished(sourceFinished))

        return .none

      case .finished(let finished):
        // Since we are unlocking between sending elements and suspending the send
        // It can happen that the source got finished or the consumption fully finishes.
        self = .init(state: .finished(finished))

        return .none
      }
    }

    /// Actions returned by `finish()`.
    @usableFromInline
    enum FinishAction {
      /// Indicates that `onTermination` should be called.
      case callOnTermination((() -> Void)?)
      /// Indicates that the consumer  should be resumed with the failure, the producers
      /// should be resumed with an error and `onTermination` should be called.
      case resumeConsumerAndCallOnTermination(
        consumerContinuation: UnsafeContinuation<Element?, any Error>,
        failure: Failure?,
        onTermination: (() -> Void)?
      )
      /// Indicates that the producers should be resumed with an error.
      case resumeProducers(
        producerContinuations: _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>
      )
    }

    @inlinable
    mutating func finish(_ failure: Failure?) -> FinishAction? {
      switch self._state {
      case .channeling(let channeling):
        guard let consumerContinuation = channeling.consumerContinuation else {
          // We don't have a suspended consumer so we are just going to mark
          // the source as finished and terminate the current suspended producers.
          self = .init(
            state: .sourceFinished(
              .init(
                iteratorInitialized: channeling.iteratorInitialized,
                sequenceInitialized: channeling.sequenceInitialized,
                buffer: channeling.buffer,
                failure: failure,
                onTermination: channeling.onTermination
              )
            )
          )

          return .resumeProducers(
            producerContinuations: .init(channeling.suspendedProducers.lazy.map { $0.1 })
          )
        }
        // We have a continuation, this means our buffer must be empty
        // Furthermore, we can now transition to finished
        // and resume the continuation with the failure
        precondition(channeling.buffer.isEmpty, "Expected an empty buffer")

        self = .init(
          state: .finished(
            .init(
              iteratorInitialized: channeling.iteratorInitialized,
              sequenceInitialized: channeling.sequenceInitialized,
              sourceFinished: true
            )
          )
        )

        return .resumeConsumerAndCallOnTermination(
          consumerContinuation: consumerContinuation,
          failure: failure,
          onTermination: channeling.onTermination
        )

      case .sourceFinished(let sourceFinished):
        // If the source has finished, finishing again has no effect.
        self = .init(state: .sourceFinished(sourceFinished))

        return .none

      case .finished(var finished):
        finished.sourceFinished = true
        self = .init(state: .finished(finished))
        return .none
      }
    }

    /// Actions returned by `next()`.
    @usableFromInline
    enum NextAction {
      /// Indicates that the element should be returned to the caller.
      case returnElement(Element)
      /// Indicates that the element should be returned to the caller and that all producers should be called.
      case returnElementAndResumeProducers(Element, _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>)
      /// Indicates that the `Failure` should be returned to the caller and that `onTermination` should be called.
      case returnFailureAndCallOnTermination(Failure?, (() -> Void)?)
      /// Indicates that the `nil` should be returned to the caller.
      case returnNil
      /// Indicates that the `Task` of the caller should be suspended.
      case suspendTask
    }

    @inlinable
    mutating func next() -> NextAction {
      switch self._state {
      case .channeling(var channeling):
        guard channeling.consumerContinuation == nil else {
          // We have multiple AsyncIterators iterating the sequence
          fatalError("MultiProducerSingleConsumerAsyncChannel internal inconsistency")
        }

        guard let element = channeling.buffer.popFirst() else {
          // There is nothing in the buffer to fulfil the demand so we need to suspend.
          // We are not interacting with the backpressure strategy here because
          // we are doing this inside `suspendNext`
          self = .init(state: .channeling(channeling))

          return .suspendTask
        }
        // We have an element to fulfil the demand right away.
        let shouldProduceMore = channeling.backpressureStrategy.didConsume(element: element)
        channeling.hasOutstandingDemand = shouldProduceMore

        guard shouldProduceMore else {
          // We don't have any new demand, so we can just return the element.
          self = .init(state: .channeling(channeling))

          return .returnElement(element)
        }
        // There is demand and we have to resume our producers
        let producers = _TinyArray(channeling.suspendedProducers.lazy.map { $0.1 })
        channeling.suspendedProducers.removeAll(keepingCapacity: true)
        self = .init(state: .channeling(channeling))

        return .returnElementAndResumeProducers(element, producers)

      case .sourceFinished(var sourceFinished):
        // Check if we have an element left in the buffer and return it
        guard let element = sourceFinished.buffer.popFirst() else {
          // We are returning the queued failure now and can transition to finished
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: sourceFinished.iteratorInitialized,
                sequenceInitialized: sourceFinished.sequenceInitialized,
                sourceFinished: true
              )
            )
          )

          return .returnFailureAndCallOnTermination(sourceFinished.failure, sourceFinished.onTermination)
        }
        self = .init(state: .sourceFinished(sourceFinished))

        return .returnElement(element)

      case .finished(let finished):
        self = .init(state: .finished(finished))

        return .returnNil
      }
    }

    /// Actions returned by `suspendNext()`.
    @usableFromInline
    enum SuspendNextAction {
      /// Indicates that the consumer should be resumed.
      case resumeConsumerWithElement(UnsafeContinuation<Element?, any Error>, Element)
      /// Indicates that the consumer and all producers should be resumed.
      case resumeConsumerWithElementAndProducers(
        UnsafeContinuation<Element?, any Error>,
        Element,
        _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>
      )
      /// Indicates that the consumer should be resumed with the failure and that `onTermination` should be called.
      case resumeConsumerWithFailureAndCallOnTermination(
        UnsafeContinuation<Element?, any Error>,
        Failure?,
        (() -> Void)?
      )
      /// Indicates that the consumer should be resumed with `nil`.
      case resumeConsumerWithNil(UnsafeContinuation<Element?, any Error>)
    }

    @inlinable
    mutating func suspendNext(continuation: UnsafeContinuation<Element?, any Error>) -> SuspendNextAction? {
      switch self._state {
      case .channeling(var channeling):
        guard channeling.consumerContinuation == nil else {
          // We have multiple AsyncIterators iterating the sequence
          fatalError("MultiProducerSingleConsumerAsyncChannel internal inconsistency")
        }

        // We have to check here again since we might have a producer interleave next and suspendNext
        guard let element = channeling.buffer.popFirst() else {
          // There is nothing in the buffer to fulfil the demand so we to store the continuation.
          channeling.consumerContinuation = continuation
          self = .init(state: .channeling(channeling))

          return .none
        }
        // We have an element to fulfil the demand right away.

        let shouldProduceMore = channeling.backpressureStrategy.didConsume(element: element)
        channeling.hasOutstandingDemand = shouldProduceMore

        guard shouldProduceMore else {
          // We don't have any new demand, so we can just return the element.
          self = .init(state: .channeling(channeling))

          return .resumeConsumerWithElement(continuation, element)
        }
        // There is demand and we have to resume our producers
        let producers = _TinyArray(channeling.suspendedProducers.lazy.map { $0.1 })
        channeling.suspendedProducers.removeAll(keepingCapacity: true)
        self = .init(state: .channeling(channeling))

        return .resumeConsumerWithElementAndProducers(continuation, element, producers)

      case .sourceFinished(var sourceFinished):
        // Check if we have an element left in the buffer and return it
        guard let element = sourceFinished.buffer.popFirst() else {
          // We are returning the queued failure now and can transition to finished
          self = .init(
            state: .finished(
              .init(
                iteratorInitialized: sourceFinished.iteratorInitialized,
                sequenceInitialized: sourceFinished.sequenceInitialized,
                sourceFinished: true
              )
            )
          )

          return .resumeConsumerWithFailureAndCallOnTermination(
            continuation,
            sourceFinished.failure,
            sourceFinished.onTermination
          )
        }
        self = .init(state: .sourceFinished(sourceFinished))

        return .resumeConsumerWithElement(continuation, element)

      case .finished(let finished):
        self = .init(state: .finished(finished))

        return .resumeConsumerWithNil(continuation)
      }
    }

    /// Actions returned by `cancelNext()`.
    @usableFromInline
    enum CancelNextAction {
      /// Indicates that the continuation should be resumed with nil, the producers should be finished and call onTermination.
      case resumeConsumerWithNilAndCallOnTermination(UnsafeContinuation<Element?, any Error>, (() -> Void)?)
      /// Indicates that the producers should be finished and call onTermination.
      case failProducersAndCallOnTermination(
        _TinyArray<_MultiProducerSingleConsumerSuspendedProducer>,
        (() -> Void)?
      )
    }

    @inlinable
    mutating func cancelNext() -> CancelNextAction? {
      switch self._state {
      case .channeling(let channeling):
        self = .init(
          state: .finished(
            .init(
              iteratorInitialized: channeling.iteratorInitialized,
              sequenceInitialized: channeling.sequenceInitialized,
              sourceFinished: false
            )
          )
        )

        guard let consumerContinuation = channeling.consumerContinuation else {
          return .failProducersAndCallOnTermination(
            .init(channeling.suspendedProducers.lazy.map { $0.1 }),
            channeling.onTermination
          )
        }
        precondition(
          channeling.suspendedProducers.isEmpty,
          "Internal inconsistency. Unexpected producer continuations."
        )
        return .resumeConsumerWithNilAndCallOnTermination(
          consumerContinuation,
          channeling.onTermination
        )

      case .sourceFinished(let sourceFinished):
        self = .init(state: .sourceFinished(sourceFinished))

        return .none

      case .finished(let finished):
        self = .init(state: .finished(finished))

        return .none
      }
    }
  }
}

extension MultiProducerSingleConsumerAsyncChannel._Storage._StateMachine {
  @usableFromInline
  enum _State {
    @usableFromInline
    struct Channeling {
      /// The backpressure strategy.
      @usableFromInline
      var backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy

      /// Indicates if the iterator was initialized.
      @usableFromInline
      var iteratorInitialized: Bool

      /// Indicates if an async sequence was initialized.
      @usableFromInline
      var sequenceInitialized: Bool

      /// The onTermination callback.
      @usableFromInline
      var onTermination: (@Sendable () -> Void)?

      /// The buffer of elements.
      @usableFromInline
      var buffer: Deque<Element>

      /// The optional consumer continuation.
      @usableFromInline
      var consumerContinuation: UnsafeContinuation<Element?, any Error>?

      /// The producer continuations.
      @usableFromInline
      var suspendedProducers: Deque<(UInt64, _MultiProducerSingleConsumerSuspendedProducer)>

      /// The producers that have been cancelled.
      @usableFromInline
      var cancelledAsyncProducers: Deque<UInt64>

      /// Indicates if we currently have outstanding demand.
      @usableFromInline
      var hasOutstandingDemand: Bool

      /// The number of active producers.
      @usableFromInline
      var activeProducers: UInt64

      /// The next callback token.
      @usableFromInline
      var nextCallbackTokenID: UInt64

      var description: String {
        "backpressure:\(self.backpressureStrategy.description) iteratorInitialized:\(self.iteratorInitialized) buffer:\(self.buffer.count) consumerContinuation:\(self.consumerContinuation == nil) producerContinuations:\(self.suspendedProducers.count) cancelledProducers:\(self.cancelledAsyncProducers.count) hasOutstandingDemand:\(self.hasOutstandingDemand)"
      }

      @inlinable
      init(
        backpressureStrategy: MultiProducerSingleConsumerAsyncChannel._InternalBackpressureStrategy,
        iteratorInitialized: Bool,
        sequenceInitialized: Bool,
        onTermination: (@Sendable () -> Void)? = nil,
        buffer: Deque<Element>,
        consumerContinuation: UnsafeContinuation<Element?, any Error>? = nil,
        producerContinuations: Deque<(UInt64, _MultiProducerSingleConsumerSuspendedProducer)>,
        cancelledAsyncProducers: Deque<UInt64>,
        hasOutstandingDemand: Bool,
        activeProducers: UInt64,
        nextCallbackTokenID: UInt64
      ) {
        self.backpressureStrategy = backpressureStrategy
        self.iteratorInitialized = iteratorInitialized
        self.sequenceInitialized = sequenceInitialized
        self.onTermination = onTermination
        self.buffer = buffer
        self.consumerContinuation = consumerContinuation
        self.suspendedProducers = producerContinuations
        self.cancelledAsyncProducers = cancelledAsyncProducers
        self.hasOutstandingDemand = hasOutstandingDemand
        self.activeProducers = activeProducers
        self.nextCallbackTokenID = nextCallbackTokenID
      }

      /// Generates the next callback token.
      @inlinable
      mutating func nextCallbackToken() -> UInt64 {
        let id = self.nextCallbackTokenID
        self.nextCallbackTokenID += 1
        return id
      }
    }

    @usableFromInline
    struct SourceFinished {
      /// Indicates if the iterator was initialized.
      @usableFromInline
      var iteratorInitialized: Bool

      /// Indicates if an async sequence was initialized.
      @usableFromInline
      var sequenceInitialized: Bool

      /// The buffer of elements.
      @usableFromInline
      var buffer: Deque<Element>

      /// The failure that should be thrown after the last element has been consumed.
      @usableFromInline
      var failure: Failure?

      /// The onTermination callback.
      @usableFromInline
      var onTermination: (@Sendable () -> Void)?

      var description: String {
        "iteratorInitialized:\(self.iteratorInitialized) buffer:\(self.buffer.count) failure:\(self.failure == nil)"
      }

      @inlinable
      init(
        iteratorInitialized: Bool,
        sequenceInitialized: Bool,
        buffer: Deque<Element>,
        failure: Failure? = nil,
        onTermination: (@Sendable () -> Void)? = nil
      ) {
        self.iteratorInitialized = iteratorInitialized
        self.sequenceInitialized = sequenceInitialized
        self.buffer = buffer
        self.failure = failure
        self.onTermination = onTermination
      }
    }

    @usableFromInline
    struct Finished {
      /// Indicates if the iterator was initialized.
      @usableFromInline
      var iteratorInitialized: Bool

      /// Indicates if an async sequence was initialized.
      @usableFromInline
      var sequenceInitialized: Bool

      /// Indicates if the source was finished.
      @usableFromInline
      var sourceFinished: Bool

      var description: String {
        "iteratorInitialized:\(self.iteratorInitialized) sourceFinished:\(self.sourceFinished)"
      }

      @inlinable
      init(
        iteratorInitialized: Bool,
        sequenceInitialized: Bool,
        sourceFinished: Bool
      ) {
        self.iteratorInitialized = iteratorInitialized
        self.sequenceInitialized = sequenceInitialized
        self.sourceFinished = sourceFinished
      }
    }

    /// The state once either any element was sent or `next()` was called.
    case channeling(Channeling)

    /// The state once the underlying source signalled that it is finished.
    case sourceFinished(SourceFinished)

    /// The state once there can be no outstanding demand. This can happen if:
    /// 1. The iterator was deinited
    /// 2. The underlying source finished and all buffered elements have been consumed
    case finished(Finished)

    @usableFromInline
    var description: String {
      switch self {
      case .channeling(let channeling):
        return "channeling \(channeling.description)"
      case .sourceFinished(let sourceFinished):
        return "sourceFinished \(sourceFinished.description)"
      case .finished(let finished):
        return "finished \(finished.description)"
      }
    }
  }
}

@usableFromInline
enum _MultiProducerSingleConsumerSuspendedProducer {
  case closure((Result<Void, any Error>) -> Void)
  case continuation(UnsafeContinuation<Void, any Error>)
}
#endif
