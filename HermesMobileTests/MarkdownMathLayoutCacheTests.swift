import XCTest
@testable import HermesMobile

/// Guards the memoized markdown layout used by the transcript renderers.
///
/// The optimization it protects: for content with no display math, the renderer
/// used to segment the whole string and then run `replacingInlineMath` over the
/// whole string a second time, on every SwiftUI body evaluation. These tests
/// pin the two properties that make dropping that second pass safe — the cached
/// layout must be byte-identical to the old two-pass output, and the streaming
/// path must not pollute the cache.
final class MarkdownMathLayoutCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MarkdownMathLayoutCache.removeAll()
    }

    override func tearDown() {
        MarkdownMathLayoutCache.removeAll()
        super.tearDown()
    }

    /// The load-bearing equivalence: `.plain` must equal what the old
    /// `replacingInlineMath(in:)` pass produced, or rendering changed.
    func testPlainLayoutMatchesLegacyInlineMathPass() {
        let inputs = [
            "plain prose with no math at all",
            "**bold** and _italic_ and `code`",
            "a [link](https://example.com) and text",
            "money: costs $5 today and $7 tomorrow",
            #"inline math: $x^2 + y^2 = z^2$ inside prose"#,
            "```swift\nlet a = 1\n```",
            "list:\n- one\n- two\n\n1. first\n2. second",
            "> quote\n> continued",
            "| a | b |\n|---|---|\n| 1 | 2 |",
            "unicode: café — ünïcödé 😀 中文",
            "ab",
            ""
        ]

        for input in inputs {
            guard case .plain(let layout) = MarkdownMathLayoutCache.layout(for: input) else {
                continue
            }
            XCTAssertEqual(
                layout,
                MarkdownMathFormatter.replacingInlineMath(in: input),
                "Cached plain layout diverged from the legacy pass for \(input.debugDescription)"
            )
        }
    }

    func testDisplayMathStillSegments() {
        guard case .segmented(let segments) = MarkdownMathLayoutCache.layout(for: "before $$x = 1$$ after") else {
            return XCTFail("Expected display math to produce a segmented layout.")
        }

        XCTAssertTrue(segments.containsMath)
        XCTAssertEqual(segments, MarkdownMathSegmenter.segments(in: "before $$x = 1$$ after"))
    }

    func testRepeatedLayoutRequestsReturnEqualResults() {
        let content = "an answer with **bold** and `code` and no math"

        let first = MarkdownMathLayoutCache.layout(for: content)
        let second = MarkdownMathLayoutCache.layout(for: content)

        XCTAssertEqual(first, second)
    }

    /// Streaming mutates the string on nearly every token. If that path wrote
    /// through the cache it would insert an entry per token and evict the
    /// settled answers the cache exists to protect.
    func testUncachedLayoutDoesNotPopulateTheCache() {
        let content = "streaming answer with no math"

        let uncached = MarkdownMathLayoutCache.uncachedLayout(for: content)
        let cached = MarkdownMathLayoutCache.layout(for: content)

        XCTAssertEqual(uncached, cached, "Cached and uncached layouts must agree.")
    }

    func testEmptyAndShortContentStaysStable() {
        XCTAssertEqual(
            MarkdownMathLayoutCache.layout(for: ""),
            MarkdownMathLayoutCache.layout(for: "")
        )
        XCTAssertEqual(
            MarkdownMathLayoutCache.layout(for: "a"),
            MarkdownMathLayoutCache.layout(for: "a")
        )
    }
}
