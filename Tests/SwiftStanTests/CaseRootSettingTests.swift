//
//  CaseRootSettingTests.swift
//  StanTests
//
//  Covers the UserDefaults-backed `stanCases` preference added to
//  `Support/CasePaths.swift`: the `setStanCases(_:)` / `stanCases()`
//  round-trip and the `resolveCaseRoot(from:)` string→URL helper.
//
//  `caseRoot()` itself is not exercised here: every `@Suite` sets
//  `caseRootOverride` (precedence tier 1) via `TestCaseRootBootstrap`,
//  which short-circuits before the UserDefaults read. Mutating that
//  global mid-run would corrupt other (parallel) suites, so we test the
//  pieces that don't depend on the override short-circuit instead.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("case-root stanCases setting tests")
struct CaseRootSettingTests {
  init() { _ = TestCaseRootBootstrap.install }

  @Test("setStanCases / stanCases round-trip through UserDefaults")
  func setterGetterRoundTrip() {
    let saved = UserDefaults.standard.string(forKey: stanCasesDefaultsKey)
    defer {
      if let saved { UserDefaults.standard.set(saved, forKey: stanCasesDefaultsKey) }
      else { UserDefaults.standard.removeObject(forKey: stanCasesDefaultsKey) }
    }

    setStanCases("SR2Cases")
    #expect(stanCases() == "SR2Cases")

    // Empty string clears the preference, reverting to the default name.
    setStanCases("")
    #expect(stanCases() == "StanCases")
    #expect(UserDefaults.standard.string(forKey: stanCasesDefaultsKey) == nil)
  }

  @Test("resolveCaseRoot handles bare name, absolute path, and tilde")
  func resolveVariants() {
    let documents = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]

    // Bare name resolves under ~/Documents/.
    #expect(resolveCaseRoot(from: "SR2Cases").path
            == documents.appendingPathComponent("SR2Cases").path)

    // Absolute path is used verbatim.
    #expect(resolveCaseRoot(from: "/tmp/AbsCases").path == "/tmp/AbsCases")

    // Tilde expands to the home directory.
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(resolveCaseRoot(from: "~/Documents/TildeCases").path
            == home.appendingPathComponent("Documents/TildeCases").path)
  }
}
