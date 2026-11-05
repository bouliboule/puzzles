package io.ricca.puzzles

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/** Key/value persistence, same keys as the web app's localStorage ("pz:" prefix dropped). */
class Store(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("pz", Context.MODE_PRIVATE)

    fun str(k: String): String? = sp.getString(k, null)
    fun json(k: String): JSONObject? = str(k)?.let { runCatching { JSONObject(it) }.getOrNull() }
    fun set(k: String, v: String) = sp.edit().putString(k, v).apply()
    fun set(k: String, v: JSONObject) = set(k, v.toString())
    fun del(k: String) = sp.edit().remove(k).apply()
}

/** Per-puzzle progress for the current game. */
data class Meta(
    var params: String,
    var label: String = "",
    var elapsed: Double = 0.0,
    var solved: Boolean = false,
    var helped: Boolean = false,
) {
    fun toJson() = JSONObject().put("params", params).put("label", label)
        .put("elapsed", elapsed).put("solved", solved).put("helped", helped)

    companion object {
        fun from(o: JSONObject?, defaultParams: String) = Meta(
            params = o?.optString("params")?.takeIf { it.isNotEmpty() } ?: defaultParams,
            label = o?.optString("label") ?: "",
            elapsed = o?.optDouble("elapsed", 0.0) ?: 0.0,
            solved = o?.optBoolean("solved") ?: false,
            helped = o?.optBoolean("helped") ?: false,
        )
    }
}
