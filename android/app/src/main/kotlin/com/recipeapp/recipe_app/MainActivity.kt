package com.recipeapp.recipe_app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "recipe_app/saf"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "takePersistablePermission" -> {
                        val uriStr = call.argument<String>("treeUri")!!
                        takePersistablePermission(uriStr)
                        result.success(true)
                    }
                    "listFiles" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val subDir = call.argument<String>("subDir")
                        result.success(listFiles(treeUri, subDir))
                    }
                    "readFile" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val subDir = call.argument<String>("subDir")!!
                        val fileName = call.argument<String>("fileName")!!
                        result.success(readFile(treeUri, subDir, fileName))
                    }
                    "writeFile" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val subDir = call.argument<String>("subDir")!!
                        val fileName = call.argument<String>("fileName")!!
                        val content = call.argument<ByteArray>("content")!!
                        result.success(writeFile(treeUri, subDir, fileName, content))
                    }
                    "createDirectory" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val name = call.argument<String>("name")!!
                        result.success(createDirectory(treeUri, name))
                    }
                    "deleteFile" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val subDir = call.argument<String>("subDir")!!
                        val fileName = call.argument<String>("fileName")!!
                        result.success(deleteFile(treeUri, subDir, fileName))
                    }
                    "deleteDirectory" -> {
                        val treeUri = call.argument<String>("treeUri")!!
                        val name = call.argument<String>("name")!!
                        result.success(deleteDirectory(treeUri, name))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("SAF_ERROR", e.message, null)
            }
        }
    }

    private fun takePersistablePermission(uriStr: String) {
        val uri = Uri.parse(uriStr)
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        contentResolver.takePersistableUriPermission(uri, flags)
    }

    private fun getTreeDocId(treeUri: Uri): String =
        DocumentsContract.getTreeDocumentId(treeUri)

    private fun findDocId(treeUri: Uri, parentDocId: String, name: String): String? {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME
        )
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) return cursor.getString(0)
            }
        }
        return null
    }

    private fun listFiles(treeUriStr: String, subDir: String?): List<Map<String, Any>> {
        val treeUri = Uri.parse(treeUriStr)
        val treeDocId = getTreeDocId(treeUri)
        val parentDocId = if (subDir != null) {
            findDocId(treeUri, treeDocId, subDir) ?: return emptyList()
        } else {
            treeDocId
        }
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        val result = mutableListOf<Map<String, Any>>()
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(0) ?: continue
                val mimeType = cursor.getString(1) ?: ""
                result.add(mapOf(
                    "name" to name,
                    "isDirectory" to (mimeType == DocumentsContract.Document.MIME_TYPE_DIR),
                    "mimeType" to mimeType
                ))
            }
        }
        return result
    }

    private fun resolveDocId(treeUri: Uri, subDir: String): String? {
        val treeDocId = getTreeDocId(treeUri)
        return findDocId(treeUri, treeDocId, subDir)
    }

    private fun readFile(treeUriStr: String, subDir: String, fileName: String): ByteArray? {
        val treeUri = Uri.parse(treeUriStr)
        val dirDocId = resolveDocId(treeUri, subDir) ?: return null
        val fileDocId = findDocId(treeUri, dirDocId, fileName) ?: return null
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, fileDocId)
        return contentResolver.openInputStream(docUri)?.use { it.readBytes() }
    }

    private fun writeFile(treeUriStr: String, subDir: String, fileName: String, content: ByteArray): Boolean {
        val treeUri = Uri.parse(treeUriStr)
        val dirDocId = resolveDocId(treeUri, subDir) ?: return false
        val existingDocId = findDocId(treeUri, dirDocId, fileName)
        val docUri = if (existingDocId != null) {
            DocumentsContract.buildDocumentUriUsingTree(treeUri, existingDocId)
        } else {
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, dirDocId)
            DocumentsContract.createDocument(contentResolver, parentUri, "text/markdown", fileName)
                ?: return false
        }
        contentResolver.openOutputStream(docUri)?.use {
            it.write(content)
            return true
        }
        return false
    }

    private fun createDirectory(treeUriStr: String, name: String): Boolean {
        val treeUri = Uri.parse(treeUriStr)
        val treeDocId = getTreeDocId(treeUri)
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
        return DocumentsContract.createDocument(
            contentResolver, parentUri, DocumentsContract.Document.MIME_TYPE_DIR, name
        ) != null
    }

    private fun deleteFile(treeUriStr: String, subDir: String, fileName: String): Boolean {
        val treeUri = Uri.parse(treeUriStr)
        val dirDocId = resolveDocId(treeUri, subDir) ?: return false
        val fileDocId = findDocId(treeUri, dirDocId, fileName) ?: return false
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, fileDocId)
        return DocumentsContract.deleteDocument(contentResolver, docUri)
    }

    private fun deleteDirectory(treeUriStr: String, name: String): Boolean {
        val treeUri = Uri.parse(treeUriStr)
        val treeDocId = getTreeDocId(treeUri)
        val dirDocId = findDocId(treeUri, treeDocId, name) ?: return false
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, dirDocId)
        return DocumentsContract.deleteDocument(contentResolver, docUri)
    }
}
