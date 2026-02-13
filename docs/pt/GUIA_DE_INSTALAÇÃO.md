## Instalação

Bem, parece que alguem quer instalar o wisp.  
Vamos começar.

Arranja o [programa já compilado](https://github.com/wizeshi/wisp/releases) ou [compila-o tu próprio](https://github.com/wizeshi/wisp/blob/master/docs/BUILDING.md).
Depois roda-o e, voilà, instalou.  

Nah, mas eu sei que não tás aqui por causa disto.
Ainda falta um bocado.

### LINUX

Malta de Linux, esperem: empacotar um programa é uma miséria. Ainda por cima em Flutter, cuja única ferramenta de empacotamento nem sequer é oficial. Lógicamente, optei pela mais fácil: AppImages. Leve problema: por enquanto não estou a conseguir empacotar a aplicação com todas as dependências nela. Portanto, se a aplicação não abrir, terás de ter o seguinte:
    - glibc 2.17+
    - libmpv (mpv-devel em Fedora, libmpv-dev em Debian, mpv em Arch)

Ah, um aviso também: já que estamos a usar AppImages, a aplicação não estará tão integrada ao SO. Caso queiras ter melhor integração, recomendo usares o AppImageLauncher para o fazer (é o que uso, então será sempre suportado).

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

### Multi-plataforma (opcional)

A aplicação consegue usar diversos provedores de metadados, audio e letras de músicas. A maioria deles vêm pre-configurados, mas existe outro (sem ser os metadados do spotify acima) que precisa de outra coisa para funcionar: as letras do Spotify.

O Spotify não fornece uma API (ponto de acesso) de letras para o público desenvolvedor. Por isso, é preciso fazer alguma engenharia reversa para o colocar a funcionar (tal como funciona na própria aplicação deles). Para isto, precisarás de fornecer tu próprio o cookie "sp_dc". Aqui vão os passos para o fazer:

1. Abre o teu navegador de preferência
2. Vai ao [Spotify](https://open.spotify.com)
3. Abre a área de desenvolvedor (DevTools, CTRL+SHIFT+I ou F12)
4. Vai lá acima onde diz "Application" (pode ser preciso clicar na setinha)
5. Expande a área, na esquerda, onde diz "Cookies" (usando a setinha à esquerda do texto)
6. Clica no URL que diz "https://open.spotify.com"
7. Clica no que diz "sp_dc"
8. Vai lá abaixo e copia
9. Vai ao wisp
10. Vai às definições da apliccação, aperta no lápis ao lado do Spotify, e coloca onde diz "sp_dc"  

E estás pronto!