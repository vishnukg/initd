#!/usr/bin/env bash
# Cache hook data against its owning Claude process, with unique atomic writes.
exec node "$(dirname "$0")/agent-status.cjs" hook
