import XCTest
@testable import LinguAlyzer

final class ArabicNLPTests: XCTestCase {

    // MARK: normalize

    func testNormalizeStripsDefiniteArticleAndHamza() {
        XCTAssertEqual(ArabicText.normalize("الإعدادات"), "اعدادات")
        XCTAssertEqual(ArabicText.normalize("إعدادات"), "اعدادات")
        XCTAssertEqual(ArabicText.normalize("بالإعدادات"), "اعدادات")
        XCTAssertEqual(ArabicText.normalize("للإعدادات"), "اعدادات")
    }

    func testNormalizeStripsTashkeelAndUnifiesEndings() {
        XCTAssertEqual(ArabicText.normalize("الخُصُوصِيَّة"), ArabicText.normalize("الخصوصية"))
        XCTAssertEqual(ArabicText.normalize("متابعة"), "متابعه")
        XCTAssertEqual(ArabicText.normalize("مستوى"), "مستوي")
    }

    // MARK: contains(term:in:)

    func testGlossaryTermMatchesSpellingVariants() {
        XCTAssertTrue(ArabicText.contains(term: "الإعدادات", in: "انتقل إلى إعدادات الجهاز"))
        XCTAssertTrue(ArabicText.contains(term: "الإعدادات", in: "تحكم بالإعدادات من هنا"))
        XCTAssertTrue(ArabicText.contains(term: "الإعدادات", in: "افتح التطبيق وإعدادات الحساب"))
    }

    func testMultiWordTermWithTashkeel() {
        XCTAssertTrue(ArabicText.contains(term: "سياسة الخصوصية", in: "اقرأ سياسةَ الخصوصيةِ قبل المتابعة"))
    }

    func testMissingTermIsNotMatched() {
        XCTAssertFalse(ArabicText.contains(term: "الحساب", in: "انتقل إلى الإعدادات"))
        XCTAssertFalse(ArabicText.contains(term: "سياسة الخصوصية", in: "الخصوصية سياسة"))
    }

    // MARK: language and sentences

    func testDetectsArabicAndEnglish() {
        XCTAssertEqual(ArabicText.dominantLanguage("انتقل إلى الإعدادات لتحديث تفضيلات الخصوصية").language, .arabic)
        XCTAssertEqual(ArabicText.dominantLanguage("Go to Settings to update your privacy preferences").language, .english)
    }

    func testSentenceCount() {
        XCTAssertEqual(ArabicText.sentenceCount("Your files were backed up. Tap Continue to review the new items."), 2)
        XCTAssertEqual(ArabicText.sentenceCount("تم نسخ ملفاتك. اضغط متابعة لمراجعة العناصر الجديدة."), 2)
    }

    // MARK: Analyzer integration

    func testAnalyzerNoLongerFlagsTermWithoutArticle() {
        let glossary = [GlossaryTerm(english: "settings", arabic: "الإعدادات")]
        let review = Analyzer.review(source: "Open Settings on your device.",
                                     target: "افتح إعدادات جهازك.",
                                     glossary: glossary)
        XCTAssertFalse(review.findings.contains { $0.category == "Terminology" })
    }

    func testAnalyzerStillFlagsMissingTerm() {
        let glossary = [GlossaryTerm(english: "account", arabic: "الحساب")]
        let review = Analyzer.review(source: "Delete your account.",
                                     target: "احذف ملفك الشخصي.",
                                     glossary: glossary)
        XCTAssertTrue(review.findings.contains { $0.category == "Terminology" })
    }

    func testAnalyzerFlagsEnglishTarget() {
        let review = Analyzer.review(source: "Go to Settings to update your privacy preferences.",
                                     target: "Go to Settings to update your privacy preferences.",
                                     glossary: [])
        XCTAssertTrue(review.findings.contains { $0.category == "Language" })
    }

    func testAnalyzerFlagsMissingSentence() {
        let review = Analyzer.review(source: "Your files were backed up. Tap Continue to review the new items.",
                                     target: "تم نسخ ملفاتك احتياطيًا.",
                                     glossary: [])
        XCTAssertTrue(review.findings.contains { $0.category == "Sentences" })
    }

    func testSampleTextHasNoNewFalseAlarms() {
        let review = Analyzer.review(source: "Go to Settings to update your privacy preferences, then select Continue.",
                                     target: "انتقل إلى الإعدادات لتحديث تفضيلات الخصوصية، ثم اختر متابعة.",
                                     glossary: [GlossaryTerm(english: "settings", arabic: "الإعدادات"),
                                                GlossaryTerm(english: "privacy", arabic: "الخصوصية"),
                                                GlossaryTerm(english: "continue", arabic: "متابعة")])
        XCTAssertFalse(review.findings.contains { ["Terminology", "Language", "Sentences"].contains($0.category) },
                       "Unexpected findings: \(review.findings.map(\.title))")
    }
}
