//
//  CasePaths.swift
//  Stan
//
//  V2.1: case-root + per-model path resolution. Centralises the
//  `<root>/<name>/{Preliminaries,Results}/` layout introduced in
//  V2.1, replacing the V1 flat-directory convention.
//

import Foundation

public struct CasePaths {
  public let model: String
  public let preliminaries: URL
  public let results: URL
}

/// UserDefaults key for the persisted case-root name. Matches the
/// `@AppStorage("stanCases")` key used by SwiftStanApp so a value set
/// from a SwiftUI view backed by the same defaults domain is honoured
/// here. Note: `UserDefaults.standard` is per-process — the standalone
/// app and the `swiftstan` CLI have distinct domains, so this only
/// shares a value cross-component when the `@AppStorage` view and this
/// library run in the same process (e.g. an app/server linking the
/// library). For the CLI it is a valid persisted per-tool preference.
public let stanCasesDefaultsKey = "stanCases"

/// Test-only override for the case root, set once at test-bundle load
/// time via `TestCaseRootBootstrap.install` (see
/// `Tests/SwiftStanTests/TestCaseRootBootstrap.swift`). When non-nil,
/// `caseRoot()` returns this verbatim and skips the env / UserDefaults /
/// Documents resolution below. Production binaries never touch this —
/// it stays nil through the CLI's entire lifetime. `nonisolated(unsafe)`
/// is safe here because the test bootstrap writes exactly once before
/// any concurrent test code runs.
public nonisolated(unsafe) var caseRootOverride: URL? = nil

/// Resolve a raw case-root value (from `$STAN_CASES`, UserDefaults, or
/// the hardcoded default) into a directory URL: tilde-expanded, treated
/// as absolute if it starts with `/`, otherwise resolved as a bare name
/// or relative subpath under `~/Documents/`.
func resolveCaseRoot(from value: String) -> URL {
  let expanded = (value as NSString).expandingTildeInPath
  if expanded.hasPrefix("/") {
    return URL(fileURLWithPath: expanded, isDirectory: true)
  }
  // Bare name ("StanCases") or relative subpath ("SR/v2") — resolve under ~/Documents/
  let documents = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
  return documents.appendingPathComponent(expanded, isDirectory: true)
}

/// Case root resolution, in precedence order: the test-only
/// `caseRootOverride` (set by the test bundle on first access), then the
/// `$STAN_CASES` env var if set, then the persisted UserDefaults
/// `stanCases` preference if set, otherwise `~/Documents/StanCases/`.
public func caseRoot() -> URL {
  if let override = caseRootOverride { return override }
  if let env = ProcessInfo.processInfo.environment["STAN_CASES"],
     !env.isEmpty {
    return resolveCaseRoot(from: env)
  }
  if let stored = UserDefaults.standard.string(forKey: stanCasesDefaultsKey),
     !stored.isEmpty {
    return resolveCaseRoot(from: stored)
  }
  return resolveCaseRoot(from: "StanCases")
}

/// The persisted case-root name, or "StanCases" when unset/empty. Reflects
/// only the stored UserDefaults preference — it does not consult
/// `$STAN_CASES` or `caseRootOverride`.
public func stanCases() -> String {
  let stored = UserDefaults.standard.string(forKey: stanCasesDefaultsKey) ?? ""
  return stored.isEmpty ? "StanCases" : stored
}

/// Persist the case-root name (e.g. "SR2Cases"). Passing an empty string
/// clears the preference, reverting `caseRoot()` to the "StanCases"
/// default (absent any `$STAN_CASES` override).
public func setStanCases(_ value: String) {
  if value.isEmpty {
    UserDefaults.standard.removeObject(forKey: stanCasesDefaultsKey)
  } else {
    UserDefaults.standard.set(value, forKey: stanCasesDefaultsKey)
  }
}

/// `(preliminaries, results)` URLs for `<name>` under the case root.
/// Does not create the directories — use `ensureCaseDirectories(_:)`
/// for that.
public func casePaths(for model: String) -> CasePaths {
  let modelDir = caseRoot().appendingPathComponent(model, isDirectory: true)
  return CasePaths(
    model: model,
    preliminaries: modelDir.appendingPathComponent("Preliminaries", isDirectory: true),
    results: modelDir.appendingPathComponent("Results", isDirectory: true)
  )
}

public func ensureCaseDirectories(_ paths: CasePaths,
                                  verbose: Bool = false) throws {
  let fm = FileManager.default
  for url in [paths.preliminaries, paths.results] {
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
      try fm.createDirectory(at: url,
                             withIntermediateDirectories: true,
                             attributes: nil)
      if verbose { print("Created directory \(url.path)") }
    }
  }
}
