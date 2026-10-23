// Numbers: the digits of the numbering system of the locale, and the numeral systems that a pattern can name (format/numeric_override.rs in ICU4X).
import DataMarkers

extension TextOutput {
    /// Appends one Unicode scalar as UTF-8.
    @inlinable
    public mutating func append(scalar v: UInt32) {
        if v < 0x80 {
            append(UInt8(v))
        } else if v < 0x800 {
            append(UInt8(0xC0 | (v >> 6)))
            append(UInt8(0x80 | (v & 0x3F)))
        } else if v < 0x10000 {
            append(UInt8(0xE0 | (v >> 12)))
            append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            append(UInt8(0x80 | (v & 0x3F)))
        } else {
            append(UInt8(0xF0 | (v >> 18)))
            append(UInt8(0x80 | ((v >> 12) & 0x3F)))
            append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            append(UInt8(0x80 | (v & 0x3F)))
        }
    }

    /// Appends a number in ASCII digits, with at least `minDigits` digits, as Decimal::write_to in ICU4X.
    @inlinable
    public mutating func appendASCII(_ value: Int, minDigits: Int = 1) {
        if value < 0 {
            append(0x2D)
        }
        var digits = InlineArray<24, UInt8>(repeating: 0x30)
        var n = value < 0 ? -value : value
        var count = 0
        repeat {
            digits[count] = UInt8(0x30 + n % 10)
            n /= 10
            count += 1
        } while n > 0 && count < 24
        var pad = minDigits - count
        while pad > 0 {
            append(0x30)
            pad -= 1
        }
        var i = count - 1
        while i >= 0 {
            append(digits[i])
            i -= 1
        }
    }
}

/// The numeral systems that a field length of 17 to 21 names (FieldNumericOverrides in ICU4X).
@usableFromInline
enum NumericOverride {
    @inlinable
    static func format(_ number: Int, override: Int, into out: inout TextOutput) {
        switch override {
        case 17: hanidec(number, into: &out)
        case 18: hanidays(number, into: &out)
        case 19: hebrew(number, into: &out)
        case 20: romanlow(number, into: &out)
        default: jpnyear(number, into: &out)
        }
    }

    @usableFromInline static let hanidecDigits: InlineArray<10, UInt32> = [0x3007, 0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, 0x516B, 0x4E5D]

    @inlinable
    static func jpnyear(_ number: Int, into out: inout TextOutput) {
        if number == 1 {
            out.append(scalar: 0x5143)
        } else {
            out.appendASCII(number)
        }
    }

    @inlinable
    static func hanidec(_ number: Int, into out: inout TextOutput) {
        if number == 0 {
            out.append(scalar: hanidecDigits[0])
            return
        }
        var digits = InlineArray<10, UInt8>(repeating: 0)
        var n = number
        var count = 0
        while n > 0 && count < 10 {
            digits[count] = UInt8(n % 10)
            n /= 10
            count += 1
        }
        var i = count - 1
        while i >= 0 {
            out.append(scalar: hanidecDigits[Int(digits[i])])
            i -= 1
        }
    }

    @inlinable
    static func hanidays(_ number: Int, into out: inout TextOutput) {
        // Element 0 is the Han digit 1.
        let han: InlineArray<10, UInt32> = [0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, 0x516B, 0x4E5D, 0x5341]
        switch number {
        case 0: out.append(scalar: 0x3007)
        case 1 ... 10:
            out.append(scalar: 0x521D)
            out.append(scalar: han[number - 1])
        case 11 ... 19:
            out.append(scalar: han[9])
            out.append(scalar: han[number - 11])
        case 20:
            out.append(scalar: 0x4E8C)
            out.append(scalar: 0x5341)
        case 21 ... 29:
            out.append(scalar: 0x5EFF)
            out.append(scalar: han[number - 21])
        case 30:
            out.append(scalar: 0x4E09)
            out.append(scalar: 0x5341)
        case 31 ... 39:
            out.append(scalar: 0x4E17)
            out.append(scalar: han[number - 31])
        case 40:
            out.append(scalar: 0x56DB)
            out.append(scalar: 0x5341)
        case 41 ... 49:
            out.append(scalar: 0x534C)
            out.append(scalar: han[number - 41])
        default:
            out.appendASCII(number)
        }
    }

    @inlinable
    static func romanlow(_ number: Int, into out: inout TextOutput) {
        if number == 0 {
            out.append(0x6E)
            return
        }
        if number >= 5000 {
            out.appendASCII(number)
            return
        }
        var n = number
        let values: InlineArray<13, Int> = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        // Each numeral as up to 2 ASCII letters: low byte first.
        let letters: InlineArray<13, UInt16> = [0x6D, 0x6D63, 0x64, 0x6463, 0x63, 0x6378, 0x6C, 0x6C78, 0x78, 0x7869, 0x76, 0x7669, 0x69]
        for i in 0 ..< 13 {
            while n >= values[i] {
                out.append(UInt8(letters[i] & 0xFF))
                if letters[i] > 0xFF { out.append(UInt8(letters[i] >> 8)) }
                n -= values[i]
            }
        }
    }

