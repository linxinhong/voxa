//
//  Cleaner.swift
//  Voxa
//
//  Local rule-based text cleaning for ASR results.
//

import Foundation

enum Cleaner {
    
    // MARK: - Fillers to remove
    
    private static let fillers = [
        "嗯", "啊", "呃", "哦", "喔", "哎", "哟",
        "那个", "这个", "就是", "然后", "那个那个", "这个这个"
    ]
    
    // MARK: - Cleaning Rules
    
    static func clean(_ text: String) -> String {
        var result = text
        
        // Remove filler words
        for filler in fillers {
            result = result.replacingOccurrences(of: filler, with: "")
        }
        
        // Remove repeated characters (e.g., "我我想" -> "我想")
        result = removeRepeatedCharacters(result)
        
        // Normalize whitespace
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add space between Chinese and English/numbers
        result = normalizeSpacing(result)
        
        return result
    }
    
    private static func removeRepeatedCharacters(_ text: String) -> String {
        var result = ""
        var lastChar: Character?
        var repeatCount = 0
        
        for char in text {
            if char == lastChar {
                repeatCount += 1
                if repeatCount <= 1 {
                    result.append(char)
                }
            } else {
                lastChar = char
                repeatCount = 0
                result.append(char)
            }
        }
        
        return result
    }
    
    private static func normalizeSpacing(_ text: String) -> String {
        var result = ""
        var prevChar: Character?
        
        for char in text {
            if let prev = prevChar {
                // Add space between Chinese and ASCII
                let isPrevChinese = isChinese(prev)
                let isCurrChinese = isChinese(char)
                let isPrevASCII = isASCII(prev)
                let isCurrASCII = isASCII(char)
                
                if (isPrevChinese && isCurrASCII) || (isPrevASCII && isCurrChinese) {
                    result.append(" ")
                }
            }
            result.append(char)
            prevChar = char
        }
        
        return result
    }
    
    private static func isChinese(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
    }
    
    private static func isASCII(_ char: Character) -> Bool {
        return char.asciiValue != nil
    }
}
