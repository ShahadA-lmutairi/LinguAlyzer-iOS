import SwiftUI
import UIKit
import NaturalLanguage

// MARK: - Theme

enum Theme {
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.19)
    static let forest = Color(red: 0.05, green: 0.35, blue: 0.30)
    static let mint = Color(red: 0.86, green: 0.94, blue: 0.90)
    static let canvas = Color(red: 0.965, green: 0.973, blue: 0.960)
    static let muted = Color(red: 0.39, green: 0.46, blue: 0.46)
    static let line = Color(red: 0.88, green: 0.91, blue: 0.88)
    static let card = Color.white
}

// MARK: - Models

enum Severity: String, Codable {
    case info, warning, critical

    var label: String {
        switch self {
        case .info: return "Note"
        case .warning: return "Review"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .info: return Theme.muted
        case .warning: return Color.orange
        case .critical: return Color.red
        }
    }
}

struct GlossaryTerm: Identifiable, Codable, Hashable {
    var id = UUID()
    var english: String
    var arabic: String
}

struct Finding: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: String
    var title: String
    var detail: String
    var severity: Severity
}

struct Suggestion: Identifiable, Codable, Hashable {
    var id = UUID()
    var original: String
    var replacement: String
    var reason: String
    var applicable: Bool
}

struct Review: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var source: String
    var target: String
    var score: Int
    var arabicPercent: Int
    var lengthRatio: Double
    var findings: [Finding]
    var suggestions: [Suggestion]

    func report(finalText: String?) -> String {
        var lines: [String] = []
        lines.append("LINGUALYZER - LOCALIZATION REVIEW")
        lines.append("Date: " + date.formatted(date: .long, time: .shortened))
        lines.append("")
        lines.append("Rule-based QA indicator: \(score)/100")
        lines.append("Arabic script share: \(arabicPercent)%")
        lines.append("Target/source length ratio: " + String(format: "%.2f", lengthRatio))
        lines.append("")
        lines.append("SOURCE")
        lines.append(source)
        lines.append("")
        lines.append("ARABIC TARGET")
        lines.append(target)
        lines.append("")
        lines.append("FINDINGS")
        if findings.isEmpty {
            lines.append("No automatic flags.")
        } else {
            for f in findings {
                lines.append("- [\(f.severity.label)] \(f.title): \(f.detail)")
            }
        }
        if let finalText = finalText, !finalText.isEmpty, finalText != target {
            lines.append("")
            lines.append("REVISED TARGET (accepted suggestions applied)")
            lines.append(finalText)
        }
        lines.append("")
        lines.append("Note: this is an automated screening aid, not a certification of translation quality. Meaning, tone and cultural fit need a human reviewer.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Arabic NLP

/// Arabic-aware text helpers built on Apple's NaturalLanguage framework.
/// Everything runs on the device.
enum ArabicText {
    private static let diacritics: ClosedRange<UInt32> = 0x064B...0x0652   // tashkeel
    private static let definitePrefixes = ["وبال", "وال", "بال", "فال", "كال", "لل", "ال"]
    private static let clitics: Set<Character> = ["و", "ب", "ل", "ف", "ك"]

    /// Normalizes one Arabic word so that spelling variants compare equal:
    /// removes tashkeel and tatweel, unifies alef forms, taa marbuta and alef maqsura,
    /// and strips a leading definite article (with its attached prepositions).
    static func normalize(_ word: String) -> String {
        let kept = word.unicodeScalars.filter { scalar in
            !diacritics.contains(scalar.value) && scalar.value != 0x0670 && scalar.value != 0x0640
        }
        var w = String(String.UnicodeScalarView(kept))
        w = w.replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression)
        if w.hasSuffix("ة") { w = String(w.dropLast()) + "ه" }
        if w.hasSuffix("ى") { w = String(w.dropLast()) + "ي" }
        for prefix in definitePrefixes where w.hasPrefix(prefix) && w.count - prefix.count >= 2 {
            w = String(w.dropFirst(prefix.count))
            break
        }
        return w
    }

    /// Splits text into words with NLTokenizer and normalizes each one.
    static func words(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = normalize(String(text[range]))
            if !w.isEmpty { result.append(w) }
            return true
        }
        return result
    }

    /// True when `term` (one or more words) appears in `text`, ignoring tashkeel,
    /// hamza forms, the definite article and one attached clitic (و ب ل ف ك).
    static func contains(term: String, in text: String) -> Bool {
        let termWords = words(term)
        guard !termWords.isEmpty else { return true }
        let textWords = words(text)
        guard textWords.count >= termWords.count else { return false }
        for start in 0...(textWords.count - termWords.count) {
            let window = (0..<termWords.count).allSatisfy { i in
                matches(textWords[start + i], termWords[i])
            }
            if window { return true }
        }
        return false
    }

    private static func matches(_ token: String, _ term: String) -> Bool {
        if token == term { return true }
        if let first = token.first, clitics.contains(first), token.count - 1 >= 2 {
            return normalize(String(token.dropFirst())) == term
        }
        return false
    }

    /// The most likely language of `text` and the recognizer's confidence (0...1).
    static func dominantLanguage(_ text: String) -> (language: NLLanguage?, confidence: Double) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return (nil, 0) }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return (language, confidence)
    }

    /// Number of sentences, using NLTokenizer.
    static func sentenceCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .filter { !text[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }
}

