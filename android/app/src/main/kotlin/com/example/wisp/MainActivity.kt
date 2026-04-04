package com.wizeshi.wisp

import android.os.Bundle
import android.os.Build
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream
import java.util.concurrent.TimeUnit

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val TAG = "YtDlp"
        private const val NODE_ASSET_ROOT = "node-bin"
        private val NATIVE_NODE_CANDIDATES = listOf(
            "node",
            "libnode_exec.so",
            "libnode_bin.so",
            "libnode.so"
        )
    }

    private val preparedAssetLibAbis = mutableSetOf<String>()
    private val jsRuntimeLock = Any()

    @Volatile
    private var cachedJsRuntimes: String? = null

    private data class NodeRuntime(
        val nodeBinary: File,
        val libDir: File,
        val source: String,
    )


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wizeshi.wisp/ytdlp").setMethodCallHandler { call, result ->
            when (call.method) {
                "getStreamUrl" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId == null) {
                        result.error("INVALID_ARGUMENT", "videoId is required", null)
                        return@setMethodCallHandler
                    }
                    
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            val url = getStreamUrl(videoId)
                            result.success(url)
                        } catch (e: Exception) {
                            result.error("YT_DLP_ERROR", e.message, e.toString())
                        }
                    }
                }
                "updateYtDlp" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            updateYtDlp()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UPDATE_ERROR", e.message, e.toString())
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val selectedRuntime = resolveJsRuntimesOption()
                Log.i(TAG, "Startup JS runtime probe complete: $selectedRuntime")
            } catch (e: Exception) {
                Log.w(TAG, "Startup JS runtime probe failed", e)
            }
        }
    }

    private suspend fun getStreamUrl(videoId: String): String = withContext(Dispatchers.IO) {
        val request = YoutubeDLRequest("https://www.youtube.com/watch?v=$videoId")
        // Request m4a/AAC format which has better Android compatibility than webm/opus
        request.addOption("-f", "140/bestaudio[ext=m4a]/bestaudio")
        val jsRuntimes = buildJsRuntimesOption()
        request.addOption("--js-runtimes", jsRuntimes)
        request.addOption("--print", "%(url)s")
        request.addOption("--no-playlist")
        request.addOption("--skip-download")
        Log.i(TAG, "Using JS runtimes: $jsRuntimes")
        
        val response = YoutubeDL.getInstance().execute(request)
        val url = response.out.trim()
        
        Log.d(TAG, "Raw output length: ${response.out.length}")
        Log.d(TAG, "URL length: ${url.length}")
        Log.d(TAG, "URL ends with: ${url.takeLast(20)}")
        
        if (url.isEmpty()) {
            throw Exception("No stream URL returned")
        }
        
        url
    }

    private fun buildJsRuntimesOption(): String {
        cachedJsRuntimes?.let { return it }

        synchronized(jsRuntimeLock) {
            cachedJsRuntimes?.let { return it }

            val selected = resolveJsRuntimesOption()
            cachedJsRuntimes = selected
            return selected
        }
    }

    private fun resolveJsRuntimesOption(): String {
        val nodeRuntime = ensureNodeRuntime()
        if (nodeRuntime == null) {
            Log.w(TAG, "Node runtime unavailable, falling back to quickjs")
            return "quickjs"
        }

        Log.i(TAG, "Node runtime ready from ${nodeRuntime.source}: ${nodeRuntime.nodeBinary.absolutePath}")
        return "node:${nodeRuntime.nodeBinary.absolutePath},quickjs"
    }

    private fun ensureNodeRuntime(): NodeRuntime? {
        val assetAbi = resolveAssetAbi()

        val nativeRuntime = resolveNativeLibraryRuntime(assetAbi)
        if (nativeRuntime != null && verifyNodeRuntime(nativeRuntime)) {
            return nativeRuntime
        }

        if (nativeRuntime != null) {
            Log.w(TAG, "Native Node candidate exists but verification failed")
            return null
        }

        Log.w(TAG, "No native Node executable found in nativeLibraryDir")
        return null
    }

    private fun resolveNativeLibraryRuntime(assetAbi: String?): NodeRuntime? {
        val nativeDirPath = applicationInfo?.nativeLibraryDir ?: return null
        val nativeDir = File(nativeDirPath)
        if (!nativeDir.exists()) {
            Log.w(TAG, "nativeLibraryDir does not exist: $nativeDirPath")
            return null
        }

        for (candidate in NATIVE_NODE_CANDIDATES) {
            val nodeCandidate = File(nativeDir, candidate)
            if (!nodeCandidate.exists()) {
                continue
            }

            Log.i(TAG, "Found Node candidate in nativeLibraryDir: ${nodeCandidate.absolutePath}")
            val extractedLibDir = assetAbi?.let { ensureExtractedAssetLibDir(it) }
            val runtimeLibDir = extractedLibDir ?: nativeDir
            val runtimeSource = if (extractedLibDir != null) {
                "nativeLibraryDir+assets/$assetAbi/lib"
            } else {
                "nativeLibraryDir"
            }

            return NodeRuntime(
                nodeBinary = nodeCandidate,
                libDir = runtimeLibDir,
                source = runtimeSource
            )
        }

        val packagedLibs = nativeDir.list()?.sorted()?.joinToString(", ") ?: "<none>"
        Log.w(TAG, "No Node candidate found in nativeLibraryDir. Available files: $packagedLibs")

        return null
    }

    private fun ensureExtractedAssetLibDir(assetAbi: String): File? {
        val abiAssetRoot = "$NODE_ASSET_ROOT/$assetAbi"
        val abiAssets = assets.list(abiAssetRoot) ?: return null

        val assetZipPath = "$abiAssetRoot/node-libs.zip.so"
        val hasZipPayload = abiAssets.contains("node-libs.zip.so")

        val assetLibPath = "$NODE_ASSET_ROOT/$assetAbi/lib"
        val assetLibFiles = assets.list(assetLibPath) ?: emptyArray()

        if (!hasZipPayload && assetLibFiles.isEmpty()) {
            return null
        }

        val outputLibDir = File(filesDir, "node-runtime/$assetAbi/lib")
        if (!preparedAssetLibAbis.contains(assetAbi)) {
            Log.i(TAG, "Refreshing Node dependency libs for ABI $assetAbi")
            outputLibDir.parentFile?.mkdirs()
            if (outputLibDir.exists()) {
                outputLibDir.deleteRecursively()
            }

            if (hasZipPayload) {
                extractAssetZip(assetZipPath, outputLibDir)
            } else {
                copyAssetTree(assetLibPath, outputLibDir)
            }

            ensureUnversionedSoAliases(outputLibDir)

            preparedAssetLibAbis.add(assetAbi)
        }

        return outputLibDir
    }

    private fun extractAssetZip(assetPath: String, outputDir: File) {
        outputDir.mkdirs()

        assets.open(assetPath).use { assetStream ->
            ZipInputStream(assetStream.buffered()).use { zipInputStream ->
                var entry = zipInputStream.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory) {
                        val outputFile = File(outputDir, entry.name)
                        val normalizedOutput = outputFile.canonicalPath
                        val normalizedRoot = outputDir.canonicalPath + File.separator
                        if (!normalizedOutput.startsWith(normalizedRoot)) {
                            throw IllegalStateException("Invalid zip entry path: ${entry.name}")
                        }

                        outputFile.parentFile?.mkdirs()
                        FileOutputStream(outputFile).use { output ->
                            zipInputStream.copyTo(output)
                        }
                    }

                    zipInputStream.closeEntry()
                    entry = zipInputStream.nextEntry
                }
            }
        }
    }

    private fun verifyNodeRuntime(nodeRuntime: NodeRuntime): Boolean {
        if (!nodeRuntime.nodeBinary.exists()) {
            return false
        }

        Log.i(TAG, "Verifying Node runtime source=${nodeRuntime.source} bin=${nodeRuntime.nodeBinary.absolutePath} libDir=${nodeRuntime.libDir.absolutePath}")

        val versionOk = runNodeCheck(nodeRuntime, "--version")
        if (!versionOk) {
            return false
        }

        return runNodeCheck(nodeRuntime, "-e", "process.stdout.write('ok')")
    }

    private fun runNodeCheck(nodeRuntime: NodeRuntime, vararg args: String): Boolean {
        return try {
            val command = mutableListOf(nodeRuntime.nodeBinary.absolutePath)
            command.addAll(args)

            val process = ProcessBuilder(command)
                .directory(nodeRuntime.nodeBinary.parentFile)
                .redirectErrorStream(true)
                .apply {
                    val libSearchPath = linkedSetOf(nodeRuntime.libDir.absolutePath)
                    nodeRuntime.nodeBinary.parentFile?.absolutePath?.let { libSearchPath.add(it) }
                    environment()["LD_LIBRARY_PATH"] = libSearchPath.joinToString(":")
                    environment()["HOME"] = filesDir.absolutePath
                    environment()["TMPDIR"] = cacheDir.absolutePath
                    Log.d(TAG, "Node check LD_LIBRARY_PATH=${environment()["LD_LIBRARY_PATH"]}")
                }
                .start()

            val finished = process.waitFor(5, TimeUnit.SECONDS)
            val output = process.inputStream.bufferedReader().use { it.readText().trim() }

            if (!finished) {
                process.destroyForcibly()
                Log.w(TAG, "Node check timed out for args=${args.joinToString(" ")}")
                return false
            }

            if (process.exitValue() != 0) {
                Log.w(TAG, "Node check failed (${process.exitValue()}): $output")
                return false
            }

            Log.d(TAG, "Node check success for args=${args.joinToString(" ")}: $output")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Node check exception for args=${args.joinToString(" ")}", e)
            false
        }
    }

    private fun resolveAssetAbi(): String? {
        val availableAbis = assets.list(NODE_ASSET_ROOT)?.toSet() ?: emptySet()
        if (availableAbis.isEmpty()) {
            return null
        }

        for (abi in Build.SUPPORTED_ABIS) {
            if (availableAbis.contains(abi)) {
                return abi
            }
        }

        return null
    }

    private fun ensureUnversionedSoAliases(libDir: File) {
        val files = libDir.listFiles() ?: return
        for (file in files) {
            if (!file.isFile) {
                continue
            }

            val name = file.name
            val match = Regex("^(.*\\.so)\\..+$").find(name) ?: continue
            val baseName = match.groupValues[1]
            val baseFile = File(libDir, baseName)
            if (!baseFile.exists()) {
                file.copyTo(baseFile, overwrite = false)
            }
        }
    }

    private fun copyAssetTree(assetPath: String, outputDir: File) {
        val children = assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            copyAssetFile(assetPath, outputDir)
            return
        }

        if (!outputDir.exists()) {
            outputDir.mkdirs()
        }

        for (child in children) {
            val childAssetPath = "$assetPath/$child"
            val childOutput = File(outputDir, child)
            copyAssetTree(childAssetPath, childOutput)
        }
    }

    private fun copyAssetFile(assetPath: String, outputFile: File) {
        outputFile.parentFile?.mkdirs()
        assets.open(assetPath).use { input ->
            outputFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    }
    
    private suspend fun updateYtDlp() = withContext(Dispatchers.IO) {
        YoutubeDL.getInstance().updateYoutubeDL(applicationContext)
    }
}
