package config

import (
	"path/filepath"
	"reflect"
	"testing"
)

func TestGivenHomeAndRootInputs_WhenNewEnvIsCalled_ThenRequiredPathsAreValidated(t *testing.T) {
	// Arrange
	tests := []struct {
		name    string
		home    string
		root    string
		wantErr bool
	}{
		{name: "valid", home: "/home/user", root: "/repo/initd"},
		{name: "missing home", root: "/repo/initd", wantErr: true},
		{name: "missing root", home: "/home/user", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Act
			_, err := NewEnv(tt.home, tt.root)

			// Assert
			if tt.wantErr && err == nil {
				t.Fatal("NewEnv returned nil error")
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("NewEnv returned error: %v", err)
			}
		})
	}
}

func TestGivenEnv_WhenHomeAndRootPathsAreExpanded_ThenAbsolutePathsUseTheExpectedRoots(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	link := Link{Target: ".config/nvim", Source: "nvim/.config/nvim"}
	profile := GitProfile{Name: "work", Source: "git/profiles/work.gitconfig"}

	// Act
	gotHomePath := env.HomePath(".config/nvim")
	gotRootPath := env.RootPath("nvim/.config/nvim")
	gotLinkTarget := env.LinkTarget(link)
	gotLinkSource := env.LinkSource(link)
	gotGitProfileSource := env.GitProfileSource(profile)

	// Assert
	if want := filepath.Join(env.HomeDir, ".config/nvim"); gotHomePath != want {
		t.Fatalf("HomePath = %q, want %q", gotHomePath, want)
	}

	if want := filepath.Join(env.RootDir, "nvim/.config/nvim"); gotRootPath != want {
		t.Fatalf("RootPath = %q, want %q", gotRootPath, want)
	}

	if want := filepath.Join(env.HomeDir, ".config/nvim"); gotLinkTarget != want {
		t.Fatalf("LinkTarget = %q, want %q", gotLinkTarget, want)
	}

	if want := filepath.Join(env.RootDir, "nvim/.config/nvim"); gotLinkSource != want {
		t.Fatalf("LinkSource = %q, want %q", gotLinkSource, want)
	}

	if want := filepath.Join(env.RootDir, "git/profiles/work.gitconfig"); gotGitProfileSource != want {
		t.Fatalf("GitProfileSource = %q, want %q", gotGitProfileSource, want)
	}
}

func TestGivenEnv_WhenDirectoryLinksAreRequested_ThenTheyMatchDirectoryPreparationLinks(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	want := [][2]string{
		{".config/kitty", "kitty/.config/kitty"},
		{".config/mise", "mise/.config/mise"},
		{".config/nvim", "nvim/.config/nvim"},
	}

	// Act
	got := linkRelPairs(env.DirectoryLinks())

	// Assert
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("DirectoryLinks = %#v, want %#v", got, want)
	}
}

func TestGivenEnv_WhenManagedLinksAreRequested_ThenTheyMatchCurrentRuntimePaths(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	want := [][2]string{
		{".config/kitty", "kitty/.config/kitty"},
		{".config/mise", "mise/.config/mise"},
		{".config/nvim", "nvim/.config/nvim"},
		{".zshrc", "zsh/.zshrc"},
		{".zprofile", "zsh/.zprofile"},
	}

	// Act
	got := linkRelPairs(env.ManagedLinks())

	// Assert
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ManagedLinks = %#v, want %#v", got, want)
	}
}

func TestGivenEnv_WhenLegacyLinksAreRequested_ThenTheyMatchCleanupScriptLegacyLinks(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	want := [][2]string{
		{".gitconfig", "git/.gitconfig"},
		{".config/git", "git/.config/git"},
		{".config/zsh", "shell/.config/zsh"},
		{".zshrc", "zsh-home/.zshrc"},
		{".config/mise/config.toml", "mise.toml"},
	}

	// Act
	got := linkRelPairs(env.LegacyLinks())

	// Assert
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("LegacyLinks = %#v, want %#v", got, want)
	}
}

