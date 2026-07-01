// Bernoulli.ulam.swift
//
// Phase 1 ulam-port input: the canonical Statistical Rethinking opening
// example expressed via the Swift result-builder DSL.
//
// Regenerate the .stan + .data.json + cmdstan output artifacts with:
//
//   stan ulam --model Bernoulli [-V]
//
// Or run this file standalone to print just the Stan source:
//
//   cd ~/Projects/Swift/SwiftStan
//   swiftc -parse-as-library -o /tmp/ulam_bernoulli \
//     Sources/SwiftStan/Ulam/AST/*.swift \
//     Sources/SwiftStan/Ulam/Builder/*.swift \
//     Sources/SwiftStan/Ulam/Data/*.swift \
//     Sources/SwiftStan/Ulam/Generator/*.swift \
//     ~/Documents/StanCases/bernoulli/Preliminaries/Bernoulli.ulam.swift
//   /tmp/ulam_bernoulli

@main
struct BernoulliSmoke {
  static func main() {
    let data: UlamData = [
      "y": .integer([0, 1, 0, 1, 1, 0, 1, 1, 1, 0]),
      "x": .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]),
    ]

    let model = UlamModel(data: data) {
      Likelihood("y", .bernoulli(p: "p"))
      Link(.logit, lhs: "p", rhs: "a + b*x")
      Prior("a", .normal(0, 1.5))
      Prior("b", .normal(0, 0.5))
    }

    do {
      print(try stancode(model))
    } catch {
      print("ERROR: \(error)")
    }
  }
}