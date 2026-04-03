## Installation

Well, looks like someone actually wants to install wisp.  
Great! Let's start.

Grab some [pre-built binaries](https://github.com/wizeshi/wisp/releases) or [build them yourself](https://github.com/wizeshi/wisp/blob/master/docs/BUILDING.md).
Then, run the setup (or install the AppImage, .apk) and voilà, it's installed.  

No, but I know you aren't here because of that.
There are a couple more steps to go.

### LINUX

Linux people, wait: packaging an app is horrendous. Even more so in Flutter, where the only packaging tool isn't even official. Therefore, I went with the more simple approach: AppImages. Little problem, though, right now I'm unable to embed the proper dependencies with the app binary. So, if the app doesn't open, try to install the following: 
    - glibc 2.17+
    - libmpv (mpv-devel in Fedora, libmpv-dev in Debian, mpv in Arch)

Oh, a warning as well: since we're using AppImages, the app isn't gonna be integrated with the OS. If you want to better integrate it, I recommend AppImageLauncher (it is what I use, so it'll always be supporteed).

### All Platforms
Before you had to go through a bunch of trouble to set up the Spotify SDK and lyrics, but now, just login inside the App (it's just the Spotify login screen, but embedded) and you're set!