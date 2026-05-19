import Foundation
import CoreGraphics

public enum KeycodeMap {
    public static func macKeyCode(forAndroidKeycode keycode: UInt16) -> CGKeyCode? {
        switch keycode {
        case 4:   return 0x35   // ESCAPE (Android KEYCODE_BACK → Esc as approximation)
        case 19:  return 0x7E   // DPAD_UP
        case 20:  return 0x7D   // DPAD_DOWN
        case 21:  return 0x7B   // DPAD_LEFT
        case 22:  return 0x7C   // DPAD_RIGHT
        case 23:  return 0x24   // DPAD_CENTER → Return
        case 61:  return 0x30   // TAB
        case 62:  return 0x31   // SPACE
        case 66:  return 0x24   // ENTER
        case 67:  return 0x33   // DEL → Delete (backspace)
        case 92:  return 0x74   // PAGE_UP
        case 93:  return 0x79   // PAGE_DOWN
        case 111: return 0x35   // ESCAPE
        case 112: return 0x75   // FORWARD_DEL
        case 113, 114: return 0x3B  // CTRL_LEFT/RIGHT
        case 117, 118: return 0x37  // META_LEFT/RIGHT (Cmd)
        case 122: return 0x73   // MOVE_HOME
        case 123: return 0x77   // MOVE_END
        case 131...142: return CGKeyCode(0x7A + UInt16(keycode - 131))   // F1..F12
        case 7:  return 0x1D    // 0
        case 8:  return 0x12    // 1
        case 9:  return 0x13    // 2
        case 10: return 0x14    // 3
        case 11: return 0x15    // 4
        case 12: return 0x17    // 5
        case 13: return 0x16    // 6
        case 14: return 0x1A    // 7
        case 15: return 0x1C    // 8
        case 16: return 0x19    // 9
        case 29...54:   return CGKeyCode(asciiToMac(keycode: keycode))
        default: return nil
        }
    }

    private static func asciiToMac(keycode: UInt16) -> UInt16 {
        let letter = Character(UnicodeScalar(UInt32(keycode - 29 + 97))!)
        let map: [Character: UInt16] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03,
            "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
            "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F,
            "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
            "y": 0x10, "z": 0x06
        ]
        return map[letter] ?? 0
    }
}
