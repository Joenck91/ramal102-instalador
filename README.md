# Ramal 102

Todos os seus WhatsApps numa caixa so, rodando no seu computador.

## Instalar

1. Instale o **Docker Desktop** e abra ele uma vez (ele precisa estar
   rodando — o icone da baleia fica perto do relogio).
2. Baixe esta pasta: botao verde **Code** > **Download ZIP**.
3. Extraia em algum lugar seu, como `C:\Ramal102`.
4. De dois cliques em **instalar.bat**.
5. Responda nome, e-mail e empresa. **Anote a senha que aparecer no
   final** — e com ela que voce entra.

Leva menos de um minuto. No fim o navegador abre sozinho em
http://localhost:3000.

## Atualizar depois

De dois cliques em **atualizar.bat** e arraste para a janela a pasta
com a versao nova.

As suas conversas, os numeros ja conectados e a mídia baixada **nao
ficam nesta pasta** — moram em areas do Docker, fora dela. Atualizar
nao encosta em nada disso, e nao pede para ler QR Code de novo.

## O que fica guardado onde

| | Onde mora |
|---|---|
| Conversas, etiquetas, notas, retornos | Banco de dados local |
| Numeros conectados (o pareamento) | Volume do Docker |
| Audios, imagens e documentos | Volume do Docker |
| As suas senhas e chaves | O arquivo `.env`, nesta pasta |
| Copias de seguranca | A pasta `backups`, aqui |

Tudo no seu computador. Nada em nuvem nenhuma.

## Se algo der errado

Ver o que o Ramal esta dizendo:

    docker compose logs ramal

Conferir se ele esta de pe, e qual versao:

    http://localhost:3000/health

---

Esta pasta e gerada automaticamente a partir do repositorio do Ramal
102. Nao edite nada aqui: a proxima geracao sobrescreve.
