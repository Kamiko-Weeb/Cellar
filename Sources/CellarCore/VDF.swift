import Foundation

/// A node in Valve's KeyValues text format (`.vdf` / `.acf`). Keys are matched case-insensitively.
public struct VDFNode: Equatable, Sendable {
    public var value: String?
    public var children: [String: VDFNode]

    public init(value: String? = nil, children: [String: VDFNode] = [:]) {
        self.value = value
        self.children = children
    }

    public subscript(key: String) -> VDFNode? { children[key.lowercased()] }
}

public enum VDF {
    public static func parse(_ text: String) -> VDFNode {
        var tokens = tokenize(text)[...]
        return parseObject(&tokens)
    }

    enum Token: Equatable {
        case string(String)
        case open
        case close
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "{":
                tokens.append(.open)
                i += 1
            case "}":
                tokens.append(.close)
                i += 1
            case "\"":
                var s = ""
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        i += 1
                        switch chars[i] {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        default: s.append(chars[i])
                        }
                    } else {
                        s.append(chars[i])
                    }
                    i += 1
                }
                i += 1
                tokens.append(.string(s))
            case "/" where i + 1 < chars.count && chars[i + 1] == "/":
                while i < chars.count, !chars[i].isNewline { i += 1 }
            default:
                if c.isWhitespace {
                    i += 1
                    continue
                }
                var s = ""
                while i < chars.count, !chars[i].isWhitespace, !"{}\"".contains(chars[i]) {
                    s.append(chars[i])
                    i += 1
                }
                tokens.append(.string(s))
            }
        }
        return tokens
    }

    static func parseObject(_ tokens: inout ArraySlice<Token>) -> VDFNode {
        var node = VDFNode()
        while let token = tokens.popFirst() {
            guard case .string(let key) = token else {
                if token == .close { return node }
                continue
            }
            switch tokens.first {
            case .open?:
                tokens.removeFirst()
                node.children[key.lowercased()] = parseObject(&tokens)
            case .string(let value)?:
                tokens.removeFirst()
                node.children[key.lowercased()] = VDFNode(value: value)
            default:
                break
            }
        }
        return node
    }
}
