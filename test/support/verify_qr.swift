// macOS independent verification with Vision; pass the JSON manifest path.
// Each fixture PDF must be rasterized to <pdf path>.png beforehand.
import Foundation
import Vision
struct Fixture: Decodable { let pdf: String; let payload: String }
let entries = try JSONDecoder().decode([Fixture].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
for entry in entries {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(url: URL(fileURLWithPath: entry.pdf + ".png")).perform([request])
    let decoded = (request.results ?? []).compactMap { $0.payloadStringValue }
    guard decoded == [entry.payload] else { fatalError("Payload mismatch: \(entry.pdf): \(decoded)") }
}
print("Verified \(entries.count) QR payloads with Vision")
