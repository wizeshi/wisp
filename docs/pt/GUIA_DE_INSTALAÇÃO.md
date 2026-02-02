## Instalação

Bem, parece que alguem quer instalar o wisp.  
Vamos começar.

Arranja o [programa já compilado](https://github.com/wizeshi/wisp/releases) ou [compila-o tu próprio](https://github.com/wizeshi/wisp/blob/master/docs/BUILDING.md).
Depois, corre o setup (ou instala o .rpm, .deb, .apk) e voilà, instalou.  

Nah, mas eu sei que não tás aqui por causa disto.
Ainda falta um bocado.

### Setup para PC
Se estás no PC, quando primeiro abrires a aplicação, tudo deve funcionar. A aplicação vai instalar todas as dependencias necessárias (ou pelo menos aquelas que não tens)

Se, por algum motivo, a aplicação não o fizer (se não detetou as dependencias, ou não conseguiu instalar, whatever), vais precisar de ter estas coisas instaladas (algumas no PATH, pesquisa, não sou o Google):
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- glibc 2.17+ (Linux)
- libmpv (Linux, mpv-devel no Fedora, libmpv-dev no Debian)
- ~~[ffmpeg](https://www.ffmpeg.org/download.html)~~ (não é preciso por enquanto)

Depois de instalar isto, podes seguir para a instalação abaixo.

### Multi-plataforma
De qualquer forma, vais ainda precisas de uma outra coisa para usar a aplicação. É a API do Spotify e aqui vai explicado como a usas:

- Vai para o [Painel de Desenvolvedores do Spotify](https://developer.spotify.com/dashboard) 
- Entra na tua conta do Spotify
- Clica "Criar Aplicação"/"Create App"
- Coloca um nome e descrição quaisquer
- Insere estes URI de reencaminhamento (redirect URIs): ```wisp-login://auth``` & ```http://127.0.0.1:43823```
- Marca a caixa com "Web API" e aceita os Termos de Uso do Spotify
- Copia o Client ID e Client Secret
- Daí vais às definições da aplicação (canto superior direito no telemóvel, barra de título no PC), clica no icone de lápis à direita da fila da conta do Spotify, e insere as credenciais aí.
- Por fim, entra na tua conta do Spotify depois de clicar no botão da porta (vai abrir no navegador padrão).

E estás pronto!