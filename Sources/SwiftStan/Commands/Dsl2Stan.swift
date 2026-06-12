//
//  Dsl2Stan.swift
//  Stan
//
//  V2.1 Slice D: compile the smoke driver in
//  `<root>/<name>/Preliminaries/*.ulam.swift` via `swiftc`, run the
//  resulting binary to capture its Stan source on stdout, and write
//  that to `<root>/<name>/Results/<name>.stan`.
//
//  The smoke driver is a self-contained `@main` Swift program that
//  builds an `UlamModel` and prints `stancode(model)` to stdout. The
//  project's Ulam source tree (`Sources/SwiftStan/Ulam/{AST,Builder,Data,
//  Generator}/`) is compiled alongside it so `internal` types resolve.
//
//  Shells out rather than depending on `swift-syntax`. The project
//  root is resolved via the `SWIFTSTAN_PROJECT_ROOT` env var; a
//  default value is used (with a printed notice) when it isn't set.
//

import Foundation

public enum Dsl2StanError: Error, CustomStringConvertible {
  case smokeDriverNotFound(model: String, dir: String)
  case multipleSmokeDrivers(model: String, files: [String])
  case projectRootNotFound
  case swiftcFailed(stderr: String)
  case runtimeFailed(stderr: String, output: String)

  public var description: String {
    switch self {
    case .smokeDriverNotFound(let model, let dir):
      return "dsl2stan: no *.ulam.swift smoke driver found for model '\(model)' in \(dir)"
    case .multipleSmokeDrivers(let model, let files):
      return "dsl2stan: multiple *.ulam.swift smoke drivers for model '\(model)': \(files.joined(separator: ", "))"
    case .projectRootNotFound:
      return "dsl2stan: SWIFTSTAN_PROJECT_ROOT not set and default path missing"
    case .swiftcFailed(let stderr):
      return "dsl2stan: swiftc failed:\n\(stderr)"
    case .runtimeFailed(let stderr, let output):
      return "dsl2stan: smoke driver runtime error:\nstderr: \(stderr)\nstdout: \(output)"
    }
  }
}

/// Compile + run the model's smoke driver, capture stdout, write
/// `Results/<name>.stan`. Returns the URL of the written file.
@discardableResult
public func dsl2stan(model: String, verbose: Bool = false) throws -> URL {
  let paths = casePaths(for: model)
  try ensureCaseDirectories(paths, verbose: verbose)

  let fm = FileManager.default
  let prelim = paths.preliminaries
  let candidates = ((try? fm.contentsOfDirectory(atPath: prelim.path)) ?? [])
    .filter { $0.hasSuffix(".ulam.swift") }
    .sorted()
  guard !candidates.isEmpty else {
    throw Dsl2StanError.smokeDriverNotFound(model: model, dir: prelim.path)
  }
  guard candidates.count == 1 else {
    throw Dsl2StanError.multipleSmokeDrivers(model: model, files: candidates)
  }
  let smokePath = prelim.appendingPathComponent(candidates[0]).path

  let ulamDir = try resolveUlamSourceDir()

  let binary = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("stan_dsl2stan_\(model)_\(UUID().uuidString)")
  let ulamSources =
      dsl2stanGlob(in: ulamDir.appendingPathComponent("AST").path)
    + dsl2stanGlob(in: ulamDir.appendingPathComponent("Builder").path)
    + dsl2stanGlob(in: ulamDir.appendingPathComponent("Data").path)
    + dsl2stanGlob(in: ulamDir.appendingPathComponent("Generator").path)
  let compileArgs = ["-parse-as-library", "-O", "-o", binary.path]
    + ulamSources
    + [smokePath]

  if verbose {
    print("dsl2stan: compiling \(smokePath)")
  }
  let compileResult = dsl2stanRun("/usr/bin/env",
                                  ["swiftc"] + compileArgs,
                                  verbose: verbose)
  guard compileResult.exitCode == 0 else {
    throw Dsl2StanError.swiftcFailed(stderr: compileResult.stderr)
  }

  if verbose {
    print("dsl2stan: running \(binary.path)")
  }
  let runResult = dsl2stanRun(binary.path, [], verbose: verbose)
  try? fm.removeItem(at: binary)
  guard runResult.exitCode == 0, !runResult.stdout.contains("ERROR:") else {
    throw Dsl2StanError.runtimeFailed(stderr: runResult.stderr, output: runResult.stdout)
  }

  let stanURL = paths.results.appendingPathComponent("\(model).stan")
  // 2026-06-02: split stdout on the sentinels. Smoke drivers produced
  // by `AlistEmitter` print the Stan source, then (when present) the
  // `// === SWIFTSTAN_SCALARS ===` block, then the
  // `// === SWIFTSTAN_INITS ===` block. Older drivers without either
  // just print the Stan source.
  let (stanText, scalarsText, initsText) = splitDriverOutput(runResult.stdout)
  try stanText.write(to: stanURL, atomically: true, encoding: .utf8)
  if verbose { print("dsl2stan: wrote \(stanURL.path)") }
  // Side-file: model-known scalar-int constants (e.g. `J`) that the
  // `.stan` data block declares but `csv2json` can't derive from the
  // CSV. Remove any stale sidecar when this model has none.
  let scalarsURL = paths.results.appendingPathComponent("\(model).scalars.json")
  if let scalars = scalarsText, !scalars.isEmpty {
    try scalars.write(to: scalarsURL, atomically: true, encoding: .utf8)
    if verbose { print("dsl2stan: wrote \(scalarsURL.path)") }
  } else {
    try? fm.removeItem(at: scalarsURL)
  }
  if let inits = initsText, !inits.isEmpty {
    let initsURL = paths.results.appendingPathComponent("\(model).init.json")
    try inits.write(to: initsURL, atomically: true, encoding: .utf8)
    if verbose { print("dsl2stan: wrote \(initsURL.path)") }
  }
  return stanURL
}

