//
//  StanCompile.swift
//  
//
//  Created by Robert Goedman on 11/13/25.
//

import Foundation

public func stanCompile(dirUrl: URL,
                        modelName: String,
                        cmdstan: String,
                        verbose: Bool) -> (String, String) {
  
  let modelPath = "\(dirUrl.path)/\(modelName)"

  if verbose {
    print(["/usr/bin/make", "-C \(cmdstan)", "\(modelPath)"])
  }

  // Pin the C++ deployment target so the model translation unit matches
  // cmdstan's precompiled `model_header.hpp.gch` (built for the current
  // SDK). Without this the compile inherits an ambient
  // MACOSX_DEPLOYMENT_TARGET that can differ from the PCH's target and
  // fail with a "precompiled file … was compiled for the target …"
  // error. This project targets macOS 27.0+.
  var environment = ProcessInfo.processInfo.environment
  environment["MACOSX_DEPLOYMENT_TARGET"] = "27.0"

  let result = swiftSyncFileExec(program: "/usr/bin/make",
                                 arguments: ["-C", cmdstan, "\(modelPath)"],
                                 method: "(\(modelName) executable)",
                                 environment: environment,
                                 logsDir: dirUrl,
                                 logsBase: "\(modelName).compile")
  return result
}
