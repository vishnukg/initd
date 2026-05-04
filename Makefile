# Keep Go migration tasks easy to discover and run.
#
# Existing Bash setup remains the stable bootstrap path. These targets only
# build and test the new Go CLI while the migration is in progress.

GO ?= go
BINARY := bin/initd
CMD := ./cmd/initd

.PHONY: help build test clean

help:
	@echo "initd development targets"
	@echo
	@echo "  make build   Build the Go CLI into $(BINARY)"
	@echo "  make test    Run all Go tests"
	@echo "  make clean   Remove built Go artifacts"

build:
	@echo "Building Go CLI: $(BINARY)"
	@mkdir -p bin
	$(GO) build -o $(BINARY) $(CMD)

test:
	@echo "Running Go tests"
	$(GO) test ./...

clean:
	@echo "Removing built Go artifacts"
	@rm -f $(BINARY)
