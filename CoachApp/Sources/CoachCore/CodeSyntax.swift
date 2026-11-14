import Foundation

public enum CodeTokenKind: Sendable, CaseIterable {
    case keyword, type, string, number, comment, function, attribute, constant, tag
}

public struct CodeToken: Equatable, Sendable {
    public var range: NSRange
    public var kind: CodeTokenKind
    public init(range: NSRange, kind: CodeTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// A small, fast syntax highlighter for code blocks (the language after ``` picks the rules).
/// It tokenises comments, strings, numbers, keywords, types, function calls and attributes —
/// enough for readable colour, not a full parser. Ranges are UTF-16, like NSString.
public enum CodeSyntax {
    struct Language {
        var keywords: Set<String> = []
        var types: Set<String> = []
        var constants: Set<String> = []
        var lineComments: [String] = []
        var blockComment: (String, String)?
        var quotes: Set<UInt16> = [34, 39]          // " '
        var multilineQuotes: Set<UInt16> = []       // e.g. ` in JS/Go
        var tripleQuotes = false                    // """ and '''
        var capitalizedAreTypes = true
        var attributes = false                      // @decorator / @attribute
        var preprocessor = false                    // #include at line start (C family)
        var markup = false                          // <tag> names
        var caseInsensitive = false                 // SQL
        var dollarInIdentifiers = false             // JS, PHP, Bash
    }

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

    private static let cConstants = words("true false null nullptr NULL nil")

    static let swift = Language(
        keywords: words("""
        actor any as associatedtype async await break case catch class continue convenience default defer deinit \
        didSet do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect \
        init inout internal is lazy let mutating nonisolated nonmutating open operator optional override private \
        protocol public repeat required rethrows return self Self set some static struct subscript super switch \
        throw throws try typealias unowned var weak where while willSet consuming borrowing macro package
        """),
        constants: words("true false nil"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34], tripleQuotes: true, attributes: true)

    static let python = Language(
        keywords: words("""
        and as assert async await break class continue def del elif else except finally for from global if import \
        in is lambda nonlocal not or pass raise return try while with yield match case self cls print
        """),
        types: words("int float str bool list dict set tuple bytes object type range len enumerate zip map filter sorted"),
        constants: words("True False None"),
        lineComments: ["#"], tripleQuotes: true, capitalizedAreTypes: true, attributes: true)

    static let javascript = Language(
        keywords: words("""
        async await break case catch class const continue debugger default delete do else export extends finally \
        for from function get if import in instanceof let new of return set static super switch this throw try \
        typeof var void while with yield as interface type enum implements private protected public readonly \
        abstract declare namespace keyof infer satisfies
        """),
        types: words("string number boolean any unknown never object symbol bigint void Array Promise Map Set Record"),
        constants: words("true false null undefined NaN Infinity"),
        lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: [96], attributes: true, dollarInIdentifiers: true)

    static let java = Language(
        keywords: words("""
        abstract assert break case catch class const continue default do else enum extends final finally for goto \
        if implements import instanceof interface native new package private protected public return static \
        strictfp super switch synchronized this throw throws transient try volatile while var record yield sealed \
        permits fun val when object companion data inline suspend override lateinit internal open is in out by \
        init constructor typealias
        """),
        types: words("int long short byte char float double boolean void String Integer Long Double Boolean List Map Set Unit Any"),
        constants: cConstants,
        lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true, attributes: true)

    static let c = Language(
        keywords: words("""
        auto break case catch class const constexpr continue default delete do else enum explicit extern for \
        friend goto if inline mutable namespace new noexcept operator private protected public register return \
        sizeof static static_cast dynamic_cast reinterpret_cast const_cast struct switch template this throw try \
        typedef typename union using virtual volatile while override final co_await co_return co_yield \
        @interface @implementation @end @property self
        """),
        types: words("""
        int long short char float double bool void unsigned signed size_t int8_t int16_t int32_t int64_t uint8_t \
        uint16_t uint32_t uint64_t string vector map set unordered_map unordered_set pair auto std
        """),
        constants: cConstants,
        lineComments: ["//"], blockComment: ("/*", "*/"), preprocessor: true)

    static let csharp = Language(
        keywords: words("""
        abstract as async await base break case catch checked class const continue default delegate do else enum \
        event explicit extern finally fixed for foreach get goto if implicit in interface internal is lock \
        namespace new operator out override params private protected public readonly record ref return sealed set \
        sizeof static struct switch this throw try typeof unchecked unsafe using var virtual void volatile when \
        where while yield init
        """),
        types: words("int long short byte char float double decimal bool string object void List Dictionary Task"),
        constants: words("true false null"),
        lineComments: ["//"], blockComment: ("/*", "*/"), preprocessor: true)

    static let go = Language(
        keywords: words("""
        break case chan const continue default defer else fallthrough for func go goto if import interface map \
        package range return select struct switch type var
        """),
        types: words("""
        int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any \
        make len cap append new delete panic recover
        """),
        constants: words("true false nil iota"),
        lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: [96])

    static let rust = Language(
        keywords: words("""
        as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move \
        mut pub ref return self Self static struct super trait type unsafe use where while macro_rules
        """),
        types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"),
        constants: words("true false None Some Ok Err"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34])

    static let ruby = Language(
        keywords: words("""
        alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo \
        rescue retry return self super then undef unless until when while yield require attr_accessor puts
        """),
        constants: words("true false nil"),
        lineComments: ["#"])

    static let php = Language(
        keywords: words("""
        abstract and array as break case catch class clone const continue declare default do echo else elseif \
        empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function \
        global if implements include instanceof interface isset list match namespace new or print private \
        protected public readonly require return static switch throw trait try unset use var while yield
        """),
        constants: words("true false null TRUE FALSE NULL"),
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), dollarInIdentifiers: true)

    static let sql = Language(
        keywords: words("""
        select from where and or not insert into values update set delete create table drop alter add column \
        index primary key foreign references join inner left right outer full cross on as group by order having \
        limit offset union all distinct case when then else end is in exists between like with returning \
        default unique check constraint view trigger begin commit rollback transaction asc desc over partition
        """),
        types: words("int integer bigint smallint text varchar char boolean bool date timestamp numeric decimal real float serial json jsonb uuid"),
        constants: words("null true false"),
        lineComments: ["--"], blockComment: ("/*", "*/"), capitalizedAreTypes: false, caseInsensitive: true)

    static let shell = Language(
        keywords: words("""
        if then else elif fi for while until do done case esac in function return local export readonly set unset \
        source alias echo cd exit shift break continue sudo
        """),
        constants: words("true false"),
        lineComments: ["#"], multilineQuotes: [96], capitalizedAreTypes: false, dollarInIdentifiers: true)

    static let json = Language(constants: words("true false null"), quotes: [34], capitalizedAreTypes: false)

    static let yaml = Language(constants: words("true false null yes no on off ~"), lineComments: ["#"], capitalizedAreTypes: false)

    static let css = Language(
        keywords: words("important media import keyframes from to supports font-face root"),
        lineComments: [], blockComment: ("/*", "*/"), capitalizedAreTypes: false)

    static let markup = Language(lineComments: [], blockComment: ("<!--", "-->"), capitalizedAreTypes: false, markup: true)

    /// Used when no (or an unknown) language is given: C-like rules with common keywords from many languages.
    static let generic: Language = {
        var l = javascript
        l.keywords.formUnion(python.keywords)
        l.keywords.formUnion(c.keywords.filter { !$0.hasPrefix("@") })
        l.keywords.formUnion(go.keywords)
        l.types.formUnion(c.types)
        l.constants.formUnion(python.constants)
        l.constants.formUnion(cConstants)
        l.lineComments = ["//", "#"]
        l.tripleQuotes = true
        return l
    }()

    static func language(_ name: String?) -> Language {
        switch (name ?? "").lowercased() {
        case "swift": return swift
        case "python", "py", "python3": return python
        case "javascript", "js", "jsx", "typescript", "ts", "tsx", "mjs", "node": return javascript
        case "java", "kotlin", "kt", "kts", "scala", "dart", "groovy": return java
        case "c", "cpp", "c++", "cc", "cxx", "h", "hpp", "objc", "objective-c", "objectivec", "arduino": return c
        case "csharp", "cs", "c#": return csharp
        case "go", "golang": return go
        case "rust", "rs": return rust
        case "ruby", "rb": return ruby
        case "php": return php
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql": return sql
        case "bash", "sh", "shell", "zsh", "console", "terminal", "fish", "powershell", "ps1": return shell
        case "json", "jsonc", "json5": return json
        case "yaml", "yml", "toml", "ini": return yaml
        case "css", "scss", "sass", "less": return css
        case "html", "xml", "svg", "vue", "svelte", "plist": return markup
        default: return generic
        }
    }

    /// The language named on a code fence line: "```python" → "python", "``` js {1,3}" → "js".
    public static func fenceLanguage(_ fenceLine: String) -> String? {
        let t = fenceLine.trimmingCharacters(in: .whitespaces).drop { $0 == "`" || $0 == "~" }
        let word = t.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace && $0 != "{" }
        return word.isEmpty ? nil : String(word)
    }

