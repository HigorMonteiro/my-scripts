# my-scripts

Scripts utilitarios para setup, monitoramento, backup e produtividade.

## Estrutura

```
my-scripts/
├── setup/              # Scripts de instalacao (Docker, Nginx, Python)
│   └── install_env.sh
├── monitoring/         # Monitoramento de servicos
│   └── check_services.sh
├── database/           # Backup do Postgres/Django
│   └── db_backup.sh
├── aliases/            # Atalhos para o shell
│   └── custom_aliases.sh
├── README.md
└── install.sh          # Script mestre para linkar tudo
```

## Uso rapido

```bash
# Instalar e linkar tudo no sistema
chmod +x install.sh
./install.sh

# Instalar ambiente completo
setup/install_env.sh all

# Instalar apenas Docker
setup/install_env.sh docker

# Verificar servicos
monitoring/check_services.sh

# Backup do banco
DB_NAME=meudb DB_USER=postgres database/db_backup.sh

# Carregar aliases manualmente
source aliases/custom_aliases.sh
```

## Variaveis de ambiente (database)

| Variavel    | Padrao     | Descricao            |
|-------------|------------|----------------------|
| DB_NAME     | mydb       | Nome do banco        |
| DB_USER     | postgres   | Usuario do Postgres  |
| BACKUP_DIR  | ~/backups/db | Diretorio de backup |
