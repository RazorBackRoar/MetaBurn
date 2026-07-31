import Foundation

let iterations = 100000
let date = Date()

func withNewFormatter() -> TimeInterval {
    let start = Date()
    for _ in 0..<iterations {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        _ = formatter.string(from: date)
    }
    return Date().timeIntervalSince(start)
}

func withStaticFormatter() -> TimeInterval {
    let start = Date()
    struct Cache {
        static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return f
        }()
    }
    for _ in 0..<iterations {
        _ = Cache.formatter.string(from: date)
    }
    return Date().timeIntervalSince(start)
}

let timeNew = withNewFormatter()
let timeStatic = withStaticFormatter()

print("New formatter: \(timeNew) seconds")
print("Static formatter: \(timeStatic) seconds")
print("Improvement: \(timeNew / timeStatic)x")
