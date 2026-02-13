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

### All platformsm (optional)

The app can use a lot of different providers for metadata, audio and song lyrics. Most of them work out of the box, but one of them (in addition to the Spotify one above) that needs further setting up: Spotify lyrics.

Spotify doesn't provider a lyrics API for the average developer. Because of that, we need to do some reverse engineering to make song lyrics work (the same way they work on the official app). To do this, you'll need to provide the "sp_dc" cookie. Here's how to do so:  

1. Open your preferred web browser
2. Go to [Spotify](https://open.spotify.com)
3. Open the DevTools (CTRL+SHIFT+I ou F12)
4. Go on the top where it says "Application" (you may need to click on the expand arrow)
5. Expand the area on the left that says "Cookies" (using the arrow located to the left of the text)
6. Click on the URL "https://open.spotify.com"
7. Click where it says "sp_dc"
8. Go down and copy it (it's usually a big random string of text)
9. Go to wisp
10. Go to the app settings, click on the pencil next to Spotify, and input where it says "sp_dc"

And you're set!