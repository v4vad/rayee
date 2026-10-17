import XCTest
@testable import Rayee

final class OnboardingRulesTests: XCTestCase {
    private let nothing = OnboardingInput(microphoneAllowed: false, accessibilityAllowed: false, speechModelReady: false)
    private let everything = OnboardingInput(microphoneAllowed: true, accessibilityAllowed: true, speechModelReady: true)

    func testStepsInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .microphone, .accessibility, .speechModel, .tryIt])
        XCTAssertEqual(OnboardingRules.next(.welcome), .microphone)
        XCTAssertNil(OnboardingRules.next(.tryIt))
        XCTAssertNil(OnboardingRules.previous(.welcome))
        XCTAssertEqual(OnboardingRules.previous(.tryIt), .speechModel)
    }

    func testMicrophoneMustBeAllowedToGoOn() {
        XCTAssertFalse(OnboardingRules.canContinue(.microphone, nothing))
        XCTAssertTrue(OnboardingRules.canContinue(.microphone, everything))
    }

    func testAccessibilityCanBeSkipped() {
        XCTAssertTrue(OnboardingRules.canContinue(.accessibility, nothing))
        XCTAssertEqual(OnboardingRules.continueLabel(.accessibility, nothing), "Skip")
        XCTAssertEqual(OnboardingRules.continueLabel(.accessibility, everything), "Continue")
    }

    func testSpeechModelMustBeReady() {
        XCTAssertFalse(OnboardingRules.canContinue(.speechModel, nothing))
        XCTAssertTrue(OnboardingRules.canContinue(.speechModel, everything))
    }

    func testFirstAndLastButtons() {
        XCTAssertEqual(OnboardingRules.continueLabel(.welcome, nothing), "Get Started")
        XCTAssertEqual(OnboardingRules.continueLabel(.tryIt, nothing), "Finish")
        XCTAssertTrue(OnboardingRules.canContinue(.tryIt, nothing))
    }
}
