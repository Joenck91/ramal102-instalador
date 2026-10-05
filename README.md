# Ramal 102

Todos os seus WhatsApps numa caixa só, rodando no seu computador.

## Instalar

1. Instale o **Docker Desktop** e abra ele uma vez. Ele precisa estar
   rodando — o ícone da baleia fica perto do relógio.
2. Baixe esta pasta: botão verde **Code** → **Download ZIP**.
3. **Antes de extrair**, clique com o botão direito no arquivo `.zip` →
   **Propriedades** → marque **Desbloquear**, embaixo à direita → **OK**.

   Esse passo parece bobo e é o que evita a dor de cabeça do próximo
   tópico. O Windows carimba tudo que vem da internet, e o carimbo passa
   do `.zip` para cada arquivo de dentro na hora de extrair. Tirando
   antes, os arquivos nascem limpos.
4. Extraia numa pasta sua, como `C:\Ramal102`.

   **Escolha a pasta com calma e não mexa nela depois.** Mover ou
   renomear funciona, mas é trabalho: o Docker usa o caminho para achar
   onde as suas conversas estão guardadas. Se precisar mudar de lugar
   um dia, peça ajuda antes.

   Evite deixar dentro do OneDrive ou do Google Drive. O arquivo de
   senhas iria junto para a nuvem, e a sincronização briga com arquivo
   que está em uso.
5. Dois cliques em **instalar.bat**.
6. Responda nome, e-mail e empresa. **Anote a senha que aparecer no
   final** — é com ela que você entra.

Leva menos de um minuto. No fim o navegador abre sozinho em
http://localhost:3000.

## Se o Windows bloquear

Pode aparecer **"O Controle de Aplicativo Inteligente bloqueou um
arquivo que pode não ser seguro"**, sem nenhuma opção de continuar.

Não é vírus. É o Windows 11 recusando qualquer programa que não tenha
sido assinado por uma empresa que ele já conhece — e o Ramal 102 ainda
não tem essa assinatura.

**O caminho mais simples, sem desligar proteção nenhuma:** em vez de
dois cliques, abra a pasta, segure **Shift**, clique com o botão
direito num lugar vazio e escolha **Abrir a janela do PowerShell
aqui**. Cole a linha abaixo e tecle Enter:

```powershell
Get-ChildItem -Recurse | Unblock-File
powershell -NoProfile -ExecutionPolicy Bypass -File .\instalar.ps1
```

São duas linhas, e cada uma resolve uma trava diferente:

- `Unblock-File` tira o carimbo de "veio da internet" dos arquivos. É
  o mesmo efeito do passo 3 acima, feito depois em vez de antes.
- `-ExecutionPolicy Bypass` destrava a execução **só desta vez**, nesta
  janela. O Windows vem de fábrica recusando qualquer script, mesmo um
  que você acabou de desbloquear, e sem isso aparece *"a execução de
  scripts foi desabilitada neste sistema"*. Não mexe na configuração da
  máquina: feche a janela e tudo volta como estava.

Funciona porque quem está sendo executado é o PowerShell, que faz parte
do Windows — e não um arquivo que veio da internet.

> Existe também a opção de desligar o Controle de Aplicativo
> Inteligente nas configurações de segurança do Windows. **Não
> recomendamos**: uma vez desligado, ele só pode ser religado
> reinstalando o Windows. O caminho acima resolve sem isso.

## Atualizar depois

Dois cliques em **atualizar.bat** e arraste para a janela a pasta com a
versão nova.

As suas conversas, os números já conectados e a mídia baixada **não
ficam nesta pasta** — moram em áreas do Docker, fora dela. Atualizar
não encosta em nada disso, e não pede para ler QR Code de novo.

## O que fica guardado onde

| | Onde mora |
|---|---|
| Conversas, etiquetas, notas, retornos | Banco de dados local |
| Números conectados (o pareamento) | Volume do Docker |
| Áudios, imagens e documentos | Volume do Docker |
| As suas senhas e chaves | O arquivo `.env`, nesta pasta |
| Cópias de segurança | A pasta `backups`, aqui |

Tudo no seu computador. Nada em nuvem nenhuma.

## Se algo der errado

Ver o que o Ramal está dizendo:

```
docker compose logs ramal
```

Conferir se ele está de pé, e qual versão:

```
http://localhost:3000/health
```

---

Esta pasta é gerada automaticamente a partir do repositório do Ramal
102. Não edite nada aqui: a próxima geração sobrescreve.

