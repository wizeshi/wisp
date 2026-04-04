##  Contribuir

Opá, duvido que realmente queiras contribuir, mas cá vai:

### PRÉ-REQUISITOS
#### MULTI-PLATAFORMA

1. Instala o [Flutter](https://docs.flutter.dev/install) (recomendo pelo VS Code)
2. Instala o [rustup](https://rustup.rs/)

#### LINUX

3. Instala o libmpv:
    - Fedora/RHEL/CentOS: ```sudo dnf install mpv-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install``` 
    - Arch-based: ```sudo pacman -S mpv```

4. Instala o WPEwebkit (e dependências):
    - Fedora/RHEL/CentOS: 
        - Adiciona o repositório COPR: ```dnf copr enable philn/wpewebkit```
        - ```sudo dnf install wpewebkit wpewebkit-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install libwpewebkit libwpewebkit-dev```
    - Arch-based: ```nem ideia```

5. Verifica que não há conflitos de dependências:
    Um dos erros mais comuns é que o WPEwebkit faz upgrade ao libinput, que requer a versão 5.4 do Lua. Esta versão não é compatível com a aplicação, já que usa o mpv (e a malta lá não gosta). Então, vais ter de fazer downgrade ao libinput. No Fedora, é assim: ```sudo dnf downgrade libinput```. A versão que obteres deve ser por volta da 1.29.

6. Ligar renderização por software:
    Uma das dependências da aplicação é o flutter_inappwebview, e a sua implementação para Linux está numa fase muito inicial de desenvolvimento, mas funciona razoávelmente. Mas quando o usas, as áreas de webview ficam com ecrãs pretos. Por isso, por agora, terás sempre de iniciar a aplicação com isto nas tuas variáveis de ambiente (normalmente a anteceder o comando de inicialização):```LIBGL_ALWAYS_SOFTWARE=1```
    Nota: isto é só no Linux. As implementações de todas as outras plataformas são razovelmente maduras e não têm este problema. [Aqui](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2778) está o issue onde este comportamento é documentado e acompanhado.

#### WINDOWS

3. Instala o [NuGet](https://learn.microsoft.com/en-us/nuget/install-nuget-client-tools?tabs=windows#nugetexe-cli) para o FlutterInAppWebview

4. Instala as Visual Studio Build Tools para "Desktop development with C++" (liga o MSVC v142 e o C++ ATL)

5. Instala o Inno Setup 6 (para distribuir) 