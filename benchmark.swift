import Foundation

func benchmark() {
    let start = Date()
    for _ in 0..<10000 {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        _ = formatter.string(from: start)
    }
    let elapsed = Date().timeIntervalSince(start)
    print("Baseline: \(elapsed) seconds")
}

benchmark()
