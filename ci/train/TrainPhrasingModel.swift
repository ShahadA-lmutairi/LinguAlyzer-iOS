// Trains the Arabic phrasing classifier with Create ML (macOS only).
//
// Usage: swift ci/train/TrainPhrasingModel.swift data/phrasing/phrasing.csv out/PhrasingClassifier.mlmodel
import CreateML
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    print("Usage: TrainPhrasingModel <phrasing.csv> <output.mlmodel>")
    exit(1)
}

let data = try MLDataTable(contentsOf: URL(fileURLWithPath: args[1]))
print("Rows: \(data.rows.count)")

let (training, testing) = data.randomSplit(by: 0.8, seed: 42)
print("Training rows: \(training.rows.count), test rows: \(testing.rows.count)")

let parameters = MLTextClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    algorithm: .maxEnt(revision: 1),
    language: .arabic
)
let classifier = try MLTextClassifier(
    trainingData: training,
    textColumn: "text",
    labelColumn: "label",
    parameters: parameters
)

let trainAccuracy = (1.0 - classifier.trainingMetrics.classificationError) * 100
let evaluation = classifier.evaluation(on: testing, textColumn: "text", labelColumn: "label")
let testAccuracy = (1.0 - evaluation.classificationError) * 100
print(String(format: "Training accuracy: %.1f%%", trainAccuracy))
print(String(format: "Test accuracy:     %.1f%%", testAccuracy))
print("Confusion matrix (test):")
print(evaluation.confusion)

// A few sentences the model has never seen.
let probes = [
    "قام النظام بحفظ التغييرات.",
    "حُفظت التغييرات.",
    "يتم الآن التحقق من حسابك.",
    "جارٍ التحقق من حسابك."
]
for sentence in probes {
    let label = try classifier.prediction(from: sentence)
    print("  \(label.padding(toLength: 8, withPad: " ", startingAt: 0)) ← \(sentence)")
}

let output = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try classifier.write(to: output, metadata: MLModelMetadata(
    author: "Shahad",
    shortDescription: "Flags Arabic UI text that reads like a literal translation from English.",
    version: "0.1"
))
print("Saved \(output.path)")
