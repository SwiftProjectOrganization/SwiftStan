//
//  GeneratedQuantities.swift
//

import Foundation

public func generatedQuantities(model: String = "bernoulli",
                                arguments: [String] = [],
                                cmdstan: String,
                                verbose: Bool = false) -> (String, String) {

  let paths = casePaths(for: model)
  let dirUrl = paths.results

  // Warn if the .stan file has no `generated quantities` block —
  // cmdstan will run but compute nothing useful.
  let stanPath = dirUrl.path + "/" + model + ".stan"
  if let stanSource = try? String(contentsOfFile: stanPath, encoding: .utf8),
     !stanSource.contains("generated quantities") {
    print("Warning: \(model).stan has no `generated quantities` block — generate_quantities will produce no derived quantities.")
  }

  // Discover raw chain files from a prior `sample` run.
  let chains = chainsFromRunInfo(dirUrl: dirUrl, modelName: model)
            ?? chainOutputFiles(dirUrl: dirUrl, modelName: model)
  if chains.isEmpty {
    return ("", "No \(model)_output*.csv chains found in \(dirUrl.path) — run `sample` first.")
  }

  let result = stanGeneratedQuantities(dirUrl: dirUrl,
                                       modelName: model,
                                       chains: chains,
                                       arguments: arguments,
                                       cmdstan: cmdstan,
                                       verbose: verbose)

  if result.1 == "" {
    let result = getGeneratedQuantitiesResult(dirUrl: dirUrl,
                                              modelName: model,
                                              chainCount: chains.count)
    if verbose {
      printResult(result)
    }
    return result
  } else {
    printResult(result)
    return result
  }
}
