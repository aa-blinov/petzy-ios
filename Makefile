# Локальный стек нативной разработки Petzy под iOS.
#
# Petzy.xcodeproj не хранится в git: он генерируется из project.yml командой
# `make generate`. Правьте project.yml, а не .pbxproj.
#
# Первым делом после клона: make setup

SIM        ?= iPhone 18 Pro
BUNDLE_ID  ?= ru.petzy.app
PETZY_DIR  ?= $(HOME)/Documents/petzy
DERIVED    ?= .build
COMPOSE    := docker compose -p petzy-local -f docker-compose.yml -f docker-compose.local.yml

DEVICE_HUB = $(shell xcode-select -p)/../Applications/DeviceHub.app

# macOS make 3.81 не знает .SHELLFLAGS, а пайп до tail съедает код возврата
# xcodebuild: без pipefail провалившиеся тесты выглядят как зелёный make ci.
# -o pipefail понимает и /bin/sh macOS, поэтому он пишется прямо в рецептах.

UDID = $(shell xcrun simctl list devices available | grep -m1 "$(SIM)" | sed -E 's/.*\(([-0-9A-F]+)\).*/\1/')
APP  = $(DERIVED)/Build/Products/Debug-iphonesimulator/Petzy.app
DEST = platform=iOS Simulator,name=$(SIM)

.DEFAULT_GOAL := help

.PHONY: help setup generate open build test test-ui run shot lint lint-strict format format-check ci hooks backend backend-stop logs clean

help: ## Показать все команды
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-13s\033[0m %s\n",$$1,$$2}'

setup: ## Поставить xcodegen и swiftlint, сгенерировать проект
	@command -v xcodegen   >/dev/null || brew install xcodegen
	@command -v swiftlint >/dev/null || brew install swiftlint
	@$(MAKE) --no-print-directory generate

generate: ## Собрать Petzy.xcodeproj из project.yml
	@xcodegen generate

hooks: ## Включить гит-хуки этого репозитория (один раз на клон)
	@git config core.hooksPath .githooks
	@echo "хуки включены: core.hooksPath = .githooks"

open: generate ## Открыть проект в Xcode
	@open Petzy.xcodeproj

build: generate ## Собрать приложение под симулятор
	@set -o pipefail; xcodebuild -project Petzy.xcodeproj -scheme Petzy -destination '$(DEST)' \
		-derivedDataPath $(DERIVED) build | tail -20

test: generate ## Прогнать юнит-тесты (быстро, без сети)
	@set -o pipefail; xcodebuild -project Petzy.xcodeproj -scheme Petzy -destination '$(DEST)' \
		-derivedDataPath $(DERIVED) test -only-testing:PetzyTests | tail -30

test-ui: generate ## Прогнать UI-тесты против локального стека (нужен make backend)
	@set -o pipefail; xcodebuild -project Petzy.xcodeproj -scheme Petzy -destination '$(DEST)' \
		-derivedDataPath $(DERIVED) test -only-testing:PetzyUITests | tail -40

run: build ## Собрать, поставить и запустить на симуляторе
	@xcrun simctl boot $(UDID) 2>/dev/null || true
	@# В Xcode 27 окно симулятора это DeviceHub.app, а не Simulator.app. Без UDID
	@# в аргументах дисплей не подключается и снимки экрана выходят чёрными.
	@open -a "$(DEVICE_HUB)" --args -CurrentDeviceUDID $(UDID) 2>/dev/null \
		|| echo "DeviceHub не найден: $(DEVICE_HUB), приложение всё равно запущено"
	@xcrun simctl install $(UDID) $(APP)
	@xcrun simctl launch $(UDID) $(BUNDLE_ID)

shot: ## Скриншот текущего экрана симулятора
	@mkdir -p screenshots
	@# Дисплей указываем явно: LCD-1 остаётся чёрным, снимок без --display
	@# выходит пустым и говорит о приложении ровно ничего.
	@out="screenshots/$$(date +%Y%m%d-%H%M%S).png"
	@xcrun simctl io $(UDID) screenshot --display=1 "$$out"
	@echo "$$out"

lint: ## Проверить стиль
	@swiftlint lint

lint-strict: ## Проверить стиль, предупреждения считаем ошибками (для CI)
	@swiftlint lint --strict

format: ## Привести код к виду по .swiftformat
	@swiftformat Petzy PetzyTests PetzyUITests

format-check: ## Проверить вид, ничего не меняя
	@swiftformat Petzy PetzyTests PetzyUITests --lint

ci: lint-strict format-check build test ## Всё, что делает CI, локально одной командой

backend: ## Поднять локальный стек petzy (нужен API на :5002)
	@cd $(PETZY_DIR) && $(COMPOSE) up -d --build

backend-stop: ## Остановить локальный стек petzy
	@cd $(PETZY_DIR) && $(COMPOSE) down

logs: ## Логи локального стека petzy
	@cd $(PETZY_DIR) && $(COMPOSE) logs -f --tail=100

clean: ## Убрать сборку и сгенерированный проект
	@rm -rf $(DERIVED) Petzy.xcodeproj Petzy/Resources/Info.plist
	@echo "убрано: сборка и Petzy.xcodeproj, он соберётся заново через make generate"