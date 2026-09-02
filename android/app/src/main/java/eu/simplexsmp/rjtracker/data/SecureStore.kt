package eu.simplexsmp.rjtracker.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import eu.simplexsmp.rjtracker.model.SavedShare
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStore(context: Context) {
    private val prefs = context.getSharedPreferences("rj_tracker_share_secure", Context.MODE_PRIVATE)

    fun loadShares(): List<SavedShare> {
        val encrypted = prefs.getString(KEY_SHARES, null) ?: return emptyList()
        val plaintext = runCatching { decrypt(encrypted) }.getOrNull() ?: return emptyList()
        return runCatching {
            val array = JSONArray(plaintext)
            buildList {
                for (i in 0 until array.length()) {
                    val item = array.optJSONObject(i) ?: continue
                    val id = item.optString("id")
                    val shareUrl = item.optString("shareUrl")
                    val baseUrl = item.optString("baseUrl")
                    val linkId = item.optString("linkId")
                    if (id.isBlank() || shareUrl.isBlank() || baseUrl.isBlank() || linkId.isBlank()) continue
                    add(
                        SavedShare(
                            id = id,
                            shareUrl = shareUrl,
                            baseUrl = baseUrl,
                            linkId = linkId,
                            password = item.optString("password"),
                            title = item.optString("title", "Geteilter Tracker"),
                            emoji = item.optString("emoji", "📍"),
                            addedAt = item.optLong("addedAt", 0L),
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    fun saveShares(shares: List<SavedShare>) {
        val array = JSONArray()
        shares.forEach { share ->
            array.put(
                JSONObject()
                    .put("id", share.id)
                    .put("shareUrl", share.shareUrl)
                    .put("baseUrl", share.baseUrl)
                    .put("linkId", share.linkId)
                    .put("password", share.password)
                    .put("title", share.title)
                    .put("emoji", share.emoji)
                    .put("addedAt", share.addedAt)
            )
        }
        prefs.edit().putString(KEY_SHARES, encrypt(array.toString())).apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + "." +
            Base64.encodeToString(ciphertext, Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val separator = value.indexOf('.')
        require(separator > 0) { "Invalid encrypted payload" }
        val iv = Base64.decode(value.substring(0, separator), Base64.NO_WRAP)
        val ciphertext = Base64.decode(value.substring(separator + 1), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private companion object {
        const val KEY_ALIAS = "rj_tracker_share_aes_v1"
        const val KEY_SHARES = "shares_v1"
    }
}
