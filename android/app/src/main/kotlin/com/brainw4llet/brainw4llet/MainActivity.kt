package com.brainw4llet.brainw4llet

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // O file_selector não tem "salvar arquivo" no Android. Aqui o sistema abre o
    // "Salvar como" (ACTION_CREATE_DOCUMENT) e o app grava só no documento que o
    // usuário escolher: nenhuma permissão de armazenamento é necessária.
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContent: ByteArray? = null

    @Suppress("DEPRECATION")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                val content = call.argument<String>("content")
                if (name == null || content == null) {
                    result.error("bad_args", "Nome ou conteúdo ausente.", null)
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "Já existe um \"Salvar como\" aberto.", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingContent = content.toByteArray(Charsets.UTF_8)
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, name)
                }
                startActivityForResult(intent, REQUEST_SAVE)
            }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_SAVE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
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
            result.error("write_failed", e.message, null)
        }
    }

    private companion object {
        const val CHANNEL = "com.brainw4llet.brainw4llet/files"
        const val REQUEST_SAVE = 7741
    }
}
