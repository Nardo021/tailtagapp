package com.josh.tailtag.data

import android.content.SharedPreferences
import java.io.IOException

internal interface KeyValueStore {
    @Throws(IOException::class)
    fun getString(key: String): String?

    /** Applies every edit or leaves the previous values in place. Must not run on the main thread. */
    fun commit(edits: Map<String, String?>): Boolean
}

internal class SharedPreferencesKeyValueStore(
    private val preferences: SharedPreferences,
) : KeyValueStore {
    override fun getString(key: String): String? = preferences.getString(key, null)

    override fun commit(edits: Map<String, String?>): Boolean {
        val editor = preferences.edit()
        for ((key, value) in edits) {
            if (value == null) editor.remove(key) else editor.putString(key, value)
        }
        return editor.commit()
    }
}