// MARK: - Analyzer

enum Analyzer {
    private struct Pattern {
        let bad: String
        let replacement: String
        let reason: String
    }

    private static let patterns: [Pattern] = [
        Pattern(bad: "عبرت عن قلق عميق على", replacement: "أعربت عن قلقها العميق إزاء",
                reason: "The usual diplomatic phrasing is «أعربت عن قلقها إزاء»."),
        Pattern(bad: "طلبت من كل الأطراف", replacement: "دعت جميع الأطراف",
                reason: "«دعت» fits formal and diplomatic register better than «طلبت»."),
        Pattern(bad: "تمارس ضبط النفس", replacement: "تلتزم ضبط النفس",
                reason: "The common collocation is «التزام ضبط النفس» or «التحلي بضبط النفس»."),
        Pattern(bad: "بواسطة", replacement: "عبر",
                reason: "«عبر» or «من خلال» is lighter and more natural in most contexts."),
        Pattern(bad: "بشكل كبير", replacement: "كثيرًا",
                reason: "«بشكل + adjective» often signals a literal calque; an adverb reads better."),
        Pattern(bad: "في الواقع", replacement: "",
                reason: "May be a literal carry-over from \"in fact\". Check whether it is needed."),
        Pattern(bad: "قام بـ", replacement: "",
                reason: "«قام بـ + masdar» is a common calque. Prefer the direct verb."),
        Pattern(bad: "يتم ", replacement: "",
                reason: "Heavy use of «يتم» weakens naturalness. Prefer an active verb or a masdar.")
    ]

