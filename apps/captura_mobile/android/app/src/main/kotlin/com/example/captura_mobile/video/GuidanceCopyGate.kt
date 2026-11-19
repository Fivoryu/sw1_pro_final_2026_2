package com.example.captura_mobile.video

/** Main-thread ownership of preview-only copy requests. No Camera2/recorder operations.
 * PixelCopy has no cancellation API: expired native copies keep their own bitmap until their
 * callback. At most two requests may exist, allowing one recovery copy without an unbounded
 * queue of buffers if the platform never calls back. Never reuse a timed-out destination.
 */
internal class GuidanceCopyGate(
    val timeoutMs: Long = 2000,
    private val maxPending: Int = 2,
) {
    data class Ticket(val id: Long, val deadlineMs: Long)
    private val pending = mutableMapOf<Long, Ticket>()
    private val expired = mutableSetOf<Long>()
    private var nextId = 0L
    private var active: Long? = null
    private var closed = false

    init { require(timeoutMs > 0 && maxPending in 1..2) }

    val pendingCount: Int get() = pending.size
    val copying: Boolean get() = active != null

    fun begin(nowMs: Long): Ticket? {
        if (closed || active != null || pending.size >= maxPending) return null
        val ticket = Ticket(++nextId, nowMs + timeoutMs)
        pending[ticket.id] = ticket
        active = ticket.id
        return ticket
    }

    fun expire(ticket: Ticket, nowMs: Long): Boolean {
        if (pending[ticket.id] != ticket || nowMs < ticket.deadlineMs || ticket.id in expired) return false
        expired.add(ticket.id)
        if (active == ticket.id) active = null
        return true
    }

    /** Removes ownership exactly once, even for a late callback after timeout/pause/close. */
    fun finish(ticket: Ticket, nowMs: Long): Boolean {
        val owned = pending.remove(ticket.id) ?: return false
        val timedOut = expired.remove(ticket.id)
        if (active == ticket.id) active = null
        return !closed && !timedOut && nowMs < owned.deadlineMs
    }

    fun owns(ticket: Ticket): Boolean = pending[ticket.id] == ticket

    fun close() {
        closed = true
        active = null
        expired.addAll(pending.keys)
    }
}
