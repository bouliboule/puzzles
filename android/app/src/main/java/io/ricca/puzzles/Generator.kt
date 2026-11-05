package io.ricca.puzzles

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Generates puzzles off the main thread with drawing-less midends, and
 * keeps one ready-made puzzle per type ("<name>:next") so New game is
 * instant. Plays the role of web/js/gen-worker.js.
 */
class Generator(private val store: Store) {
    private val thread = Executors.newSingleThreadExecutor { r -> Thread(r, "puzzle-gen").apply { isDaemon = true } }
        .asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + thread)
    private val handles = HashMap<String, Long>()   // only touched on `thread`

    private fun generate(name: String, params: String): String {
        val h = handles.getOrPut(name) { Native.create(name, null) }
        return Native.generate(h, params).ifEmpty { throw IllegalArgumentException("Invalid parameters: $params") }
    }

    /** A game ID for name/params, using the prefetched one if it matches. */
    suspend fun take(name: String, params: String): String {
        val next = store.json("$name:next")
        if (next != null && next.optString("params") == params && next.optString("gameId").isNotEmpty()) {
            store.del("$name:next")
            return next.getString("gameId")
        }
        return withContext(thread) { generate(name, params) }
    }

    fun prefetch(name: String, params: String) {
        if (store.json("$name:next")?.optString("params") == params) return
        scope.launch {
            runCatching { generate(name, params) }.onSuccess {
                store.set("$name:next", JSONObject().put("params", params).put("gameId", it))
            }
        }
    }
}
