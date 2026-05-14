package com.androidmonitor.input

import android.view.KeyEvent
import com.androidmonitor.connection.KeyAction
import com.androidmonitor.connection.KeyModifiers
import com.androidmonitor.connection.KeyPacket
import com.androidmonitor.connection.PacketWriter

class KeyboardHandler(private val writer: PacketWriter) {
    fun handleHardwareKey(event: KeyEvent): Boolean {
        val action = when (event.action) {
            KeyEvent.ACTION_DOWN -> KeyAction.DOWN
            KeyEvent.ACTION_UP -> KeyAction.UP
            else -> return false
        }
        val mods = modifiersFromEvent(event)
        val unicode = event.unicodeChar
        writer.key(KeyPacket(action, mods, event.keyCode.toShort(), unicode))
        return true
    }

    fun handleTextInput(text: CharSequence) {
        for (codepoint in text.codePoints()) {
            writer.key(KeyPacket(KeyAction.DOWN, 0, 0, codepoint))
            writer.key(KeyPacket(KeyAction.UP, 0, 0, codepoint))
        }
    }

    private fun modifiersFromEvent(event: KeyEvent): Byte {
        var mods = 0
        if (event.isShiftPressed) mods = mods or KeyModifiers.SHIFT.toInt()
        if (event.isCtrlPressed) mods = mods or KeyModifiers.CTRL.toInt()
        if (event.isAltPressed) mods = mods or KeyModifiers.ALT.toInt()
        if (event.isMetaPressed) mods = mods or KeyModifiers.META.toInt()
        return mods.toByte()
    }
}
