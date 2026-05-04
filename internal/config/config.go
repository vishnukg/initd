// Package config defines the repo-specific paths and settings used by initd.
//
// It is intentionally data-focused: other packages should use these definitions
// instead of duplicating managed paths, legacy paths, or Git profile names. That
// keeps the Go migration aligned with the existing Bash behavior.
package config

import (
	"errors"
	"path/filepath"
)

// Env carries the filesystem roots used by initd.
//
// Passing these paths explicitly keeps internal packages testable and avoids
// reading the real home directory from code that should work with temp dirs.
type Env struct {
	HomeDir string
	RootDir string
}

// NewEnv validates and normalizes the two roots that every initd operation uses.
func NewEnv(homeDir, rootDir string) (Env, error) {
	if homeDir == "" {
		return Env{}, errors.New("home directory is required")
	}
	if rootDir == "" {
		return Env{}, errors.New("repo root directory is required")
	}

	return Env{
		HomeDir: filepath.Clean(homeDir),
		RootDir: filepath.Clean(rootDir),
	}, nil
}

// HomePath converts a path relative to the user's home into an absolute path.
func (e Env) HomePath(path string) string {
	return filepath.Join(e.HomeDir, path)
}

// RootPath converts a path relative to the initd repo into an absolute path.
func (e Env) RootPath(path string) string {
	return filepath.Join(e.RootDir, path)
}

// StowPackages returns the package names used by the existing GNU Stow command.
func (e Env) StowPackages() []string {
	return []string{"kitty", "mise", "nvim", "zsh"}
}

// Link describes one runtime path that should point at this repo.
//
// Target is relative to HomeDir, and Source is relative to RootDir. Keeping the
// data relative makes the mapping easy to read and avoids storing the same path
// twice in different forms.
type Link struct {
	Label  string
	Target string
	Source string
}

// LinkTarget returns the absolute runtime path for a link.
func (e Env) LinkTarget(link Link) string {
	return e.HomePath(link.Target)
}

// LinkSource returns the absolute repo source path for a link.
func (e Env) LinkSource(link Link) string {
	return e.RootPath(link.Source)
}

// DirectoryLinks returns config directories that should become direct symlinks.
//
// scripts/stow.sh has special migration logic for these paths before Stow runs.
func (e Env) DirectoryLinks() []Link {
	return []Link{
		{"kitty config directory", ".config/kitty", "kitty/.config/kitty"},
		{"mise config directory", ".config/mise", "mise/.config/mise"},
		{"nvim config directory", ".config/nvim", "nvim/.config/nvim"},
	}
}

// ManagedLinks returns the current non-Git links owned by initd.
//
// Git is excluded because ~/.gitconfig points at the active profile instead of a
// single fixed source path.
func (e Env) ManagedLinks() []Link {
	return []Link{
		{"kitty config directory", ".config/kitty", "kitty/.config/kitty"},
		{"mise config directory", ".config/mise", "mise/.config/mise"},
		{"nvim config directory", ".config/nvim", "nvim/.config/nvim"},
		{"zshrc", ".zshrc", "zsh/.zshrc"},
		{"zprofile", ".zprofile", "zsh/.zprofile"},
	}
}

// LegacyLinks returns known symlinks from older initd layouts.
//
// Cleanup can remove these safely only when the runtime path resolves to the
// expected legacy source path.
func (e Env) LegacyLinks() []Link {
	return []Link{
		{"legacy gitconfig", ".gitconfig", "git/.gitconfig"},
		{"legacy git config directory", ".config/git", "git/.config/git"},
		{"legacy zsh config directory", ".config/zsh", "shell/.config/zsh"},
		{"legacy zshrc", ".zshrc", "zsh-home/.zshrc"},
		{"legacy mise config", ".config/mise/config.toml", "mise.toml"},
	}
}

const (
	// ProfilePersonal is the default Git profile used by the current bootstrap.
	ProfilePersonal = "personal"
	// ProfileWork is the alternate Git profile supported by scripts/git-profile.sh.
	ProfileWork = "work"
)

// GitProfile describes a complete Git config profile managed by initd.
type GitProfile struct {
	Name   string
	Source string
}

// GitProfileSource returns the absolute repo source path for a Git profile.
func (e Env) GitProfileSource(profile GitProfile) string {
	return e.RootPath(profile.Source)
}

// GitConfigPath returns the runtime Git config path read by Git.
func (e Env) GitConfigPath() string {
	return e.HomePath(".gitconfig")
}

// DefaultGitProfile returns the profile selected by bootstrap on first setup.
func (e Env) DefaultGitProfile() GitProfile {
	return GitProfile{ProfilePersonal, "git/profiles/personal.gitconfig"}
}

// GitProfiles returns the complete Git profiles supported by initd.
func (e Env) GitProfiles() []GitProfile {
	return []GitProfile{
		{ProfilePersonal, "git/profiles/personal.gitconfig"},
		{ProfileWork, "git/profiles/work.gitconfig"},
	}
}

// GitProfile finds a profile by name.
func (e Env) GitProfile(name string) (GitProfile, bool) {
	for _, profile := range e.GitProfiles() {
		if profile.Name == name {
			return profile, true
		}
	}

	return GitProfile{}, false
}

// LegacyGitConfigPath returns the older repo-level Git config source.
func (e Env) LegacyGitConfigPath() string {
	return e.RootPath("git/.gitconfig")
}

// XDGGitConfigPath returns the older XDG Git config runtime path.
func (e Env) XDGGitConfigPath() string {
	return e.HomePath(".config/git/.gitconfig")
}

// LegacyZshrcContent returns the old one-line zshrc shim that initd can replace.
func (e Env) LegacyZshrcContent() string {
	return `[[ -f "${HOME}/.config/zsh/initd.zsh" ]] && source "${HOME}/.config/zsh/initd.zsh"`
}

// LegacyZprofileContent returns the old one-line zprofile shim that initd can replace.
func (e Env) LegacyZprofileContent() string {
	return `[[ -f "${HOME}/.config/zsh/initd.zprofile" ]] && source "${HOME}/.config/zsh/initd.zprofile"`
}
