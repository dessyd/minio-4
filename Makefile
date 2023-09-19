# .SILENT:
SHELL = bash
C_DIR := $(lastword $(subst /, ,$(CURDIR)))

.PHONY: env up down clean

.env:
	echo "Create $@ from template"
	C_DIR=$(C_DIR) R_P=`openssl rand -hex 8` envsubst < tpl.env | op inject -f > $@ && chmod 600 $@

env: .env

up: env
	echo "Powering up"
	docker-compose up -d

down:
	echo "Powering down"
	docker-compose down

clean:
	echo "Powering down and removing volumes"
	docker-compose down -v
	rm -rf .env
