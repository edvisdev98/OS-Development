# KSDOS SDK System

Este sistema permite configurar automaticamente os SDKs para desenvolvimento de jogos PS1 e DOOM usando as ferramentas locais em `sdk/`.

## Estrutura dos SDKs

```
sdk/
├── psyq/          # PS1 SDK (PSn00bSDK equivalent)
│   ├── include/   # Headers para desenvolvimento PS1
│   └── lib/       # Bibliotecas PS1
├── gold4/         # DOOM SDK (GNU gold + djgpp)
│   ├── include/   # Headers DOOM/VGA
│   └── lib/       # Bibliotecas DOOM
├── sdk-config.bat # Script de configuração Windows
├── sdk-config.sh  # Script de configuração Linux/Mac
└── detect-sdk.mk  # Sistema de detecção automática
```

## Configuração Automática

### Windows
```batch
sdk\sdk-config.bat
```

### Linux/Mac
```bash
sdk/sdk-config.sh
# Para configuração permanente:
sdk/sdk-config.sh --permanent
```

## Variáveis de Ambiente Configuradas

- `PS1_SDK` - Caminho para o SDK PS1
- `DOOM_SDK` - Caminho para o SDK DOOM  
- `PS1_INC` - Diretório de includes PS1
- `DOOM_INC` - Diretório de includes DOOM
- `PS1_LIB` - Diretório de bibliotecas PS1
- `DOOM_LIB` - Diretório de bibliotecas DOOM
- `KSDOS_ROOT` - Diretório raiz do projeto

## Build System

### Makefile Principal
```bash
# Configurar SDKs
make configure-sdk

# Construir bootloader
make build-bootloader

# Construir todos os jogos
make build-games

# Ajuda
make help
```

### Jogos Individuais

#### PS1 Game
```bash
cd games/psx
make psx-game
make info    # Mostrar informações do SDK
```

#### DOOM Game  
```bash
cd games/doom
make doom-game
make info    # Mostrar informações do SDK
```

## Sistema de Detecção Automática

O sistema `detect-sdk.mk` automaticamente:

1. **Detecta SDKs** - Procura em múltiplos locais
2. **Valida estrutura** - Verifica diretórios include/lib
3. **Configura variáveis** - Define paths para sub-makes
4. **Auto-configura** - Executa configuração se necessário

### Exemplo de Detecção
```makefile
# Detecta SDK automaticamente
PS1_SDK := $(call detect_sdk,$(PS1_SDK),$(PS1_SDK_DEFAULT),$(error PS1 SDK not found))
```

## Configuração de Projetos

Para novos projetos, use o sistema comum:

```makefile
# Makefile do seu jogo
PROJECT_NAME = meu-jogo
PLATFORM = PS1  # ou DOOM

include ../common.mk

# Seu código específico aqui...
```

## Troubleshooting

### SDK não encontrado
```bash
# Verifique se os SDKs existem
ls -la sdk/psyq/
ls -la sdk/gold4/

# Reconfigure manualmente
make configure-sdk
```

### Problemas de compilação
```bash
# Verifique configuração do SDK
make info

# Limpe e recompile
make clean
make psx-game  # ou make doom-game
```

### Variáveis de ambiente
```bash
# Verifique variáveis configuradas
echo $PS1_SDK
echo $DOOM_SDK
echo $KSDOS_ROOT
```

## Estrutura de Arquivos Criada

- `sdk/sdk-config.bat` - Configuração Windows
- `sdk/sdk-config.sh` - Configuração Linux/Mac  
- `sdk/detect-sdk.mk` - Sistema de detecção
- `games/common.mk` - Configuração compartilhada
- `games/psx/Makefile` - Build PS1
- `games/doom/Makefile` - Build DOOM
- `Makefile` - Build principal atualizado

## Uso

1. **Configure os SDKs**: `make configure-sdk`
2. **Construa jogos**: `make build-games`
3. **Desenvolva**: Use os templates em `games/`

O sistema agora detecta e usa automaticamente os SDKs locais quando você cria jogos para PS1 ou DOOM!
