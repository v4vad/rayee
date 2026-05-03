//
//  MLXTransformManagerTests.swift
//  RayeeTests
//

import XCTest
@testable import Rayee

final class MLXTransformManagerTests: XCTestCase {

    func testBuildPromptGrammar() {
        let (system, user) = MLXTransformManager.buildPrompt(text: "hello world", type: .grammar)
        XCTAssertTrue(system.contains("transformation assistant"))
        XCTAssertTrue(user.contains("hello world"))
        XCTAssertTrue(user.contains("grammar"))
    }

    func testBuildPromptBullets() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "item one item two", type: .bullets)
        XCTAssertTrue(user.contains("bullet"))
        XCTAssertTrue(user.contains("item one item two"))
    }

    func testBuildPromptFormal() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "hey what's up", type: .formal)
        XCTAssertTrue(user.contains("formal"))
    }

    func testBuildPromptCasual() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "Please be advised", type: .casual)
        XCTAssertTrue(user.contains("casual"))
    }

    func testBuildPromptRephrase() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "The quick brown fox", type: .rephrase)
        XCTAssertTrue(user.contains("clearer"))
    }
}
