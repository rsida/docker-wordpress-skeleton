.DEFAULT_GOAL := help
SHELL         := /bin/bash

# Charger .env si present
-include .env
export

SITE_DOMAIN      ?= wordpress.local
PROJECT_NAME     ?= wordpress
TRAEFIK_NETWORK  ?= traefik-net

.PHONY: help start stop restart logs ps hosts wp-cli wp-shell db-shell

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

## -- Demarrage ------------------------------------------------------------

start: ## Demarre le stack WordPress (docker-base/Traefik doit deja tourner)
	docker compose up -d

stop: ## Arrete tous les conteneurs de ce projet
	docker compose down

restart: stop start ## Redemararre le stack

logs: ## Affiche les logs en temps reel
	docker compose logs -f

## -- WordPress ------------------------------------------------------------

wp-cli: ## Lance une commande WP-CLI (ex: make wp-cli CMD="plugin list")
	docker compose exec wordpress wp $(CMD) --allow-root

wp-shell: ## Ouvre un shell dans le conteneur WordPress
	docker compose exec wordpress bash

db-shell: ## Ouvre un shell MariaDB
	docker compose exec mariadb mariadb -u root -p$(DB_ROOT_PASSWORD)

## -- Utilitaires ----------------------------------------------------------

ps: ## Liste les conteneurs du projet
	docker compose ps

hosts: ## Ajoute les domaines dans /etc/hosts (Linux) et affiche la ligne pour Windows
	@HOSTS_LINE="127.0.0.1 $(SITE_DOMAIN) pma.$(SITE_DOMAIN) mail.$(SITE_DOMAIN)"; \
	if grep -qF "$(SITE_DOMAIN)" /etc/hosts; then \
		echo "/etc/hosts : entree deja presente pour $(SITE_DOMAIN)"; \
	else \
		echo "$$HOSTS_LINE" | sudo tee -a /etc/hosts > /dev/null; \
		echo "/etc/hosts : entree ajoutee ($$HOSTS_LINE)"; \
	fi
	@echo ""
	@echo "Ajouter aussi dans C:\\Windows\\System32\\drivers\\etc\\hosts :"
	@echo ""
	@echo "  127.0.0.1 $(SITE_DOMAIN) pma.$(SITE_DOMAIN) mail.$(SITE_DOMAIN)"
	@echo ""

check-network: ## Verifie que le reseau Traefik partage existe
	@docker network inspect $(TRAEFIK_NETWORK) > /dev/null 2>&1 \
		&& echo "Reseau '$(TRAEFIK_NETWORK)' : OK" \
		|| (echo "ERREUR : le reseau '$(TRAEFIK_NETWORK)' n'existe pas." \
			&& echo "         Lancer docker-base d'abord : cd ~/project/docker-base && make up" \
			&& exit 1)
