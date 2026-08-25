package com.duole.engineering.duole_engineering_app

import android.content.Context
import android.net.wifi.WifiManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class MainActivity : FlutterActivity() {
    private val channelName = "com.duole.engineering/platform"
    private val trustPrefix = "trust."
    private val signingAlias = "duole.installation.signing.v1"
    private val sealingAlias = "duole.pairing.credentials.v1"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "acquireMulticastLock" -> {
                            acquireMulticastLock()
                            result.success(null)
                        }
                        "releaseMulticastLock" -> {
                            releaseMulticastLock()
                            result.success(null)
                        }
                        "loadTrustRecords" -> result.success(loadTrustRecords())
                        "saveTrustRecord" -> {
                            val encoded = call.argument<String>("record")
                                ?: throw IllegalArgumentException("trust_record_required")
                            saveTrustRecord(encoded)
                            result.success(null)
                        }
                        "loadOrCreateInstallationIdentity" -> {
                            result.success(loadOrCreateInstallationIdentity())
                        }
                        "savePairingCredentials" -> {
                            val encoded = call.argument<String>("credentials")
                                ?: throw IllegalArgumentException(
                                    "pairing_credentials_required",
                                )
                            savePairingCredentials(encoded)
                            result.success(null)
                        }
                        "loadPairingCredentials" -> {
                            val robotId = call.argument<String>("robot_id")
                                ?: throw IllegalArgumentException("pairing_robot_id_required")
                            result.success(loadPairingCredentials(robotId))
                        }
                        "clearPairingCredentials" -> {
                            val robotId = call.argument<String>("robot_id")
                                ?: throw IllegalArgumentException("pairing_robot_id_required")
                            clearPairingCredentials(robotId)
                            result.success(null)
                        }
                        "signInstallationPayload" -> {
                            val payload = call.argument<String>("payload_base64")
                                ?: throw IllegalArgumentException(
                                    "installation_payload_required",
                                )
                            result.success(signInstallationPayload(payload))
                        }
                        "loadEventCursor" -> {
                            val robotId = call.argument<String>("robot_id")
                                ?: throw IllegalArgumentException("event_cursor_robot_id_required")
                            result.success(loadEventCursor(robotId))
                        }
                        "saveEventCursor" -> {
                            val robotId = call.argument<String>("robot_id")
                                ?: throw IllegalArgumentException("event_cursor_robot_id_required")
                            val seq = call.argument<Number>("seq")?.toLong()
                                ?: throw IllegalArgumentException("event_cursor_seq_required")
                            saveEventCursor(robotId, seq)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error(
                        "platform_operation_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    override fun onStop() {
        releaseMulticastLock()
        super.onStop()
    }

    private fun acquireMulticastLock() {
        val existing = multicastLock
        if (existing != null && existing.isHeld) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE)
            as WifiManager
        val created = wifi.createMulticastLock("duole-app-discovery")
        created.setReferenceCounted(false)
        created.acquire()
        multicastLock = created
    }

    private fun releaseMulticastLock() {
        val existing = multicastLock ?: return
        if (existing.isHeld) existing.release()
        multicastLock = null
    }

    private fun loadTrustRecords(): List<String> {
        val preferences = getSharedPreferences("duole_connection_identity", MODE_PRIVATE)
        return preferences.all.entries
            .filter { it.key.startsWith(trustPrefix) && it.value is String }
            .sortedBy { it.key }
            .map { it.value as String }
    }

    private fun saveTrustRecord(encoded: String) {
        val record = JSONObject(encoded)
        val robotId = record.getString("robot_id")
        val fingerprint = record.getString("device_key_fingerprint")
        val lastPort = record.getInt("last_port")
        if (robotId.isBlank() || robotId.length > 128) {
            throw IllegalArgumentException("trust_robot_id_invalid")
        }
        if (!Regex("^sha256:[0-9a-f]{64}$").matches(fingerprint)) {
            throw IllegalArgumentException("trust_fingerprint_invalid")
        }
        if (lastPort !in 1..65535) {
            throw IllegalArgumentException("trust_port_invalid")
        }
        record.getString("display_name")
        record.getString("confirmed_at")
        record.getString("last_host")
        val preferences = getSharedPreferences("duole_connection_identity", MODE_PRIVATE)
        if (!preferences.edit().putString("$trustPrefix$robotId", encoded).commit()) {
            throw IllegalStateException("trust_store_write_failed")
        }
    }

    private fun loadOrCreateInstallationIdentity(): Map<String, String> {
        val publicKey = installationPublicKey()
        val digest = MessageDigest.getInstance("SHA-256").digest(publicKey)
        val installationId = "ins_${digest.toHex().take(32)}"
        return mapOf(
            "installation_id" to installationId,
            "public_key_base64" to Base64.encodeToString(publicKey, Base64.NO_WRAP),
        )
    }

    private fun installationPublicKey(): ByteArray {
        val keyStore = androidKeyStore()
        if (!keyStore.containsAlias(signingAlias)) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore",
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    signingAlias,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            generator.generateKeyPair()
        }
        return keyStore.getCertificate(signingAlias)?.publicKey?.encoded
            ?: throw IllegalStateException("installation_public_key_unavailable")
    }

    private fun savePairingCredentials(encoded: String) {
        val credentials = validatePairingCredentials(encoded)
        val robotId = credentials.getString("robot_id")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, credentialSealingKey())
        cipher.updateAAD(robotId.toByteArray(StandardCharsets.UTF_8))
        val ciphertext = cipher.doFinal(encoded.toByteArray(StandardCharsets.UTF_8))
        val sealed = JSONObject()
            .put("version", 1)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .toString()
        val storageKey = "credentials.${sha256Hex(robotId)}"
        val preferences = getSharedPreferences("duole_pairing_ciphertext", MODE_PRIVATE)
        if (!preferences.edit().putString(storageKey, sealed).commit()) {
            throw IllegalStateException("pairing_credentials_write_failed")
        }
    }

    private fun loadPairingCredentials(robotId: String): String? {
        if (robotId.isBlank() || robotId.length > 128) {
            throw IllegalArgumentException("pairing_robot_id_invalid")
        }
        val storageKey = "credentials.${sha256Hex(robotId)}"
        val sealed = getSharedPreferences("duole_pairing_ciphertext", MODE_PRIVATE)
            .getString(storageKey, null)
            ?: return null
        val wrapper = JSONObject(sealed)
        if (wrapper.getInt("version") != 1) {
            throw IllegalStateException("pairing_ciphertext_version_invalid")
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = Base64.decode(wrapper.getString("iv"), Base64.NO_WRAP)
        val ciphertext = Base64.decode(
            wrapper.getString("ciphertext"),
            Base64.NO_WRAP,
        )
        cipher.init(
            Cipher.DECRYPT_MODE,
            credentialSealingKey(),
            javax.crypto.spec.GCMParameterSpec(128, iv),
        )
        cipher.updateAAD(robotId.toByteArray(StandardCharsets.UTF_8))
        val encoded = String(
            cipher.doFinal(ciphertext),
            StandardCharsets.UTF_8,
        )
        val credentials = validatePairingCredentials(encoded)
        if (credentials.getString("robot_id") != robotId) {
            throw IllegalStateException("pairing_credentials_robot_mismatch")
        }
        return credentials.toString()
    }

    private fun clearPairingCredentials(robotId: String) {
        if (robotId.isBlank() || robotId.length > 128) {
            throw IllegalArgumentException("pairing_robot_id_invalid")
        }
        val storageKey = "credentials.${sha256Hex(robotId)}"
        val preferences = getSharedPreferences("duole_pairing_ciphertext", MODE_PRIVATE)
        if (!preferences.edit().remove(storageKey).commit()) {
            throw IllegalStateException("pairing_credentials_clear_failed")
        }
    }

    private fun signInstallationPayload(payloadBase64: String): String {
        val payload = Base64.decode(payloadBase64, Base64.NO_WRAP)
        if (payload.isEmpty() || payload.size > 2048) {
            throw IllegalArgumentException("installation_payload_invalid")
        }
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(installationPrivateKey())
        signer.update(payload)
        return Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
    }

    private fun loadEventCursor(robotId: String): Long? {
        validateRobotId(robotId)
        val key = "cursor.${sha256Hex(robotId)}"
        val preferences = getSharedPreferences("duole_event_cursors", MODE_PRIVATE)
        return if (preferences.contains(key)) preferences.getLong(key, -1L) else null
    }

    private fun saveEventCursor(robotId: String, seq: Long) {
        validateRobotId(robotId)
        if (seq < 0) throw IllegalArgumentException("event_cursor_seq_invalid")
        val key = "cursor.${sha256Hex(robotId)}"
        val preferences = getSharedPreferences("duole_event_cursors", MODE_PRIVATE)
        if (!preferences.edit().putLong(key, seq).commit()) {
            throw IllegalStateException("event_cursor_write_failed")
        }
    }

    private fun validateRobotId(robotId: String) {
        if (!Regex("^[A-Za-z0-9._:-]{1,128}$").matches(robotId)) {
            throw IllegalArgumentException("robot_id_invalid")
        }
    }

    private fun installationPrivateKey(): PrivateKey {
        installationPublicKey()
        return androidKeyStore().getKey(signingAlias, null) as? PrivateKey
            ?: throw IllegalStateException("installation_private_key_unavailable")
    }

    private fun validatePairingCredentials(encoded: String): JSONObject {
        val value = JSONObject(encoded)
        val robotId = value.getString("robot_id")
        val sessionId = value.getString("device_session_id")
        val installationId = value.getString("installation_id")
        val accessToken = value.getString("access_token")
        val refreshToken = value.getString("refresh_token")
        val expiresAt = value.getString("expires_at")
        val scopes = value.getJSONArray("scopes")
        if (robotId.isBlank() || robotId.length > 128) {
            throw IllegalArgumentException("pairing_robot_id_invalid")
        }
        if (!Regex("^dvs_[0-9a-f]{32}$").matches(sessionId)) {
            throw IllegalArgumentException("pairing_session_id_invalid")
        }
        if (installationId != loadOrCreateInstallationIdentity()["installation_id"]) {
            throw IllegalArgumentException("pairing_installation_mismatch")
        }
        if (accessToken.isBlank() || accessToken.length > 512 ||
            refreshToken.isBlank() || refreshToken.length > 512
        ) {
            throw IllegalArgumentException("pairing_token_invalid")
        }
        if (expiresAt.isBlank() || scopes.length() == 0) {
            throw IllegalArgumentException("pairing_metadata_invalid")
        }
        return value
    }

    private fun credentialSealingKey(): SecretKey {
        val keyStore = androidKeyStore()
        if (!keyStore.containsAlias(sealingAlias)) {
            val generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore",
            )
            generator.init(
                KeyGenParameterSpec.Builder(
                    sealingAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generator.generateKey()
        }
        return keyStore.getKey(sealingAlias, null) as? SecretKey
            ?: throw IllegalStateException("credential_sealing_key_unavailable")
    }

    private fun androidKeyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(StandardCharsets.UTF_8))
            .toHex()

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
