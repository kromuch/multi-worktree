import CoreGraphics
import Foundation

let owner = CommandLine.arguments[1]
let title = CommandLine.arguments[2]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          window[kCGWindowName as String] as? String == title,
          window[kCGWindowLayer as String] as? Int == 0,
          let number = window[kCGWindowNumber as String] as? Int else { continue }
    print(number)
    exit(0)
}
FileHandle.standardError.write(Data("no on-screen window of \(owner) titled \(title)\n".utf8))
exit(1)
