package com.example.captura_mobile.ar

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.BigInteger

/**
 * Minimal JSON writer for the capture result. Doubles always keep a decimal point so they parse
 * back as doubles; non-finite numbers are rejected instead of being written as fictitious values.
 */
object JsonWriter {
    fun write(value: Any?): String = StringBuilder().also { append(it, value) }.toString()

    private fun append(out: StringBuilder, value: Any?) {
        when (value) {
            null -> out.append("null")
            is String -> appendString(out, value)
            is Boolean -> out.append(value)
            is Int, is Long, is Short, is Byte -> out.append(value.toString())
            is Double -> appendDouble(out, value)
            is Float -> appendDouble(out, value.toDouble())
            is Map<*, *> -> {
                out.append('{')
                var first = true
                for ((key, item) in value) {
                    if (!first) out.append(',')
                    first = false
                    appendString(out, key.toString())
                    out.append(':')
                    append(out, item)
                }
                out.append('}')
            }
            is Iterable<*> -> {
                out.append('[')
                var first = true
                for (item in value) {
                    if (!first) out.append(',')
                    first = false
                    append(out, item)
                }
                out.append(']')
            }
            else -> throw IllegalArgumentException("Unsupported JSON value: ${value::class.java.name}")
        }
    }

    private fun appendDouble(out: StringBuilder, value: Double) {
        require(value.isFinite()) { "Non-finite number cannot be written to JSON: $value" }
        val text = value.toString()
        out.append(text)
        if (!text.contains('.') && !text.contains('E') && !text.contains('e')) out.append(".0")
    }

    private fun appendString(out: StringBuilder, value: String) {
        out.append('"')
        for (ch in value) {
            when (ch) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (ch < ' ') out.append(String.format("\\u%04x", ch.code)) else out.append(ch)
            }
        }
        out.append('"')
    }
}

/**
 * Parses JSON into plain Kotlin values supported by Flutter's StandardMethodCodec:
 * Map, List, String, Boolean, Int, Long, Double and null.
 */
object JsonReader {
    fun parse(json: String): Any? {
        val trimmed = json.trim()
        return if (trimmed.startsWith("[")) toPlain(JSONArray(trimmed)) else toPlain(JSONObject(trimmed))
    }

    private fun toPlain(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> {
            val map = LinkedHashMap<String, Any?>()
            val keys = value.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = toPlain(value.opt(key))
            }
            map
        }
        is JSONArray -> (0 until value.length()).map { toPlain(value.opt(it)) }
        is Int, is Boolean, is String -> value
        is Long -> if (value in Int.MIN_VALUE..Int.MAX_VALUE) value.toInt() else value
        is BigInteger -> value.toLong()
        is BigDecimal -> value.toDouble()
        is Double -> value
        is Float -> value.toDouble()
        is Number -> value.toDouble()
        else -> value.toString()
    }
}
