// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


/// Simple representation of file path. There are should be already existed library for such operations
public struct Path: Hashable {

    enum Error: Swift.Error {
        case notAnAbsolutePath
        case pathCantUnwrapHomeLiteral
        case canNotAppendAbsolutePath
    }

    private var _components: [String.SubSequence]
    private var _path: String

    var isAbsolute: Bool {
        _path.starts(with: "/")
    }

    public var absolutePath: String {
        _path
    }

    public init(_ path: String, isAbsolute: Bool = false) throws {
        guard !path.starts(with: "~") else {
            throw Error.pathCantUnwrapHomeLiteral
        }
        guard !(isAbsolute && path.starts(with: "/")) else {
            throw Error.notAnAbsolutePath
        }

        self._components = Self.normalizePath(path)
        let normalPath = path.starts(with: "/") ? "/" : ""
        self._path = normalPath + self._components.joined(separator: "/")
    }

    private init(path: String, components: [Substring]) {
        self._components = components
        self._path = path
    }

    public func appending(_ string: String) throws -> Path {
        try appending(try Path(string))
    }

    public func appending(_ path: Path) throws -> Path {
        guard !path.isAbsolute else {
            throw Error.canNotAppendAbsolutePath
        }
        return Path(path: _path + "/" + path.absolutePath,
                    components: _components + path._components)
    }
}

extension Path {
    static func normalizePath(_ path: String) -> [String.SubSequence] {
        path.split(separator: "/").reduce(into: []) { (acc, component) in
            switch component {
                case ".":
                    break // Do nothing
                case "..":
                    acc.removeLast()
                default:
                    acc.append(component)
            }
        }
    }
}
