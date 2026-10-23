import SwiftData
import XCTest
@testable import RecallRx

final class MedicalWorkflowRegressionTests: XCTestCase {
    func testClozePromptHidesAnswerAndHintAndGradesTheDeletion() throws {
        let content = try XCTUnwrap(AudioStudyContent.make(
            front: "The toxin blocks {{c1::acetylcholine::neurotransmitter}} release.",
            back: "This is an explanatory note, not the answer.",
            noteType: .cloze
        ))
        XCTAssertEqual(content.question, "The toxin blocks blank release.")
        XCTAssertFalse(content.question.contains("acetylcholine"))
        XCTAssertFalse(content.question.contains("neurotransmitter"))
        XCTAssertEqual(content.expectedAnswers, ["acetylcholine"])
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "acetylcholine", expectedAnswers: content.expectedAnswers).rating, 2)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "explanatory note", expectedAnswers: content.expectedAnswers).rating, 0)
    }

    func testMedicalClozeDoesNotRequireAnOptionalBackField() throws {
        let content = try XCTUnwrap(AudioStudyContent.make(front: "SIADH increases {{c1::ADH}}.", back: "", noteType: .medical))
        XCTAssertEqual(content.question, "SIADH increases blank.")
        XCTAssertEqual(content.expectedAnswer, "ADH")
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "ADH", expectedAnswers: content.expectedAnswers).rating, 2)
    }

    func testMultipleBlanksMustAllBeRecalledForGood() throws {
        let content = try XCTUnwrap(AudioStudyContent.make(front: "PTH raises {{c1::calcium}} and lowers {{c2::phosphate}}.", back: "", noteType: .medical))
        XCTAssertEqual(content.expectedAnswers, ["calcium", "phosphate"])
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "calcium", expectedAnswers: content.expectedAnswers).rating, 1)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "calcium and phosphate", expectedAnswers: content.expectedAnswers).rating, 2)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "sodium", expectedAnswers: content.expectedAnswers).rating, 0)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "", expectedAnswers: content.expectedAnswers).rating, 0)
    }

    func testAudioRejectsVisualMalformedAndUnansweredNotes() {
        XCTAssertNil(AudioStudyContent.make(front: "Identify the structure", back: "artery", noteType: .imageOcclusion))
        XCTAssertNil(AudioStudyContent.make(front: "Identify this <img src='slide.png'>", back: "artery", noteType: .basic))
        XCTAssertNil(AudioStudyContent.make(front: "Question", back: "", noteType: .basic))
        XCTAssertNil(AudioStudyContent.make(front: "Question", back: "", noteType: .medical))
        XCTAssertNil(AudioStudyContent.make(front: "No deletion here", back: "answer", noteType: .cloze))
        XCTAssertNil(AudioStudyContent.make(front: "Nested {{c1::outer {{c2::secret}}}}", back: "", noteType: .cloze))
        XCTAssertNil(AudioStudyContent.make(front: "Empty {{c1::::hint}}", back: "", noteType: .cloze))
        XCTAssertNil(AudioStudyContent.make(front: String(repeating: "long ", count: 50), back: "answer", noteType: .basic))
    }

    func testSpeechSanitizerMasksUppercaseAndEncodedDeletions() throws {
        XCTAssertEqual(AudioStudyContent.sanitize("Cause: {{C1::SIADH::SIADH}}"), "Cause: blank")
        let encoded = try XCTUnwrap(AudioStudyContent.make(front: "Cause: &#123;&#123;c1::SIADH&#125;&#125;", back: "", noteType: .medical))
        XCTAssertEqual(encoded.question, "Cause: blank")
        XCTAssertEqual(encoded.expectedAnswer, "SIADH")
    }

    func testMedicalAnswersAreNotMistakenForVoiceCommandsOrSurrender() {
        XCTAssertNil(AudioStudyAnswerEvaluator.voiceCommand(in: "stop bacterial protein synthesis"))
        XCTAssertNil(AudioStudyAnswerEvaluator.voiceCommand(in: "repeat expansion mutation"))
        XCTAssertEqual(AudioStudyAnswerEvaluator.voiceCommand(in: "could you repeat that please"), .repeatQuestion)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "coronary bypass", expectedAnswers: ["coronary bypass"]).rating, 2)
        XCTAssertEqual(AudioStudyAnswerEvaluator.evaluate(spoken: "5", expectedAnswers: ["5"]).rating, 2)
        for spoken in ["", "i don't know", "pass", "wrong", "ADH"] {
            XCTAssertNotEqual(AudioStudyAnswerEvaluator.evaluate(spoken: spoken, expectedAnswers: ["ADH"]).rating, 3)
        }
    }

    func testQuestionIDPrefixCollisionsDoNotMatchTagsOrContent() {
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: nil, tags: ["#UWorld::Step1::QID_1234"], front: "", back: ""))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: nil, tags: [], front: "QID: 1234", back: "QID_123abc"))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: ["#UWorld::Step1::QID_123"], front: "", back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: ["#UWorld::123"], front: "", back: ""))
    }

    func testQuestionIDSourceIsEnforcedForContentFallback() {
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: ["AMBOSS"], front: "QID: 123", back: ""))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: "amboss", tags: ["UWorld"], front: "", back: "QID_123"))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: [], front: "QID: 123", back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: nil, tags: [], front: "QID: 123", back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "amboss", tags: ["AMBOSS"], front: "", back: "QID: 123"))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: ["UWorld", "QID_123"], front: "", back: ""))
    }

    func testMixedSourcesAttributeEachExplicitQuestionID() {
        let content = "AMBOSS QID: 123, UWorld QID: 1234"
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: [], front: content, back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "amboss", tags: [], front: content, back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "1234", source: "uworld", tags: [], front: content, back: ""))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "1234", source: "amboss", tags: [], front: content, back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "123", source: "amboss", tags: [], front: "QID: 123 (AMBOSS)", back: ""))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "1234", source: "uworld", tags: [], front: "UWorld QID: 123, QID: 1234 (AMBOSS)", back: ""))
        XCTAssertTrue(QuestionIDMatcher.matches(qid: "1234", source: "amboss", tags: [], front: "UWorld QID: 123, QID: 1234 (AMBOSS)", back: ""))
        XCTAssertFalse(QuestionIDMatcher.matches(qid: "123", source: "uworld", tags: [], front: "QID: 123, UWorld QID: 1234", back: ""))
    }

    func testSourceQualifiedInputIsNormalizedAndDeduplicated() {
        XCTAssertEqual(QuestionIDMatcher.parseInput("123, QID_123; qid:1234\n#UWorld::Step1::QID_777 AMBOSS_ABC12"), ["123", "1234", "777", "abc12"])
    }

    @MainActor
    func testQBankSearchUsesExactSourceAwareMatchesInAnInMemoryLibrary() throws {
        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let deck = Deck(name: "Isolated medical workflow test")
        context.insert(deck)
        let correct = Card(front: "QID: 123", back: "answer", deck: deck, tags: ["UWorld"])
        let prefixCollision = Card(front: "QID: 1234", back: "answer", deck: deck, tags: ["UWorld"])
        let wrongSource = Card(front: "QID: 123", back: "answer", deck: deck, tags: ["AMBOSS"])
        for card in [correct, prefixCollision, wrongSource] { context.insert(card) }
        try context.save()
        let model = QBankViewModel(modelContext: context)
        model.rawInput = "123"
        model.selectedSource = .uworld
        model.searchQIDs()
        XCTAssertEqual(model.allMatchedCards.map(\.id), [correct.id])
        model.selectedSource = .amboss
        model.searchQIDs()
        XCTAssertEqual(model.allMatchedCards.map(\.id), [wrongSource.id])
    }
}
