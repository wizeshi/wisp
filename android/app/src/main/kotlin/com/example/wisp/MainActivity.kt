package com.wizeshi.wisp

import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AudioServiceActivity() {


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
    }

    private suspend fun getStreamUrl(videoId: String): String = withContext(Dispatchers.IO) {
        val request = YoutubeDLRequest("https://www.youtube.com/watch?v=$videoId")
        // Request m4a/AAC format which has better Android compatibility than webm/opus
        request.addOption("-f", "140/bestaudio[ext=m4a]/bestaudio")
        request.addOption("--js-runtimes", "quickjs")
        request.addOption("--print", "%(url)s")
        request.addOption("--no-playlist")
        request.addOption("--skip-download")
        
        val response = YoutubeDL.getInstance().execute(request)
        val url = response.out.trim()
        
        android.util.Log.d("YtDlp", "Raw output length: ${response.out.length}")
        android.util.Log.d("YtDlp", "URL length: ${url.length}")
        android.util.Log.d("YtDlp", "URL ends with: ${url.takeLast(20)}")
        
        if (url.isEmpty()) {
            throw Exception("No stream URL returned")
        }
        
        url
    }
    
    private suspend fun updateYtDlp() = withContext(Dispatchers.IO) {
        YoutubeDL.getInstance().updateYoutubeDL(applicationContext)
    }
}
