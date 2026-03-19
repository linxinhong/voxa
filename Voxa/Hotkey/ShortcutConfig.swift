//
//  ShortcutConfig.swift
//  Voxa
//
//  Hotkey configuration management.
//

import Foundation
import AppKit
import HotKey

/// 支持的快捷键配置
struct ShortcutConfig: Codable, Equatable {
    var key: String       // 例如: "space", "v"
    var modifiers: [String] // 例如: ["option"], ["control"]
    
    init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = modifiers
    }
    
    static let `default` = ShortcutConfig(
        key: "space",
        modifiers: ["option"]
    )
    
    /// 从字符串解析快捷键配置
    /// 格式: "modifiers+key" 例如: "option+space", "ctrl+v"
    init?(from string: String) {
        let parts = string.lowercased()
            .replacingOccurrences(of: "ctrl", with: "control")
            .replacingOccurrences(of: "cmd", with: "command")
            .replacingOccurrences(of: "opt", with: "option")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard let keyPart = parts.last else { return nil }
        let modifierParts = Array(parts.dropLast())
        
        // 验证 key
        guard Key.from(string: keyPart) != nil else {
            NSLog("[Voxa] 不支持的快捷键: \(keyPart)")
            return nil
        }
        
        // 验证 modifiers（只支持标准修饰键）
        let validModifiers = ["command", "option", "control", "shift"]
        let invalidModifiers = modifierParts.filter { !validModifiers.contains($0) }
        if !invalidModifiers.isEmpty {
            NSLog("[Voxa] 不支持的修饰键: \(invalidModifiers)")
            NSLog("[Voxa] 支持的修饰键: command, option, control, shift")
            return nil
        }
        
        self.key = keyPart
        self.modifiers = modifierParts
    }
    
    /// 转换为 HotKey 可用的 Key
    var hotKey: Key? {
        return Key.from(string: key)
    }
    
    /// 转换为 HotKey 可用的 NSEvent.ModifierFlags
    var hotKeyModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case "command":
                flags.insert(.command)
            case "option":
                flags.insert(.option)
            case "control":
                flags.insert(.control)
            case "shift":
                flags.insert(.shift)
            default:
                break
            }
        }
        return flags
    }
    
    /// 显示用的字符串
    var displayString: String {
        var parts: [String] = []
        for modifier in modifiers {
            switch modifier {
            case "command": parts.append("⌘")
            case "option": parts.append("⌥")
            case "control": parts.append("⌃")
            case "shift": parts.append("⇧")
            default: break
            }
        }
        parts.append(key.uppercased())
        return parts.joined(separator: "+")
    }
}

// MARK: - Key Extension

extension Key {
    static func from(string: String) -> Key? {
        switch string.lowercased() {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "forwarddelete", "del": return .forwardDelete
        case "home": return .home
        case "end": return .end
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        case "left", "leftarrow": return .leftArrow
        case "right", "rightarrow": return .rightArrow
        case "up", "uparrow": return .upArrow
        case "down", "downarrow": return .downArrow
        case "help": return .help
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "0": return .zero
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        case "f13": return .f13
        case "f14": return .f14
        case "f15": return .f15
        case "f16": return .f16
        case "f17": return .f17
        case "f18": return .f18
        case "f19": return .f19
        case "f20": return .f20
        default: return nil
        }
    }
}
