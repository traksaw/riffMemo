//
//  RiffMemoTests.swift
//  RiffMemoTests
//
//  Created by Waskar Paulino on 11/16/25.
//

import Testing
@testable import RiffMemo

struct RiffMemoTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    // THROWAWAY: WAS-49 CI-gate verification. Deliberately fails.
    // This branch/PR exists only to prove the GitHub Actions run actually
    // goes red now that || true is gone. Will not be merged.
    @Test func was49ThrowawayFailingTest() async throws {
        #expect(1 == 2)
    }

}