    private static func normalizeDigits(_ text: String) -> String {
        let map: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"
        ]
        return String(text.map { map[$0] ?? $0 })
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            ns.substring(with: match.range)
        }
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let wordPattern: String = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: [.caseInsensitive]) else {
            return text.lowercased().contains(word.lowercased())
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func review(source rawSource: String, target rawTarget: String, glossary: [GlossaryTerm]) -> Review {
        let source = rawSource.trimmed
        let target = rawTarget.trimmed
        var findings: [Finding] = []
        var suggestions: [Suggestion] = []

        // 1. Glossary
        for term in glossary {
            let en = term.english.trimmed
            let ar = term.arabic.trimmed
            if en.isEmpty || ar.isEmpty { continue }
            if containsWord(en, in: source) && !ArabicText.contains(term: ar, in: target) {
                findings.append(Finding(category: "Terminology",
                                        title: "Glossary term missing",
                                        detail: "\"\(en)\" should appear as «\(ar)».",
                                        severity: .warning))
                suggestions.append(Suggestion(original: en, replacement: ar,
                                              reason: "Approved glossary term not found in the Arabic text.",
                                              applicable: false))
            }
        }

        // 2. Numbers
        let sourceNumbers = matches(in: normalizeDigits(source), pattern: "\\d+(?:[.,]\\d+)?").sorted()
        let targetNumbers = matches(in: normalizeDigits(target), pattern: "\\d+(?:[.,]\\d+)?").sorted()
        if sourceNumbers != targetNumbers {
            let srcText: String = sourceNumbers.isEmpty ? "none" : sourceNumbers.joined(separator: ", ")
            let tgtText: String = targetNumbers.isEmpty ? "none" : targetNumbers.joined(separator: ", ")
            let numbersDetail: String = "Source: \(srcText). Target: \(tgtText)."
            findings.append(Finding(category: "Numbers",
                                    title: "Numbers differ",
                                    detail: numbersDetail,
                                    severity: .critical))
        }

        // 3. Placeholders
        let placeholderPattern = "\\{[^{}]+\\}|%[0-9]*\\$?[@sdf]|<[^<>]+>"
        let sourcePlaceholders = matches(in: source, pattern: placeholderPattern).sorted()
        let targetPlaceholders = matches(in: target, pattern: placeholderPattern).sorted()
        if sourcePlaceholders != targetPlaceholders {
            findings.append(Finding(category: "Placeholders",
                                    title: "Variables or tags differ",
                                    detail: "Compare tokens such as {name}, %s or <b> in both texts.",
                                    severity: .critical))
        }

        // 4. Arabic script share
        let letters = target.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let arabicLetters = letters.filter { scalar in
            let v: UInt32 = scalar.value
            if v >= 0x0600 && v <= 0x06FF { return true }
            if v >= 0x0750 && v <= 0x077F { return true }
            if v >= 0x08A0 && v <= 0x08FF { return true }
            return false
        }
        let arabicRatio = letters.isEmpty ? 0.0 : Double(arabicLetters.count) / Double(letters.count)
        let arabicPercent = Int((arabicRatio * 100).rounded())
        if arabicRatio < 0.85 {
            findings.append(Finding(category: "Script",
                                    title: "Check language composition",
                                    detail: "Arabic letters are \(arabicPercent)% of all letters. Latin text may be untranslated or intentional (names, brands).",
                                    severity: .info))
        }

        // 4b. Language detection (NaturalLanguage)
        let detected = ArabicText.dominantLanguage(target)
        if let language = detected.language, language != .arabic, detected.confidence >= 0.5 {
            let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
            findings.append(Finding(category: "Language",
                                    title: "Target may not be Arabic",
                                    detail: "Detected \(name) (\(Int((detected.confidence * 100).rounded()))% confidence).",
                                    severity: .warning))
        }

        // 5. Length ratio
        let ratio = Double(target.count) / Double(max(source.count, 1))
        if ratio < 0.4 {
            findings.append(Finding(category: "Length",
                                    title: "Target is much shorter",
                                    detail: "Ratio \(String(format: "%.2f", ratio)). Part of the meaning may be missing.",
                                    severity: .warning))
        } else if ratio > 2.2 {
            findings.append(Finding(category: "Length",
                                    title: "Target is much longer",
                                    detail: "Ratio \(String(format: "%.2f", ratio)). Check for additions or UI truncation.",
                                    severity: .info))
        }

        // 6. Phrasing patterns
        for p in patterns where target.contains(p.bad) {
            findings.append(Finding(category: "Phrasing",
                                    title: "Possible literal phrasing",
                                    detail: "«\(p.bad.trimmed)» \(p.reason)",
                                    severity: .warning))
            suggestions.append(Suggestion(original: p.bad, replacement: p.replacement,
                                          reason: p.reason, applicable: !p.replacement.isEmpty))
        }

        // 7. Punctuation
        let punctuation: [(String, String)] = [("?", "؟"), (";", "؛"), (",", "،")]
        for pair in punctuation {
            let present: Bool
            if pair.0 == "," {
                present = !matches(in: target, pattern: "(?<!\\d),(?!\\d)").isEmpty
            } else {
                present = target.contains(pair.0)
            }
            if present {
                findings.append(Finding(category: "Punctuation",
                                        title: "Latin punctuation in Arabic text",
                                        detail: "Use «\(pair.1)» instead of \"\(pair.0)\".",
                                        severity: .info))
                suggestions.append(Suggestion(original: pair.0, replacement: pair.1,
                                              reason: "Use Arabic punctuation marks in Arabic text.",
                                              applicable: true))
            }
        }

        // 8. Spacing
        if target.contains("  ") {
            findings.append(Finding(category: "Spacing",
                                    title: "Double spaces",
                                    detail: "Remove the extra spaces.",
                                    severity: .info))
        }

        // 8b. Sentence count (NaturalLanguage)
        let sourceSentences = ArabicText.sentenceCount(source)
        let targetSentences = ArabicText.sentenceCount(target)
        if sourceSentences >= 2 && targetSentences < sourceSentences {
            findings.append(Finding(category: "Sentences",
                                    title: "Possible missing sentence",
                                    detail: "Source has \(sourceSentences) sentences, target has \(targetSentences).",
                                    severity: .info))
        }

        // Score
        var score = 100
        for f in findings {
            switch f.severity {
            case .critical: score -= 20
            case .warning: score -= 8
            case .info: score -= 3
            }
        }
        score = max(0, min(100, score))

        return Review(source: source, target: target, score: score,
                      arabicPercent: arabicPercent, lengthRatio: ratio,
                      findings: findings, suggestions: suggestions)
    }

    static func apply(_ accepted: [Suggestion], to text: String) -> String {
        var result = text
        for s in accepted where s.applicable {
            if s.original == "," {
                result = result.replacingOccurrences(of: "(?<!\\d),(?!\\d)", with: "،", options: .regularExpression)
            } else {
                result = result.replacingOccurrences(of: s.original, with: s.replacement)
            }
        }
        return result
    }
}

