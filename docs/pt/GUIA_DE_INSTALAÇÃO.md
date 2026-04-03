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
Antes tinhas de passar por um monte de problemas para configurar o SDK do Spotify, sacar os cookies para letras, mas não mais! 
Agora é só fazeres login dentro da App (é a página de login do Spotify) e pronto!