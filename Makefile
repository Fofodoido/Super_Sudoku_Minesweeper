SWIPL ?= swipl
NPM   ?= npm
UV    ?= uv
PORT  ?= 8080

FRONTEND := frontend
ELM_BIN  := $(FRONTEND)/node_modules/.bin

ELM      ?= $(if $(wildcard $(ELM_BIN)/elm),$(abspath $(ELM_BIN)/elm),elm)
ELM_TEST ?= $(if $(wildcard $(ELM_BIN)/elm-test),$(abspath $(ELM_BIN)/elm-test),elm-test)
ELM_FMT  ?= $(if $(wildcard $(ELM_BIN)/elm-format),$(abspath $(ELM_BIN)/elm-format),elm-format)

ELM_SRC    := $(wildcard $(FRONTEND)/src/*.elm)
ELM_TESTS  := $(shell find $(FRONTEND)/tests -name '*.elm' 2>/dev/null)
PL_TESTS   := $(sort $(wildcard backend/tests/test_*.pl))
BUNDLE     := $(FRONTEND)/public/elm.js

.PHONY: help deps build run test test-prolog test-minesweeper test-acceptance \
        test-elm format check-format check-bundle ci validar clean

help:
	@echo "make deps              instala elm, elm-test e elm-format fixados (npm ci em frontend/)"
	@echo "make build             compila $(BUNDLE) a partir dos fontes Elm"
	@echo "make run [PORT=8080]   compila $(BUNDLE) e inicia o servidor Prolog"
	@echo "make test              testes Prolog e Elm"
	@echo "make test-prolog       todas as suítes backend/tests/test_*.pl"
	@echo "make test-minesweeper  o mesmo que test-prolog (mantido por compatibilidade)"
	@echo "make test-acceptance   fluxos integrados via HTTP"
	@echo "make test-elm          elm-test em frontend/tests"
	@echo "make format            aplica elm-format em frontend/src e frontend/tests"
	@echo "make check-format      valida se elm-format está aplicado"
	@echo "make ci                test + build + check-format (o mesmo que o GitHub Actions)"
	@echo "make validar           valida a entrega (scripts/validar_entrega.py, via uv)"

deps:
	cd $(FRONTEND) && $(NPM) ci

build: $(BUNDLE)

$(BUNDLE): $(ELM_SRC) $(FRONTEND)/elm.json
	cd $(FRONTEND) && $(ELM) make src/Main.elm --optimize --output=public/elm.js

run: build
	$(SWIPL) backend/server.pl $(PORT)

test: test-prolog test-elm

test-prolog:
	@set -e; for t in $(PL_TESTS); do \
	  echo "== $$t"; $(SWIPL) -g run_tests -t halt $$t; \
	done

test-minesweeper: test-prolog

test-acceptance:
	$(SWIPL) -g run_tests -t halt backend/tests/test_minesweeper_acceptance.pl

test-elm:
ifeq ($(strip $(ELM_TESTS)),)
	@echo "== elm-test: nenhum teste em $(FRONTEND)/tests; nada a executar"
else
	cd $(FRONTEND) && $(ELM_TEST) --compiler $(ELM)
endif

format:
	cd $(FRONTEND) && $(ELM_FMT) src/ tests/ --yes

check-format:
	cd $(FRONTEND) && $(ELM_FMT) src/ tests/ --validate

check-bundle: build

ci: test build check-format

validar:
	$(UV) run scripts/validar_entrega.py

clean:
	rm -rf $(BUNDLE) $(FRONTEND)/elm-stuff
