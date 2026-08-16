import SwiftUI

enum MessageSegment: Identifiable {
    case text(AttributedString)
    case codeBlock(code: String, language: String)

    var id: String {
        switch self {
        case .text(let s): return "text_\(s.hashValue)"
        case .codeBlock(let code, let lang): return "code_\(lang)_\(code.prefix(20).hashValue)"
        }
    }
}

func parseMarkdown(_ text: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    let parts = text.components(separatedBy: "```")

    for (i, part) in parts.enumerated() {
        if i % 2 == 1 {
            // Inside code block
            let lines = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let langLine = lines.first.map(String.init) ?? ""
            let isLang = langLine.range(of: #"^[a-zA-Z0-9_+\-]+$"#, options: .regularExpression) != nil
            let lang = isLang ? langLine : ""
            let code: String
            if !lang.isEmpty && lines.count > 1 {
                code = String(lines[1])
            } else {
                code = part
            }
            segments.append(.codeBlock(code: code.trimmingCharacters(in: .newlines), language: lang))
        } else if !part.isEmpty {
            segments.append(.text(parseInlineMarkdown(part)))
        }
    }

    if segments.isEmpty {
        segments.append(.text(AttributedString(text)))
    }
    return segments
}

private func parseInlineMarkdown(_ text: String) -> AttributedString {
    var result = AttributedString()
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

    for (lineIdx, line) in lines.enumerated() {
        if lineIdx > 0 {
            result.append(AttributedString("\n"))
        }
        result.append(parseLine(String(line)))
    }
    return result
}

private let headerPattern = try! NSRegularExpression(pattern: #"^(#{1,3})\s+(.+)$"#)
private let bulletPattern = try! NSRegularExpression(pattern: #"^(\s*)[*\-+]\s+(.+)$"#)
private let checkboxChecked = try! NSRegularExpression(pattern: #"^(\s*)[*\-+]\s+\[x\]\s+(.+)$"#, options: .caseInsensitive)
private let checkboxUnchecked = try! NSRegularExpression(pattern: #"^(\s*)[*\-+]\s+\[ \]\s+(.+)$"#)

private func parseLine(_ line: String) -> AttributedString {
    let nsLine = line as NSString
    let range = NSRange(location: 0, length: nsLine.length)

    // Headers
    if let match = headerPattern.firstMatch(in: line, range: range) {
        let level = nsLine.substring(with: match.range(at: 1)).count
        let content = nsLine.substring(with: match.range(at: 2))
        var attr = parseInlineFormatting(content)
        let size: CGFloat = level == 1 ? 18 : level == 2 ? 16 : 15
        attr.font = .system(size: size, weight: .bold)
        return attr
    }

    // Checked checkbox
    if let match = checkboxChecked.firstMatch(in: line, range: range) {
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        var result = AttributedString("\(indent)\u{2611} ")
        var contentAttr = parseInlineFormatting(content)
        contentAttr.strikethroughStyle = .single
        contentAttr.foregroundColor = Color(hex: 0x7C7C96)
        result.append(contentAttr)
        return result
    }

    // Unchecked checkbox
    if let match = checkboxUnchecked.firstMatch(in: line, range: range) {
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        var result = AttributedString("\(indent)\u{2610} ")
        result.append(parseInlineFormatting(content))
        return result
    }

    // Bullet lists
    if let match = bulletPattern.firstMatch(in: line, range: range) {
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        var result = AttributedString("\(indent)  \u{2022} ")
        result.append(parseInlineFormatting(content))
        return result
    }

    return parseInlineFormatting(line)
}

private let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

private func parseInlineFormatting(_ text: String) -> AttributedString {
    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let linkMatches = linkPattern.matches(in: text, range: fullRange)

    var result = AttributedString()
    var cursor = 0

    for match in linkMatches {
        // Text before link
        if match.range.location > cursor {
            let before = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result.append(parseBasicFormatting(before))
        }
        // Link
        let linkText = nsText.substring(with: match.range(at: 1))
        let url = nsText.substring(with: match.range(at: 2))
        var linkAttr = AttributedString(linkText)
        linkAttr.foregroundColor = AppColors.accentOrange
        linkAttr.underlineStyle = .single
        if let linkURL = URL(string: url) {
            linkAttr.link = linkURL
        }
        result.append(linkAttr)
        cursor = match.range.location + match.range.length
    }

    // Remaining text
    if cursor < nsText.length {
        let remaining = nsText.substring(from: cursor)
        result.append(parseBasicFormatting(remaining))
    }

    return result
}

private func parseBasicFormatting(_ text: String) -> AttributedString {
    var result = AttributedString()
    let chars = Array(text)
    var i = 0

    while i < chars.count {
        // Strikethrough: ~text~
        if chars[i] == "~" && i + 1 < chars.count && chars[i + 1] != " " {
            if let end = text.index(of: "~", after: i + 1), text[text.index(text.startIndex, offsetBy: end - 1)] != " " {
                let content = String(chars[(i + 1)..<end])
                var attr = AttributedString(content)
                attr.strikethroughStyle = .single
                result.append(attr)
                i = end + 1
                continue
            }
        }

        // Inline code: `text`
        if chars[i] == "`" {
            if let end = text.index(of: "`", after: i + 1) {
                let content = String(chars[(i + 1)..<end])
                var attr = AttributedString(content)
                attr.font = .system(.body, design: .monospaced)
                attr.backgroundColor = AppColors.inlineCodeBg
                result.append(attr)
                i = end + 1
                continue
            }
        }

        // Bold+Italic: ***text***
        if i + 2 < chars.count && chars[i] == "*" && chars[i + 1] == "*" && chars[i + 2] == "*" {
            if let end = text.range(of: "***", after: i + 3) {
                let content = String(chars[(i + 3)..<end])
                var attr = AttributedString(content)
                attr.font = .system(.body, design: .default).bold().italic()
                result.append(attr)
                i = end + 3
                continue
            }
        }

        // Bold: **text**
        if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "*" {
            if let end = text.range(of: "**", after: i + 2) {
                let content = String(chars[(i + 2)..<end])
                var attr = AttributedString(content)
                attr.font = .system(.body, design: .default).bold()
                result.append(attr)
                i = end + 2
                continue
            }
        }

        // Bold (single *): *text*
        if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] != " " {
            if let end = text.index(of: "*", after: i + 1), end > i + 1 && chars[end - 1] != " " {
                let content = String(chars[(i + 1)..<end])
                var attr = AttributedString(content)
                attr.font = .system(.body, design: .default).bold()
                result.append(attr)
                i = end + 1
                continue
            }
        }

        // Italic: _text_
        if chars[i] == "_" && i + 1 < chars.count && chars[i + 1] != " " {
            if let end = text.index(of: "_", after: i + 1), end > i + 1 && chars[end - 1] != " " {
                let content = String(chars[(i + 1)..<end])
                var attr = AttributedString(content)
                attr.font = .system(.body, design: .default).italic()
                result.append(attr)
                i = end + 1
                continue
            }
        }

        result.append(AttributedString(String(chars[i])))
        i += 1
    }

    return result
}

// MARK: - String search helpers

private extension String {
    func index(of char: Character, after startIdx: Int) -> Int? {
        let chars = Array(self)
        for i in startIdx..<chars.count {
            if chars[i] == char { return i }
        }
        return nil
    }

    func range(of substring: String, after startIdx: Int) -> Int? {
        let chars = Array(self)
        let sub = Array(substring)
        guard sub.count > 0 else { return nil }
        for i in startIdx...(chars.count - sub.count) {
            if Array(chars[i..<(i + sub.count)]) == sub {
                return i
            }
        }
        return nil
    }
}
