## Installation

Well, looks like someone actually wants to install wisp.  
Great! Let's start.

Grab some [pre-built binaries](https://github.com/wizeshi/wisp/releases) or [build them yourself](https://github.com/wizeshi/wisp/blob/master/docs/BUILDING.md).
Then, run the setup (or install the .rpm, .deb, .apk) and voilà, it's installed.  

No, but I know you aren't here because of that.
There are a couple more steps to go.

### Desktop-only setup
If on desktop, when you first open the app, everything should work. The app will install all related dependencies (at least, those that weren't at install-time)

If, for some reason, the app doesn't (be it that the app didn't detect the deps, or it failed to install them, whatever), you'll need these either installed or in your PATH (search up on how to do that, I'm not Google):
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- glibc 2.17+ (Linux)
- libmpv (Linux, mpv-devel on Fedora, libmpv-dev on Debian)
- ~~[ffmpeg](https://www.ffmpeg.org/download.html)~~ (not needed for now)

After installing these, you can proceed to the "All platforms" installation section below. 

### All platforms
Anyway, you'll still need some other things to proceed. This is the Spotify API, and here's how to set it up:

- Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) 
- Log in to your Spotify account
- Click "Create App"
- Input any app name and description
- Add the following these redirect URIs: ```wisp-login://auth``` & ```http://127.0.0.1:43823```
- Check "Web API" and accept Spotify's Terms of Use
- Copy your Client ID and Client Secret
- Then go to the App's settings (top-right on mobile, titlebar on desktop), select the Pencil Icon to the right of the Spotify Account Row, and input the credentials there.
- Finally, login to your Spotify Account clicking on the door button (this will open in your default browser).

And you're set!