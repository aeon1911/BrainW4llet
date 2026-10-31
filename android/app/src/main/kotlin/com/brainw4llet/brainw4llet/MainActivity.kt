package com.brainw4llet.brainw4llet

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    // O file_selector não tem "salvar arquivo" no Android, e o "abrir" dele derruba
    // o app quando o provedor de arquivos do sistema falha (visto no Waydroid:
    // NullPointerException vindo do MediaProvider). Aqui o sistema abre o seletor
    // (ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT), o app lê ou grava só o
    // documento escolhido e qualquer falha volta ao Dart como erro. Nenhuma
    // permissão de armazenamento é necessária.
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContent: ByteArray? = null
    private var pendingCompat = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveText" -> startSave(call, result)
                    "openText" -> startOpen(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startSave(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val content = call.argument<String>("content")
        if (name == null || content == null) {
            result.error("bad_args", "Nome ou conteúdo ausente.", null)
            return
        }
        if (!claim(result)) return
        pendingContent = content.toByteArray(Charsets.UTF_8)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        launch(intent, REQUEST_SAVE)
    }

    private fun startOpen(call: MethodCall, result: MethodChannel.Result) {
        if (!claim(result)) return
        // Modo compatível: depois que a leitura normal falhou, ou direto no
        // Waydroid, onde ela sempre falha. Pede também a permissão de escrita no
        // documento escolhido, para poder abri-lo em "rw".
        pendingCompat = (call.argument<Boolean>("compat") ?: false) || isWaydroid()
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            if (pendingCompat) {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
        }
        launch(intent, REQUEST_OPEN)
    }

    /** O Waydroid se anuncia como "waydroid" na marca, no modelo e no dispositivo. */
    private fun isWaydroid(): Boolean =
        listOf(Build.BRAND, Build.MANUFACTURER, Build.MODEL, Build.DEVICE, Build.PRODUCT)
            .any { it.contains("waydroid", ignoreCase = true) }

    /** Só um seletor aberto por vez. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "Já existe um seletor de arquivos aberto.", null)
            return false
        }
        pendingResult = result
        return true
    }

    @Suppress("DEPRECATION")
    private fun launch(intent: Intent, requestCode: Int) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            val result = pendingResult
            pendingResult = null
            pendingContent = null
            pendingCompat = false
            result?.error("no_picker", "Este aparelho não tem seletor de arquivos.", null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQUEST_SAVE -> finishSave(resultCode, data)
            REQUEST_OPEN -> finishOpen(resultCode, data)
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    private fun finishSave(resultCode: Int, data: Intent?) {
        val result = pendingResult
        val content = pendingContent
        pendingResult = null
        pendingContent = null
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || content == null) {
            result.success(null) // cancelou
            return
        }
        try {
            val stream = contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Não foi possível abrir o arquivo.")
            stream.use { it.write(content) }
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("write_failed", describe(e), null)
        }
    }

    private fun finishOpen(resultCode: Int, data: Intent?) {
        val result = pendingResult
        val compat = pendingCompat
        pendingResult = null
        pendingCompat = false
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // cancelou
            return
        }
        // Fora da thread principal, e com qualquer falha do provedor do sistema
        // devolvida como erro: antes, o plugin deixava a exceção derrubar o app.
        Thread {
            try {
                val text = String(readLimited(uri, compat), Charsets.UTF_8)
                runOnUiThread { result.success(text) }
            } catch (e: Exception) {
                runOnUiThread { result.error("read_failed", describe(e), null) }
            }
        }.start()
    }

    private fun readLimited(uri: Uri, compat: Boolean): ByteArray {
        try {
            val stream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("O Android não abriu o arquivo.")
            return stream.use { readAtMost(it) }
        } catch (first: TooLargeException) {
            throw first
        } catch (first: Exception) {
            if (!compat) throw first
            // No Waydroid, a leitura em modo "r" falha dentro do MediaProvider
            // (NullPointerException). O modo "rw" não passa por esse caminho. O
            // app só lê: nada é escrito no arquivo.
            val pfd: ParcelFileDescriptor? = try {
                contentResolver.openFileDescriptor(uri, "rw")
            } catch (second: Exception) {
                throw IllegalStateException(
                    "${describe(first)} / modo compatível: ${describe(second)}"
                )
            }
            if (pfd == null) throw first
            return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { readAtMost(it) }
        }
    }

    private fun readAtMost(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            if (out.size() + n > MAX_BYTES) throw TooLargeException()
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }

    private class TooLargeException :
        Exception("Arquivo grande demais para ser do BrainW4llet.")

    private fun describe(e: Exception): String {
        val name = e.javaClass.simpleName
        return if (e.message.isNullOrBlank()) name else "$name: ${e.message}"
    }

    private companion object {
        const val CHANNEL = "com.brainw4llet.brainw4llet/files"
        const val REQUEST_SAVE = 7741
        const val REQUEST_OPEN = 7742
        const val MAX_BYTES = 8 * 1024 * 1024
    }
}
