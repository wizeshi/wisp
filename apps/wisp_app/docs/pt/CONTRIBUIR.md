##  Contribuir

Opá, duvido que realmente queiras contribuir, mas cá vai:

### PRÉ-REQUISITOS
#### MULTI-PLATAFORMA

1. Instala o [Flutter](https://docs.flutter.dev/install) (recomendo pelo VS Code)

#### LINUX

2. Instala o libmpv:
    - Fedora/RHEL/CentOS: ```sudo dnf install mpv-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install``` 
    - Arch-based: ```sudo pacman -S mpv```

3. Instala o WPEwebkit (e dependências):
    - Fedora/RHEL/CentOS: 
        - Adiciona o repositório COPR: ```dnf copr enable philn/wpewebkit```
        - ```sudo dnf install wpewebkit wpewebkit-devel```
    - Debian/Ubuntu/Mint: ```sudo apt install libwpewebkit libwpewebkit-dev```
    - Arch-based: ```nem ideia```

4. Verifica que não há conflitos de dependências:
    Um dos erros mais comuns é que o WPEwebkit faz upgrade ao libinput, que requer a versão 5.4 do Lua. Esta versão não é compatível com a aplicação, já que usa o mpv (e a malta lá não gosta). Então, vais ter de fazer downgrade ao libinput. No Fedora, é assim: ```sudo dnf downgrade libinput```. A versão que obteres deve ser por volta da 1.29.

5. Ligar renderização por software:
    Uma das dependências da aplicação é o flutter_inappwebview, e a sua implementação para Linux está numa fase muito inicial de desenvolvimento, mas funciona razoávelmente. Mas quando o usas, as áreas de webview ficam com ecrãs pretos. Por isso, por agora, terás sempre de iniciar a aplicação com isto nas tuas variáveis de ambiente (normalmente a anteceder o comando de inicialização):```LIBGL_ALWAYS_SOFTWARE=1```
    Nota: isto é só no Linux. As implementações de todas as outras plataformas são razovelmente maduras e não têm este problema. [Aqui](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2778) está o issue onde este comportamento é documentado e acompanhado.

#### WINDOWS

2. Instala o [NuGet](https://learn.microsoft.com/en-us/nuget/install-nuget-client-tools?tabs=windows#nugetexe-cli) para o FlutterInAppWebview

3. Instala as Visual Studio Build Tools para "Desktop development with C++" (liga o MSVC v142 e o C++ ATL)

### O que fazer e não fazer

O projeto tem uma pequena lista de regras que deves seguir, começando por umas mais abstratas:
1. Podes e deves usar IA (até mais o que chamam Engenharia com Agentes), mas todas as PRs e commits devem ser revistas por um humano, porque como uma máquina não pode ser responsabilizada, tem de haver um humano para levar com as culpas.
2. Não faças mudanças desnecessárias. Todas as mudanças que fizeres devem basear-se em gosto ou necessidade, e não política, discriminação, religião, etc. Isto também aplica-se quando interages com outras pessoas sobre o projeto.

Vamos entrar nas mais técnicas:
3. Tenta adicionar logs, mas não demasiadas. Não precisas de fazer log em tudo a acontecer na app, mas também deves conseguir ver o que está mal sem mudar muita coisa. No caso de fazeres um sistema demasiado complicado, no qual logs não são o suficiente, podes sempre criar uma nova aba na página de depuração.
4. Continuando, deves preferir logs com indicações claras. Por exemplo, num ficheiro chamado exemplo.dart, na pasta providers/metadata, as logs devem ser "[Metadata/Exemplo]" ou "[Providers/Metadata/Exemplo]". Tenta sempre fazer duas camadas (ou seja, o primeiro exemplo), a não ser que já exista uma log parecida e não relacionada noutro ficheiro. Por exemplo, pesquisa no código por "[Metadata/" para veres exemplos.
5. Tenta reutilizar código, mas sem exageros. Por exemplo, se estiveres a implementar uma tela que usa uma linhas de música, tenta usar widgets que já o representem em vez de refazer. Mas, se precisares de um layout muito específico, e não existe nenhum widget com ele, é melhor fazeres um novo em vez de tentares mudar tudo do zero e enfiar nos layouts existentes. 

É tudo por agora!