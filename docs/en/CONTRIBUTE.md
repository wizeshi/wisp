##  Contribute

Well, I doubt you really want to contribute, but here it goes:

### REQUIREMENTS
#### MULTI-PLATFORM

1. Install [Flutter](https://docs.flutter.dev/install) (I recommend using VS Code)
2. Install [rustup](https://rustup.rs/)

#### LINUX

3. Install libmpv:
    - Fedora/RHEL/CentOS: ```sudo dnf install mpv-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install libmpv-dev``` 
    - Arch-based: ```sudo pacman -S mpv```

4. Install WPEwebkit (and deps):
    - Fedora/RHEL/CentOS: 
        - Add the COPR repo: ```dnf copr enable philn/wpewebkit```
        - ```sudo dnf install wpewebkit wpewebkit-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install libwpewebkit libwpewebkit-dev```
    - Arch-based: ```no clue```

5. Ensure no dependencies clash:
    One of the most common errors is WPEwebkit upgrading libinput, which requires Lua 5.4. Lua 5.4 is not compatible with the app, since it uses mpv (and the guys there hate it). Therefore, you'll have to downgrade libinput. On Fedora, it is done like so: ```sudo dnf downgrade libinput```. The version you get should be around 1.29 or so.

6. Enabling software rendering:
    One of the dependencies of the app is flutter_inappwebview, and their Linux implementation is in a very early stage of development, but it works okay. But when using it, any webview areas are black screens. So for now, you'll always have to start the app with this in your environment variables (usually prepend it to the launch command): ```LIBGL_ALWAYS_SOFTWARE=1```
    Note: this is only on Linux. All other platforms' implementations are decently mature and don't have this problem. [Here](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2778) is the issue where this behaviour is documented and tracked. 

#### WINDOWS

3. Install [NuGet](https://learn.microsoft.com/en-us/nuget/install-nuget-client-tools?tabs=windows#nugetexe-cli) for FlutterInAppWebview

4. Install Visual Studio Build Tools for "Desktop development with C++" (turn on MSVC v142 and C++ ATL)

5. Install Inno Setup 6 (if you wanna distribute) 


### Do's and Don'ts

This project has a little list of rules you should follow, starting with some more abstract ones:
1. You are allowed and encouraged to use AI (moreso what they call Agentic Engineering nowadays), though all PRs or commits should be reviewed by a human, because since a machine cannot be held accountable, the human must take responsibility.
2. Don't make unnecessary changes. Any change you make should not base itself on politics, or any form of discrimination. This also applies to interacting with users about the project. 

Now let's get to the more technical ones: 
3. Try to add logging, but also not too much. You don't need to log every single thing happening in the app, but you also wanna be able to see what's bugged without too much change in the logs. 
4. On the same train, prefer properly labeling the logs you add. E.g., a file called example.dart, in the providers/metadata folder, should log like "[Metadata/Example]" or "[Providers/Metadata/Example]". Try to keep it two layers (so the former), unless there is already a decently unrelated log on another file. For reference, try searching the codebase for "[Metadata/", since it should show you some examples.
5. Try to reuse code, but not too much. For example, if you're implementing a screen that uses song rows, prefer using existing song row widgets instead of remaking your own. But if you're implementing a screen that uses a very specific layout of song rows, and there is no existing widget that has that layout, then it's better to make a new one instead of trying to reuse an existing one and shoehorning it into the new layout.

That's all for now!