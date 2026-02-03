# Keep Apache Commons Compress classes used via reflection
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**

# Keep XZ classes used by commons-compress for .xz archives
-keep class org.tukaani.xz.** { *; }
-dontwarn org.tukaani.xz.**

# Keep YoutubeDL Android classes (loaded/used reflectively)
-keep class com.yausername.youtubedl_android.** { *; }
-dontwarn com.yausername.youtubedl_android.**
