package eu.rjuhas.rjtracker.android.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.builtins.ListSerializer

private val Context.store by preferencesDataStore("rjtracker")

class LinkRepository(private val context: Context) {
    private val linksKey = stringPreferencesKey("links_v1")
    private val introKey = booleanPreferencesKey("intro_done")
    private val serializer = ListSerializer(SavedLink.serializer())

    val links: Flow<List<SavedLink>> = context.store.data.map { prefs ->
        prefs[linksKey]?.let { runCatching { Api.json.decodeFromString(serializer, it) }.getOrNull() } ?: emptyList()
    }
    val introDone: Flow<Boolean> = context.store.data.map { it[introKey] ?: false }

    suspend fun current(): List<SavedLink> = links.first()
    suspend fun find(id: String): SavedLink? = current().firstOrNull { it.id == id }

    suspend fun upsert(link: SavedLink) = update { list -> list.filterNot { it.id == link.id } + link }
    suspend fun remove(id: String) = update { list -> list.filterNot { it.id == id } }
    suspend fun modify(id: String, change: (SavedLink) -> SavedLink) = update { list -> list.map { if (it.id == id) change(it) else it } }
    suspend fun setIntroDone() = context.store.edit { it[introKey] = true }

    private suspend fun update(transform: (List<SavedLink>) -> List<SavedLink>) {
        context.store.edit { prefs ->
            val current = prefs[linksKey]?.let { runCatching { Api.json.decodeFromString(serializer, it) }.getOrNull() } ?: emptyList()
            prefs[linksKey] = Api.json.encodeToString(serializer, transform(current))
        }
    }
}