func TestGivenEnv_WhenGitProfilesAreRequested_ThenTheyMatchGitProfileScript(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	want := [][2]string{
		{"personal", "git/profiles/personal.gitconfig"},
		{"work", "git/profiles/work.gitconfig"},
	}

	// Act
	gotProfiles := env.GitProfiles()
	got := make([][2]string, 0, len(gotProfiles))
	for _, profile := range gotProfiles {
		got = append(got, [2]string{profile.Name, profile.Source})
	}

	// Assert
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("GitProfiles = %#v, want %#v", got, want)
	}
}

func TestGivenKnownGitProfileName_WhenGitProfileIsRequested_ThenProfileIsReturned(t *testing.T) {
	// Arrange
	env := mustEnv(t)

	// Act
	profile, ok := env.GitProfile("work")

	// Assert
	if !ok {
		t.Fatal("GitProfile(work) returned ok=false")
	}
	if profile.Source != "git/profiles/work.gitconfig" {
		t.Fatalf("work profile source = %q", profile.Source)
	}
}

func TestGivenUnknownGitProfileName_WhenGitProfileIsRequested_ThenProfileIsNotFound(t *testing.T) {
	// Arrange
	env := mustEnv(t)

	// Act
	_, ok := env.GitProfile("unknown")

	// Assert
	if ok {
		t.Fatal("GitProfile(unknown) returned ok=true")
	}
}

func TestGivenEnv_WhenSpecialLegacyPathsAreRequested_ThenTheyMatchCurrentMigrationRules(t *testing.T) {
	// Arrange
	env := mustEnv(t)
	wantZshrc := `[[ -f "${HOME}/.config/zsh/initd.zsh" ]] && source "${HOME}/.config/zsh/initd.zsh"`
	wantZprofile := `[[ -f "${HOME}/.config/zsh/initd.zprofile" ]] && source "${HOME}/.config/zsh/initd.zprofile"`

	// Act
	gotGitConfigPath := env.GitConfigPath()
	gotLegacyGitConfigPath := env.LegacyGitConfigPath()
	gotXDGGitConfigPath := env.XDGGitConfigPath()
	gotLegacyZshrcContent := env.LegacyZshrcContent()
	gotLegacyZprofileContent := env.LegacyZprofileContent()

	// Assert
	if want := filepath.Join(env.HomeDir, ".gitconfig"); gotGitConfigPath != want {
		t.Fatalf("GitConfigPath = %q, want %q", gotGitConfigPath, want)
	}

	if want := filepath.Join(env.RootDir, "git/.gitconfig"); gotLegacyGitConfigPath != want {
		t.Fatalf("LegacyGitConfigPath = %q, want %q", gotLegacyGitConfigPath, want)
	}

	if want := filepath.Join(env.HomeDir, ".config/git/.gitconfig"); gotXDGGitConfigPath != want {
		t.Fatalf("XDGGitConfigPath = %q, want %q", gotXDGGitConfigPath, want)
	}

	if gotLegacyZshrcContent != wantZshrc {
		t.Fatalf("LegacyZshrcContent = %q, want %q", gotLegacyZshrcContent, wantZshrc)
	}

	if gotLegacyZprofileContent != wantZprofile {
		t.Fatalf("LegacyZprofileContent = %q, want %q", gotLegacyZprofileContent, wantZprofile)
	}
}

func linkRelPairs(links []Link) [][2]string {
	pairs := make([][2]string, 0, len(links))
	for _, link := range links {
		pairs = append(pairs, [2]string{link.Target, link.Source})
	}

	return pairs
}

func mustEnv(t *testing.T) Env {
	t.Helper()

	env, err := NewEnv("/tmp/home", "/tmp/repo")
	if err != nil {
		t.Fatalf("NewEnv returned error: %v", err)
	}

	return env
}
