package eu.rjuhas.rjtracker.android.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import eu.rjuhas.rjtracker.android.data.AddressResolver

/** Address text for a position: the server's address, else resolved on the phone. */
data class AddressText(val text: String?, val loading: Boolean)

@Composable
fun rememberAddress(lat: Double?, lon: Double?, serverAddress: String?): AddressText {
    val context = LocalContext.current
    if (!serverAddress.isNullOrBlank()) return AddressText(serverAddress, false)
    if (lat == null || lon == null) return AddressText(null, false)
    var resolved by remember(lat, lon) { mutableStateOf(AddressResolver.cached(lat, lon)) }
    var done by remember(lat, lon) { mutableStateOf(resolved != null) }
    LaunchedEffect(lat, lon) {
        if (resolved == null) {
            resolved = AddressResolver.resolve(context, lat, lon)
            done = true
        }
    }
    return when {
        resolved != null -> AddressText(resolved, false)
        !done -> AddressText(null, true)
        else -> AddressText(AddressResolver.coordinates(lat, lon), false)
    }
}
