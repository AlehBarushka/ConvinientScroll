import Foundation

nonisolated enum UpdateError: Error, Equatable {
    case network
    case rateLimited
    case server(status: Int)
    case unreadableVersion(tag: String)
    case noDiskImage
    case diskImageUnreadable
    case appNotInImage
    case signatureInvalid
    case wrongDeveloper
    case versionMismatch(found: String, expected: String)
    case applicationsNotWritable
    case cancelled

    var message: String {
        switch self {
        case .network:
            "Can't reach GitHub. Check your internet connection and try again."
        case .rateLimited:
            "GitHub limits how often updates can be checked. Try again in an hour."
        case .server(let status):
            "GitHub returned an error (HTTP \(status)). Try again later."
        case .unreadableVersion(let tag):
            "The latest release has an unexpected version tag \"\(tag)\"."
        case .noDiskImage:
            "The latest release has no disk image to install."
        case .diskImageUnreadable:
            "The downloaded disk image couldn't be opened."
        case .appNotInImage:
            "The disk image doesn't contain Mac Toolkit."
        case .signatureInvalid:
            "The downloaded app has a broken signature, so it wasn't installed."
        case .wrongDeveloper:
            "The downloaded app isn't signed by the Mac Toolkit developer, so it wasn't installed."
        case .versionMismatch(let found, let expected):
            "The downloaded app is version \(found), but the release is \(expected)."
        case .applicationsNotWritable:
            "Mac Toolkit can't write to the Applications folder. Download the update from GitHub and install it by hand."
        case .cancelled:
            "The update was cancelled."
        }
    }
}
