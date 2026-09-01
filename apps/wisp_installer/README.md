# wisp_installer

This is a simple installer for [wisp](https://github.com/wizeshi/wisp), the Open, Fast & Unified music player.
It manages all dependencies for the normal functioning of the app, as well as setting up optional components.

To be specific, it installs the core app, as well as the following optional components:
- YouTube Engines
    - [YT-DLP](https://github.com/yt-dlp/yt-dlp) & [Node.JS](https://nodejs.org/en/)
    - [NewPipeStreamExtractor](https://github.com/wizeshi/NewPipeStreamExtractor) & [JDK 21](https://www.oracle.com/java/technologies/javase/jdk21-archive-downloads.html)

## Compiling
### macOS
Compiling for macOS is simple. Just run ```flutter build macos``` and the resulting .app file is ready to execute.

### Windows
To compile for Windows, you need to have Enigma VirtualBox installed, as well as the Windows SDK. You can then run ```flutter build windows``` to generate the .dlls and .exe file. 

After this, you'll need to install Enigma Virtual Box. Open it, and select the wisp .exe as the input file. Then, add the .dlls and the "data" folder as additional files. If you want, change the location of the output. Finally, click "Process" and wait until it's done.