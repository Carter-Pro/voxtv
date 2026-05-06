import Testing
@testable import Voxtv

struct WakePipelineTests {
    @Test func testInitialState() {
        let pipeline = WakePipeline(
            spotter: nil, speech: nil, bridge: nil,
            dispatcher: nil, prompt: nil, feedback: nil
        )
        #expect(pipeline.state == .idle)
    }

    @Test func testConfigDefaults() {
        let pipeline = WakePipeline(
            spotter: nil, speech: nil, bridge: nil,
            dispatcher: nil, prompt: nil, feedback: nil
        )
        #expect(pipeline.promptType == "beep")
        #expect(pipeline.promptText == "请说")
        #expect(pipeline.feedbackEnabled == true)
        #expect(pipeline.recognitionTimeout == 8.0)
        #expect(pipeline.cooldownDuration == 3.0)
    }

    @Test func testCooldownTransitions() {
        let pipeline = WakePipeline(
            spotter: nil, speech: nil, bridge: nil,
            dispatcher: nil, prompt: nil, feedback: nil
        )
        pipeline.startCooldown(duration: 0.05)
        #expect(pipeline.state == .cooldown)
    }

    @Test func testStateChangeCallback() {
        final class StateCollector: @unchecked Sendable {
            var states: [PipelineState] = []
        }
        let pipeline = WakePipeline(
            spotter: nil, speech: nil, bridge: nil,
            dispatcher: nil, prompt: nil, feedback: nil
        )
        let collector = StateCollector()
        pipeline.onStateChange = { collector.states.append($0) }
        pipeline.startCooldown(duration: 0.05)
        #expect(collector.states.contains(.cooldown))
    }
}
