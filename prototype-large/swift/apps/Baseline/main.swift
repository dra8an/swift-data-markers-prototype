// The baseline for code sizes: the same input and output as the size apps, with no formatter. Built without the modules of the prototype.
import Darwin

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "ja"
var bytes = Array(locale.utf8)
bytes.append(0x0A)
bytes.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
