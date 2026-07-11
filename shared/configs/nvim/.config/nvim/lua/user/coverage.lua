-- Test coverage overlay (gcv = load & show, then <leader>cvs for summary)
-- Workflow: run tests with neotest → gcv to overlay coverage gutters
require("coverage").setup({
	commands = true,
	auto_reload = true,
	highlights = {
		covered   = { bg = "#004400" },
		uncovered = { bg = "#440000" },
	},
	signs = {
		covered   = { hl = "CoverageCovered",   text = "▎" },
		uncovered = { hl = "CoverageUncovered", text = "▎" },
	},
	lang = {
		-- go test -coverprofile=coverage.out ./...
		go         = { coverage_file = "coverage.out" },
		-- npm run test:coverage (vitest/jest with lcov reporter)
		typescript = { coverage_file = "coverage/lcov.info" },
		javascript = { coverage_file = "coverage/lcov.info" },
		-- coverage run -m pytest && coverage json
		python     = { coverage_file = ".coverage" },
		-- dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=lcov
		cs         = { coverage_file = "TestResults/lcov.info" },
	},
})
