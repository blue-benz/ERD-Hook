.PHONY: bootstrap build test coverage lint demo-local demo-testnet demo-streaming demo-epoch demo-all verify-commits

bootstrap:
	./scripts/bootstrap.sh

build:
	forge build

test:
	forge test

coverage:
	forge coverage --report lcov

lint:
	forge fmt --check

verify-commits:
	./scripts/verify_commits.sh 54

demo-streaming:
	./scripts/demo-streaming.sh

demo-epoch:
	./scripts/demo-epoch.sh

demo-local:
	./scripts/demo-local.sh

demo-testnet:
	./scripts/demo-testnet.sh

demo-all: demo-streaming demo-epoch