/// Smoke-driver output may carry a `// === SWIFTSTAN_SCALARS ===`
/// block and/or a `// === SWIFTSTAN_INITS ===` block after the Stan
/// source, each a separator line followed by a JSON dict. Drivers
/// always print them in that order (scalars, then inits). Split the
/// captured stdout into (stan source, optional scalars JSON, optional
/// inits JSON). The Stan source has its trailing newline (from
/// `print()`) trimmed so dsl2stan and the in-process `stancode(_:)`
/// path produce byte-identical files.
private func splitDriverOutput(_ stdout: String)
    -> (stan: String, scalars: String?, inits: String?) {
  var remainder = stdout
  var inits: String? = nil
  var scalars: String? = nil
  // Inits is last, so peel it first.
  if let range = remainder.range(of: "\n\(AlistEmitter.initsSentinel)\n") {
    inits = String(remainder[range.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    remainder = String(remainder[..<range.lowerBound])
  }
  // Scalars now sits at the tail of what's left.
  if let range = remainder.range(of: "\n\(AlistEmitter.scalarsSentinel)\n") {
    scalars = String(remainder[range.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    remainder = String(remainder[..<range.lowerBound])
  }
  // Whichever sentinel matched consumed the `\n` separating it from the
  // Stan source, so `remainder` is clean. With no sentinels, trim the
  // single trailing newline `print()` added.
  let stanText = (scalars == nil && inits == nil) && remainder.hasSuffix("\n")
    ? String(remainder.dropLast())
    : remainder
  return (stanText, scalars, inits)
}

private func resolveUlamSourceDir() throws -> URL {
  if let env = ProcessInfo.processInfo.environment["SWIFTSTAN_PROJECT_ROOT"], !env.isEmpty {
    let url = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
    return url.appendingPathComponent("Sources/SwiftStan/Ulam", isDirectory: true)
  }
  let defaultRoot = "/Users/rob/Projects/Swift/SwiftStan"
  print("dsl2stan: SWIFTSTAN_PROJECT_ROOT not set — using default \(defaultRoot)")
  let fallback = URL(fileURLWithPath: defaultRoot, isDirectory: true)
    .appendingPathComponent("Sources/SwiftStan/Ulam", isDirectory: true)
  if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
  throw Dsl2StanError.projectRootNotFound
}

private func dsl2stanGlob(in dir: String) -> [String] {
  ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
    .filter { $0.hasSuffix(".swift") }
    .sorted()
    .map { dir + "/" + $0 }
}

private struct Dsl2StanRunResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

private func dsl2stanRun(_ path: String,
                         _ args: [String],
                         verbose: Bool) -> Dsl2StanRunResult {
  let proc = Process()
  proc.launchPath = path
  proc.arguments = args
  let outPipe = Pipe()
  let errPipe = Pipe()
  proc.standardOutput = outPipe
  proc.standardError = errPipe
  do {
    try proc.run()
  } catch {
    return Dsl2StanRunResult(exitCode: -1, stdout: "", stderr: "Process.run failed: \(error)")
  }
  let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
  let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
  proc.waitUntilExit()
  let stdout = String(decoding: outData, as: UTF8.self)
  let stderr = String(decoding: errData, as: UTF8.self)
  if verbose {
    if !stdout.isEmpty { print("[\(path)] stdout (\(stdout.count) bytes)") }
    if !stderr.isEmpty { print("[\(path)] stderr: \(stderr)") }
  }
  return Dsl2StanRunResult(exitCode: proc.terminationStatus,
                           stdout: stdout,
                           stderr: stderr)
}
