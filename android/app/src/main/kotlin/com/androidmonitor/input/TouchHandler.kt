package com.androidmonitor.input

import android.view.MotionEvent
import android.view.View
import com.androidmonitor.connection.PacketWriter
import com.androidmonitor.connection.TouchAction
import com.androidmonitor.connection.TouchPacket

class TouchHandler(private val writer: PacketWriter) : View.OnTouchListener {
    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val width = view.width.coerceAtLeast(1).toFloat()
        val height = view.height.coerceAtLeast(1).toFloat()
        val pointerIndex = event.actionIndex
        val pointerId = event.getPointerId(pointerIndex).toByte()
        val action = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> TouchAction.DOWN
            MotionEvent.ACTION_MOVE -> TouchAction.MOVE
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> TouchAction.UP
            MotionEvent.ACTION_CANCEL -> TouchAction.CANCEL
            else -> return false
        }
        if (action == TouchAction.MOVE) {
            for (i in 0 until event.pointerCount) {
                emit(event, i, width, height, action, event.getPointerId(i).toByte())
            }
        } else {
            emit(event, pointerIndex, width, height, action, pointerId)
        }
        return true
    }

    private fun emit(event: MotionEvent, idx: Int, w: Float, h: Float, action: TouchAction, id: Byte) {
        val x = (event.getX(idx) / w).coerceIn(0f, 1f)
        val y = (event.getY(idx) / h).coerceIn(0f, 1f)
        val pressure = event.getPressure(idx).coerceIn(0f, 1f)
        writer.touch(TouchPacket(action, id, x, y, pressure))
    }
}