    public static func tokens(_ code: String, language name: String?) -> [CodeToken] {
        let lang = language(name)
        let u = Array(code.utf16)
        let n = u.count
        var out: [CodeToken] = []
        var i = 0
        var lineStart = true // only whitespace so far on this line

        func at(_ s: String, _ p: Int) -> Bool {
            var k = p
            for c in s.utf16 { guard k < n, u[k] == c else { return false }; k += 1 }
            return true
        }
        func add(_ start: Int, _ end: Int, _ kind: CodeTokenKind) {
            if end > start { out.append(CodeToken(range: NSRange(location: start, length: end - start), kind: kind)) }
        }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        func isIdentStart(_ c: UInt16) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 || (lang.dollarInIdentifiers && c == 36)
        }
        func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
        func toLineEnd(_ p: Int) -> Int { var k = p; while k < n, u[k] != 10 { k += 1 }; return k }

        while i < n {
            let c = u[i]
            if c == 10 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 { i += 1; continue }
            let wasLineStart = lineStart
            lineStart = false

            // Comments.
            if let (open, close) = lang.blockComment, at(open, i) {
                var k = i + open.utf16.count
                while k < n, !at(close, k) { k += 1 }
                k = min(n, k + close.utf16.count)
                add(i, k, .comment); i = k; continue
            }
            if lang.lineComments.contains(where: { at($0, i) }) {
                // `#` only starts a comment at a word boundary (keeps `$#` and `a#b` intact).
                if c != 35 || i == 0 || u[i - 1] == 32 || u[i - 1] == 9 || u[i - 1] == 10 {
                    let k = toLineEnd(i); add(i, k, .comment); i = k; continue
                }
            }
            if lang.preprocessor, wasLineStart, c == 35 { // #include, #define
                let k = toLineEnd(i); add(i, k, .attribute); i = k; continue
            }

            // Strings.
            if lang.quotes.contains(c) || lang.multilineQuotes.contains(c) {
                let triple = lang.tripleQuotes && i + 2 < n && u[i + 1] == c && u[i + 2] == c
                let multiline = triple || lang.multilineQuotes.contains(c)
                var k = i + (triple ? 3 : 1)
                while k < n {
                    if u[k] == 92 { k += 2; continue } // backslash escape
                    if !multiline, u[k] == 10 { break }
                    if u[k] == c {
                        if !triple { k += 1; break }
                        if k + 2 < n, u[k + 1] == c, u[k + 2] == c { k += 3; break }
                    }
                    k += 1
                }
                k = min(k, n)
                add(i, k, .string); i = k; continue
            }

            // Numbers.
            if isDigit(c) || (c == 46 && i + 1 < n && isDigit(u[i + 1])), i == 0 || !isIdent(u[i - 1]) {
                var k = i + 1
                while k < n {
                    let d = u[k]
                    if isIdent(d) || d == 46 { k += 1; continue }
                    if (d == 43 || d == 45), (u[k - 1] == 101 || u[k - 1] == 69), k - i > 0, !(u[i] == 48 && i + 1 < n && (u[i + 1] | 32) == 120) {
                        k += 1; continue // 1e-9 (but not inside 0x…)
                    }
                    break
                }
                // "1.." ranges: don't swallow the dots.
                while k > i + 1, u[k - 1] == 46 { k -= 1 }
                add(i, k, .number); i = k; continue
            }

            // Markup tags: <div ...> </div>
            if lang.markup, c == 60 {
                var k = i + 1
                if k < n, u[k] == 47 || u[k] == 33 || u[k] == 63 { k += 1 }
                let nameStart = k
                while k < n, isIdent(u[k]) || u[k] == 45 || u[k] == 58 { k += 1 }
                add(nameStart, k, .tag)
                i = max(k, i + 1); continue
            }

            // @attributes / decorators.
            if lang.attributes, c == 64, i + 1 < n, isIdentStart(u[i + 1]) {
                var k = i + 1
                while k < n, isIdent(u[k]) || u[k] == 46 { k += 1 }
                add(i, k, .attribute); i = k; continue
            }

            // Words.
            if isIdentStart(c) || (c == 64 && i + 1 < n && isIdentStart(u[i + 1])) {
                var k = i + 1
                while k < n, isIdent(u[k]) || (u[k] == 63 && lang.keywords.contains("defined?")) { k += 1 }
                let word = String(utf16CodeUnits: Array(u[i..<k]), count: k - i)
                let key = lang.caseInsensitive ? word.lowercased() : word
                // A word followed by "(" is a call, unless it's a keyword (if, for, while…).
                var p = k
                while p < n, u[p] == 32 { p += 1 }
                let isCall = p < n && u[p] == 40
                let afterDot = i > 0 && u[i - 1] == 46
                if lang.keywords.contains(key), !afterDot { add(i, k, .keyword) }
                else if lang.constants.contains(key) { add(i, k, .constant) }
                else if lang.types.contains(key) || (lang.capitalizedAreTypes && c >= 65 && c <= 90 && !isCall
                                                     && word.contains(where: \.isLowercase)) {
                    add(i, k, .type)
                }
                else if isCall { add(i, k, lang.capitalizedAreTypes && c >= 65 && c <= 90 ? .type : .function) }
                i = k; continue
            }

            i += 1
        }
        if ["yaml", "yml", "toml", "ini"].contains((name ?? "").lowercased()) { out += yamlKeys(u) }
        return out
    }

    /// YAML keys (`key:` at the start of a line, after any indent or "- ") as attributes.
    private static func yamlKeys(_ u: [UInt16]) -> [CodeToken] {
        var out: [CodeToken] = []
        var i = 0
        let n = u.count
        while i < n {
            var k = i
            while k < n, u[k] == 32 || u[k] == 45 { k += 1 } // indent and "- "
            let start = k
            while k < n, u[k] != 58, u[k] != 10, u[k] != 35, u[k] != 34, u[k] != 39 { k += 1 }
            if k < n, u[k] == 58, k > start { out.append(CodeToken(range: NSRange(location: start, length: k - start), kind: .attribute)) }
            while k < n, u[k] != 10 { k += 1 }
            i = k + 1
        }
        return out
    }
}