    // The Hebrew letters. Hundreds above 400 are two or three letters, from the hundreds table.
    @usableFromInline static let hebrewUnits: InlineArray<9, UInt32> = [0x5D0, 0x5D1, 0x5D2, 0x5D3, 0x5D4, 0x5D5, 0x5D6, 0x5D7, 0x5D8]
    @usableFromInline static let hebrewTens: InlineArray<9, UInt32> = [0x5D9, 0x5DB, 0x5DC, 0x5DE, 0x5E0, 0x5E1, 0x5E2, 0x5E4, 0x5E6]
    // ק ר ש ת תק תר תש תת תתק: each entry packs up to 3 letters, first letter in the low bits, as the offset from U+05D0 plus 1, 6 bits each.
    @usableFromInline static let hebrewHundreds: InlineArray<9, UInt32> = [0x18, 0x19, 0x1A, 0x1B, 0x18 << 6 | 0x1B, 0x19 << 6 | 0x1B, 0x1A << 6 | 0x1B, 0x1B << 6 | 0x1B, 0x18 << 12 | 0x1B << 6 | 0x1B]
    @usableFromInline static let geresh: UInt32 = 0x5F3
    @usableFromInline static let gershayim: UInt32 = 0x5F4

    /// The letters of the hundreds of `n` (1 to 9), first letter first.
    @inlinable
    static func hundredLetters(_ h: Int) -> (count: Int, letters: InlineArray<3, UInt32>) {
        var letters = InlineArray<3, UInt32>(repeating: 0)
        guard h >= 1 && h <= 9 else { return (0, letters) }
        var packed = hebrewHundreds[h - 1]
        var count = 0
        while packed != 0 {
            letters[count] = 0x5D0 + (packed & 0x3F) - 1
            packed >>= 6
            count += 1
        }
        return (count, letters)
    }

    @inlinable
    static func hebrewBelow1000(_ n: Int, forceGeresh: Bool, into out: inout TextOutput) {
        let (hcount, hletters) = hundredLetters(n / 100)
        let rem = n % 100
        var wroteGershayim = false
        func writeHundreds(_ out: inout TextOutput) {
            for i in 0 ..< hcount { out.append(scalar: hletters[i]) }
        }
        if rem == 15 || rem == 16 {
            writeHundreds(&out)
            out.append(scalar: 0x5D8)
            out.append(scalar: gershayim)
            out.append(scalar: rem == 15 ? 0x5D5 : 0x5D6)
            wroteGershayim = true
        } else {
            let tens = rem / 10
            let units = rem % 10
            if tens > 0 && units > 0 {
                writeHundreds(&out)
                out.append(scalar: hebrewTens[tens - 1])
                out.append(scalar: gershayim)
                out.append(scalar: hebrewUnits[units - 1])
                wroteGershayim = true
            } else if tens > 0 || units > 0 {
                let x = tens > 0 ? hebrewTens[tens - 1] : hebrewUnits[units - 1]
                if hcount > 0 {
                    writeHundreds(&out)
                    out.append(scalar: gershayim)
                    out.append(scalar: x)
                    wroteGershayim = true
                } else {
                    out.append(scalar: x)
                    out.append(scalar: geresh)
                }
            } else if hcount == 1 {
                out.append(scalar: hletters[0])
                out.append(scalar: geresh)
            } else if hcount > 1 {
                for i in 0 ..< hcount - 1 { out.append(scalar: hletters[i]) }
                out.append(scalar: gershayim)
                out.append(scalar: hletters[hcount - 1])
                wroteGershayim = true
            }
        }
        if wroteGershayim && forceGeresh {
            out.append(scalar: geresh)
        }
    }

    @inlinable
    static func hebrew(_ number: Int, into out: inout TextOutput) {
        switch number {
        case 0: out.append(0x30)
        case 1000: out.append("אלף")
        case 2000: out.append("אלפיים")
        case 1_000_000: out.append("אלף אלפים")
        case 1_000_001...: out.appendASCII(number)
        case 1001 ..< 1_000_000:
            let rest = number % 1000
            hebrewBelow1000(number / 1000, forceGeresh: rest > 0, into: &out)
            if rest == 0 {
                out.append(" אלפים")
            } else {
                hebrewBelow1000(rest, forceGeresh: false, into: &out)
            }
        default:
            hebrewBelow1000(number, forceGeresh: false, into: &out)
        }
    }
}