// MARK: - Store

final class LinguAlyzerStore: ObservableObject {
    @Published var source = ""
    @Published var target = ""
    @Published var current: Review?
    @Published var decisions: [UUID: Bool] = [:]
    @Published var selectedTab = 0

    @Published var glossary: [GlossaryTerm]
    @Published var history: [Review]

    func persist() {
        Self.save(glossary, key: "lingualyzer.glossary")
        Self.save(history, key: "lingualyzer.history")
    }

    init() {
        let defaults = [
            GlossaryTerm(english: "settings", arabic: "الإعدادات"),
            GlossaryTerm(english: "privacy", arabic: "الخصوصية"),
            GlossaryTerm(english: "account", arabic: "الحساب"),
            GlossaryTerm(english: "continue", arabic: "متابعة"),
            GlossaryTerm(english: "cancel", arabic: "إلغاء"),
            GlossaryTerm(english: "download", arabic: "تنزيل"),
            GlossaryTerm(english: "save", arabic: "حفظ")
        ]
        glossary = Self.load([GlossaryTerm].self, key: "lingualyzer.glossary") ?? defaults
        history = Self.load([Review].self, key: "lingualyzer.history") ?? []
    }

    var canAnalyze: Bool {
        !source.trimmed.isEmpty && !target.trimmed.isEmpty
    }

    func analyze() {
        guard canAnalyze else { return }
        let review = Analyzer.review(source: source, target: target, glossary: glossary)
        current = review
        decisions = [:]
        history.insert(review, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        persist()
    }

    func loadSample() {
        source = "Go to Settings to update your privacy preferences, then select Continue."
        target = "انتقل إلى الإعدادات لتحديث تفضيلات الخصوصية، ثم اختر متابعة."
        current = nil
    }

    func swapTexts() {
        let old = source
        source = target
        target = old
        current = nil
    }

    func clearTexts() {
        source = ""
        target = ""
        current = nil
        decisions = [:]
    }

    func finalText() -> String {
        guard let review = current else { return "" }
        let accepted = review.suggestions.filter { decisions[$0.id] == true }
        return Analyzer.apply(accepted, to: review.target)
    }

    func addTerm(english: String, arabic: String) {
        let en = english.trimmed
        let ar = arabic.trimmed
        if en.isEmpty || ar.isEmpty { return }
        glossary.append(GlossaryTerm(english: en, arabic: ar))
        persist()
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Shared UI

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundColor(Theme.forest)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.forest.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Theme.forest)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.mint.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.mint, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Theme.forest, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
        }
        .frame(width: 76, height: 76)
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(Theme.forest.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FindingRow: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(finding.severity.label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(finding.severity.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(finding.severity.color.opacity(0.14), in: Capsule())
                Text(finding.category)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }
            Text(finding.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)
            Text(finding.detail)
                .font(.footnote)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: LinguAlyzerStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            AnalyzeView()
                .tabItem { Label("Analyze", systemImage: "waveform.path.ecg") }
                .tag(0)
            SuggestionsView()
                .tabItem { Label("Suggestions", systemImage: "lightbulb") }
                .tag(1)
            GlossaryView()
                .tabItem { Label("Glossary", systemImage: "character.book.closed") }
                .tag(2)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(4)
        }
    }
}

// MARK: - Analyze

