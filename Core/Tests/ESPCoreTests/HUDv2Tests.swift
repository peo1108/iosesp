import Testing
@testable import ESPCore

@Test func countSummaryFormats() {
    #expect(CountSummary.text(people: 3, animals: [.cat: 1, .dog: 1]) == "3 người · 🐕 1 · 🐈 1")
    #expect(CountSummary.text(people: 1, animals: [:]) == "1 người")
    #expect(CountSummary.text(people: 0, animals: [.bird: 2]) == "🐦 2")
}

@Test func countSummaryEmpty() {
    #expect(CountSummary.text(people: 0, animals: [:]) == "Không có ai")
}
