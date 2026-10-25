import Foundation
import Testing

@testable import GeekClockCore

/// A scripted claude.ai page: each fetch pops the next result.
@MainActor
private final class FakePage: ClaudePage {
    enum Step {
        case reply(PageReply)
        case throwError
    }

    var steps: [Step]
    var loadSucceeds = true
    private(set) var loads = 0
    private(set) var fetches = 0

    init(_ steps: [Step]) { self.steps = steps }

    func load() async -> Bool {
        loads += 1
        return loadSucceeds
    }

    func fetch(_ path: String) async throws -> PageReply {
        fetches += 1
        switch steps.removeFirst() {
        case .reply(let reply): return reply
        case .throwError: throw CocoaError(.featureUnsupported)
        }
    }
}

private func json(_ status: Int = 200, body: String = "{\"ok\":true}", url: String = "https://claude.ai/api/x")
    -> FakePage.Step
{
    .reply(PageReply(status: status, body: body, url: url))
}

@MainActor
struct ClaudeFetcherTests {
    @Test func fetchesAfterLoadingThePageOnce() async {
        let page = FakePage([json()])
        let fetcher = ClaudeFetcher(page: page)
        #expect(await fetcher.get("/api/x") == .ok(Data("{\"ok\":true}".utf8)))
        #expect(page.loads == 1)

        page.steps = [json()]
        _ = await fetcher.get("/api/x")
        #expect(page.loads == 1, "a ready page is not reloaded")
    }

    @Test func reloadsAndRetriesOnceWhenTheScriptThrows() async {
        let page = FakePage([.throwError, json()])
        let fetcher = ClaudeFetcher(page: page)
        #expect(await fetcher.get("/api/x") == .ok(Data("{\"ok\":true}".utf8)))
        #expect(page.loads == 2, "the page is reloaded before the retry")
        #expect(page.fetches == 2)
    }

    @Test func reportsFailureWhenTheRetryThrowsToo() async {
        let page = FakePage([.throwError, .throwError])
        let fetcher = ClaudeFetcher(page: page)
        guard case .failed = await fetcher.get("/api/x") else {
            Issue.record("expected .failed")
            return
        }
        #expect(page.fetches == 2, "only one retry")
    }

    @Test func failsWhenThePageDoesNotLoad() async {
        let page = FakePage([])
        page.loadSucceeds = false
        let fetcher = ClaudeFetcher(page: page)
        #expect(await fetcher.get("/api/x") == .failed("claude.ai did not load"))
        #expect(page.fetches == 0)
    }

    @Test func recognisesSignedOutReplies() async {
        let page = FakePage([
            json(401),
            json(200, body: "<html>", url: "https://claude.ai/login"),
            json(403, body: "{\"error\":\"x\"}"),
        ])
        let fetcher = ClaudeFetcher(page: page)
        for _ in 0..<3 {
            #expect(await fetcher.get("/api/x") == .signedOut)
        }
    }

    @Test func treatsNonJSONRepliesAsFailuresAndReloads() async {
        let page = FakePage([json(200, body: "<html>challenge</html>"), json()])
        let fetcher = ClaudeFetcher(page: page)
        #expect(await fetcher.get("/api/x") == .failed("HTTP 200"))
        _ = await fetcher.get("/api/x")
        #expect(page.loads == 2, "a challenge page forces a reload next time")
    }

    @Test func resetForcesTheNextFetchToReload() async {
        let page = FakePage([json(), json()])
        let fetcher = ClaudeFetcher(page: page)
        _ = await fetcher.get("/api/x")
        fetcher.reset()
        _ = await fetcher.get("/api/x")
        #expect(page.loads == 2)
    }
}
