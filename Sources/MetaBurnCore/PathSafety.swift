import Darwin
import Foundation

public struct FileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public enum PathSafetyError: Error, Equatable, Sendable {
    case symlink(String)
    case notRegularFile(String)
    case notDirectory(String)
    case escapedRoot(String)
}

/// No-follow filesystem helpers so output dirs and copies cannot chase attacker-controlled links.
public enum PathSafety: Sendable {
    public static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    public static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func isPhysicallyInside(_ path: String, ancestor: String) -> Bool {
        let child = resolvedPath(path)
        let root = resolvedPath(ancestor)
        if child == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return child.hasPrefix(prefix)
    }

    public static func identity(at path: String) throws -> FileIdentity {
        let st = try lstatPath(path)
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK {
            throw PathSafetyError.symlink(path)
        }
        if type != S_IFREG {
            throw PathSafetyError.notRegularFile(path)
        }
        return FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
    }

    public static func assertRegularFileNoFollow(at path: String) throws {
        _ = try identity(at: path)
    }

    public static func ensureDirectoryNoFollow(_ url: URL, within ancestor: String) throws {
        guard !ancestor.isEmpty else { throw PathSafetyError.escapedRoot(url.path) }
        let ancestorResolved = resolvedPath(ancestor)
        var current = url.standardizedFileURL
        while true {
            let path = current.path
            if path == ancestor || resolvedPath(path) == ancestorResolved {
                break
            }
            if isSymlink(path) {
                throw PathSafetyError.symlink(path)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == path { break }
            current = parent
        }
        if !isPhysicallyInside(url.path, ancestor: ancestor) {
            throw PathSafetyError.escapedRoot(url.path)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if isSymlink(url.path) {
            throw PathSafetyError.symlink(url.path)
        }
        if !isPhysicallyInside(url.path, ancestor: ancestor) {
            throw PathSafetyError.escapedRoot(url.path)
        }
    }

    public static func copyNoFollow(from source: String, to destination: URL) throws {
        let expected = try identity(at: source)
        let srcFD = source.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard srcFD >= 0 else { throw PathSafetyError.notRegularFile(source) }
        defer { close(srcFD) }

        var st = Darwin.stat()
        guard fstat(srcFD, &st) == 0 else { throw PathSafetyError.notRegularFile(source) }
        let opened = FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
        guard opened == expected else { throw PathSafetyError.notRegularFile(source) }

        if isSymlink(destination.path) {
            throw PathSafetyError.symlink(destination.path)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
            if isSymlink(destination.path) {
                throw PathSafetyError.symlink(destination.path)
            }
        }

        let destPath = destination.path
        let dstFD = destPath.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644) }
        guard dstFD >= 0 else { throw PathSafetyError.notRegularFile(destPath) }
        defer { close(dstFD) }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { raw in
                read(srcFD, raw.baseAddress, raw.count)
            }
            if n == 0 { break }
            if n < 0 { throw PathSafetyError.notRegularFile(source) }
            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes { raw in
                    write(dstFD, raw.baseAddress?.advanced(by: written), n - written)
                }
                if w <= 0 { throw PathSafetyError.notRegularFile(destPath) }
                written += w
            }
        }
    }

    private static func lstatPath(_ path: String) throws -> Darwin.stat {
        var st = Darwin.stat()
        let rc = path.withCString { lstat($0, &st) }
        if rc != 0 {
            throw PathSafetyError.notRegularFile(path)
        }
        return st
    }
}
