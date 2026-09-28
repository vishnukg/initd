-- terraform-ls reads its options ONLY from initializationOptions: it does not
-- implement workspace/didChangeConfiguration (-32601 method not found), so
-- under `settings` every value here was silently dropped.
--
-- indexing.ignoreDirectoryNames is deliberately absent: .terraform and .git
-- are already ignored by default, and naming either one makes initialize fail
-- with `cannot ignore directory ".terraform"` - the server never starts.
return {
	init_options = {
		terraform = {
			timeout = "30s",
		},
		validation = {
			enableEnhancedValidation = true,
		},
		experimentalFeatures = {
			validateOnSave = true,
			prefillRequiredFields = true,
		},
	},
}
