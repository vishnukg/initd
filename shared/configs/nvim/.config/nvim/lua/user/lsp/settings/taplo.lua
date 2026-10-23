-- No remote schemas: taplo 0.10.0 (still the latest release) verifies TLS
-- against a webpki-roots bundle compiled into the binary, and that bundle
-- still trusts the compromised eMudhra intermediates
-- (https://emudhra.we-have-a-problem.com/) - so any fetched schema could be
-- MITM'd. Formatting and syntax diagnostics need no schema. Re-enable once a
-- taplo release ships webpki-roots >= 1.0.10.
return {
	settings = {
		evenBetterToml = {
			schema = { enabled = false },
		},
	},
}
