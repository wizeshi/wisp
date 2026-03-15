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