struct AnalyzeView: View {
    @EnvironmentObject var store: LinguAlyzerStore

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(18)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sourceCard
            targetCard
            actionRow
            analyzeButton
            resultSection
            footnote
        }
    }

    private var sourceCard: some View {
        Card {
            HStack {
                Eyebrow(text: "01 · Source")
                Spacer()
                Text("English")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.muted)
            }
            TextEditor(text: $store.source)
                .font(.system(size: 16))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.canvas)
                .cornerRadius(12)
        }
    }

    private var targetCard: some View {
        Card {
            HStack {
                Eyebrow(text: "02 · Localized version")
                Spacer()
                Text("العربية")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.muted)
            }
            TextEditor(text: $store.target)
                .font(.system(size: 17))
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.canvas)
                .cornerRadius(12)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Sample") { store.loadSample() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Swap") { store.swapTexts() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Clear") { store.clearTexts() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var analyzeButton: some View {
        let enabled: Bool = store.canAnalyze
        let amount: Double = enabled ? 1.0 : 0.45
        return Button("Analyze text") {
            store.analyze()
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(amount)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var resultSection: some View {
        if let review = store.current {
            resultCard(review)
        }
    }

    private var footnote: some View {
        Text("Checks run on this device and your text is not sent anywhere. The score is a rule-based screening indicator, not a measure of translation quality.")
            .font(.footnote)
            .foregroundColor(Theme.muted)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LinguAlyzer")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
            Text("Language. Culture. Intelligence.")
                .font(.subheadline)
                .foregroundColor(Theme.forest)
        }
        .padding(.top, 8)
    }

    private func resultCard(_ review: Review) -> some View {
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Screening indicator")
                    Text("Rule-based QA")
                        .font(.title3.bold())
                        .foregroundColor(Theme.ink)
                    // Verbatim: a literal "%" inside a localized, interpolated Text
                    // becomes a broken format string ("...%lld%") and can crash.
                    Text(verbatim: "\(review.findings.count) finding(s) · Arabic \(review.arabicPercent)%")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                ScoreRing(score: review.score)
            }

            if review.findings.isEmpty {
                Text("No automatic flags. A human review is still recommended.")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            } else {
                Divider()
                ForEach(review.findings) { finding in
                    FindingRow(finding: finding)
                }
            }

            if !review.suggestions.isEmpty {
                Button("Review \(review.suggestions.count) suggestion(s)") {
                    store.selectedTab = 1
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

struct SuggestionsView: View {
    @EnvironmentObject var store: LinguAlyzerStore
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let review = store.current {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            if review.suggestions.isEmpty {
                                Card {
                                    Text("No suggestions for this text. A human review is still recommended.")
                                        .foregroundColor(Theme.ink)
                                }
                            } else {
                                ForEach(review.suggestions) { suggestion in
                                    suggestionCard(suggestion)
                                }
                            }
                            finalCard(review)
                        }
                        .padding(18)
                    }
                } else {
                    EmptyHint(icon: "lightbulb",
                              title: "Run an analysis first",
                              message: "Suggestions appear after you analyze a text in the Analyze tab.")
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Smart suggestions")
            Text("Alternatives, with reasons")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
            Text("You decide. Accepted suggestions are applied to the revised text below.")
                .font(.footnote)
                .foregroundColor(Theme.muted)
        }
        .padding(.top, 8)
    }

    private func suggestionCard(_ s: Suggestion) -> some View {
        Card {
            Text("ORIGINAL")
                .font(.caption2.weight(.bold))
                .foregroundColor(Theme.muted)
            Text(s.original)
                .foregroundColor(Theme.ink)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
            replacementView(s)
            Text(s.reason)
                .font(.footnote)
                .foregroundColor(Theme.muted)
            decisionView(s)
        }
    }

    @ViewBuilder
    private func replacementView(_ s: Suggestion) -> some View {
        if s.replacement.isEmpty {
            Text("Rephrase manually")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.forest)
        } else {
            Text(s.replacement)
                .fontWeight(.semibold)
                .foregroundColor(Theme.ink)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(10)
                .background(Theme.mint)
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func decisionView(_ s: Suggestion) -> some View {
        if s.applicable {
            let decision: Bool? = store.decisions[s.id]
            let acceptTitle: String = (decision == true) ? "Accepted ✓" : "Accept"
            let rejectTitle: String = (decision == false) ? "Rejected" : "Reject"
            HStack(spacing: 10) {
                Button(acceptTitle) {
                    store.decisions[s.id] = true
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(rejectTitle) {
                    store.decisions[s.id] = false
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Text("This one needs a manual edit, so there is no automatic replacement.")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
    }

    private func finalCard(_ review: Review) -> some View {
        let finalText = store.finalText()
        return Card {
            Eyebrow(text: "Revised text")
            Text(finalText.isEmpty ? review.target : finalText)
                .textSelection(.enabled)
                .foregroundColor(Theme.ink)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 10) {
                Button(copied ? "Copied ✓" : "Copy text") {
                    UIPasteboard.general.string = finalText.isEmpty ? review.target : finalText
                    copied = true
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Copy report") {
                    UIPasteboard.general.string = review.report(finalText: finalText)
                    copied = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

// MARK: - Glossary

struct GlossaryView: View {
    @EnvironmentObject var store: LinguAlyzerStore
    @State private var english = ""
    @State private var arabic = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add a term") {
                    TextField("English term", text: $english)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("المقابل العربي", text: $arabic)
                        .multilineTextAlignment(.trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    Button("Add term") {
                        store.addTerm(english: english, arabic: arabic)
                        english = ""
                        arabic = ""
                    }
                    .disabled(english.trimmed.isEmpty || arabic.trimmed.isEmpty)
                }

                Section("Approved terms (\(store.glossary.count))") {
                    ForEach(store.glossary) { term in
                        HStack {
                            Text(term.english)
                            Spacer()
                            Text(term.arabic)
                                .foregroundColor(Theme.forest)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                    .onDelete { offsets in
                        store.glossary.remove(atOffsets: offsets)
                        store.persist()
                    }
                }
            }
            .navigationTitle("Glossary")
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: LinguAlyzerStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.history.isEmpty {
                    EmptyHint(icon: "clock.arrow.circlepath",
                              title: "No reviews yet",
                              message: "Each analysis you run is saved here on this device.")
                } else {
                    historyList
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("History")
        }
    }

    private var historyList: some View {
        List {
            Section {
                Button("Clear all history") {
                    store.history = []
                    store.persist()
                }
            }
            Section {
                ForEach(store.history) { review in
                    NavigationLink {
                        HistoryDetailView(review: review)
                    } label: {
                        historyRow(review)
                    }
                }
                .onDelete { offsets in
                    store.history.remove(atOffsets: offsets)
                    store.persist()
                }
            }
        }
    }

    private func historyRow(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(review.source)
                .lineLimit(1)
                .font(.subheadline.weight(.semibold))
            Text("Score \(review.score)")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
    }
}

struct HistoryDetailView: View {
    let review: Review
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(copied ? "Copied ✓" : "Copy report") {
                    UIPasteboard.general.string = review.report(finalText: nil)
                    copied = true
                }
                .buttonStyle(SecondaryButtonStyle())
                Text(review.report(finalText: nil))
                    .font(.system(size: 14, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .navigationTitle("Review")
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        Eyebrow(text: "About")
                        Text("LinguAlyzer")
                            .font(.title2.bold())
                            .foregroundColor(Theme.ink)
                        Text("A review companion for English to Arabic localization. It helps a reviewer catch the things that are easy to miss by hand.")
                            .foregroundColor(Theme.muted)
                    }
                    Card {
                        Eyebrow(text: "What it checks")
                        Text("Glossary terms, numbers, placeholders and tags, Arabic script share, text length, Arabic punctuation, and common literal phrasings.")
                            .foregroundColor(Theme.ink)
                    }
                    Card {
                        Eyebrow(text: "What it does not do")
                        Text("It does not judge meaning, tone, dialect or cultural fit. The score is a screening indicator, not a translation-quality score. A qualified human reviewer makes the final decision.")
                            .foregroundColor(Theme.ink)
                    }
                    Card {
                        Eyebrow(text: "Privacy")
                        Text("Everything runs on your device. Your glossary and history stay in local storage.")
                            .foregroundColor(Theme.ink)
                    }
                }
                .padding(18)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("About")
        }
    }
}

struct ContentView: View {
    @StateObject private var store = LinguAlyzerStore()

    var body: some View {
        RootView()
            .environmentObject(store)
            .tint(Theme.forest)
    }
}
