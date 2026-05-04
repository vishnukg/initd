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

const (
	// ProfilePersonal is the default Git profile used by the current bootstrap.
	ProfilePersonal = "personal"
	// ProfileWork is the alternate Git profile supported by scripts/git-profile.sh.
	ProfileWork = "work"
)

// Env carries the filesystem roots used by initd.
//
// Passing these paths explicitly keeps internal packages testable and avoids
// reading the real home directory from code that should work with temp dirs.
type Env struct {
	HomeDir string
	RootDir string
}

// ManagedLink describes one runtime path that should point at this repo.
//
// The absolute paths are what filesystem code should use. The relative paths are
// kept for clear tests and for messages that explain the repo mapping.
type ManagedLink struct {
	Label          string
	RuntimePath    string
	SourcePath     string
	RuntimeRelPath string
	SourceRelPath  string
}

// GitProfile describes a complete Git config profile managed by initd.
type GitProfile struct {
	Name          string
	SourcePath    string
	SourceRelPath string
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

// HomePath converts a home-relative runtime path into an absolute path.
func (e Env) HomePath(rel string) string {
	return filepath.Join(e.HomeDir, rel)
}

// RootPath converts a repo-relative source path into an absolute path.
func (e Env) RootPath(rel string) string {
	return filepath.Join(e.RootDir, rel)
}

// StowPackages returns the package names used by the existing GNU Stow command.
func (e Env) StowPackages() []string {
	return []string{"kitty", "mise", "nvim", "zsh"}
}

// DirectoryLinks returns config directories that should become direct symlinks.
//
// scripts/stow.sh has special migration logic for these paths before Stow runs.
func (e Env) DirectoryLinks() []ManagedLink {
	return []ManagedLink{
		e.managedLink("kitty config directory", ".config/kitty", "kitty/.config/kitty"),
		e.managedLink("mise config directory", ".config/mise", "mise/.config/mise"),
		e.managedLink("nvim config directory", ".config/nvim", "nvim/.config/nvim"),
	}
}

// ManagedLinks returns the current non-Git links owned by initd.
//
// Git is excluded because ~/.gitconfig points at the active profile instead of a
// single fixed source path.
func (e Env) ManagedLinks() []ManagedLink {
	return []ManagedLink{
		e.managedLink("kitty config directory", ".config/kitty", "kitty/.config/kitty"),
		e.managedLink("mise config directory", ".config/mise", "mise/.config/mise"),
		e.managedLink("nvim config directory", ".config/nvim", "nvim/.config/nvim"),
		e.managedLink("zshrc", ".zshrc", "zsh/.zshrc"),
		e.managedLink("zprofile", ".zprofile", "zsh/.zprofile"),
	}
}

// LegacyLinks returns known symlinks from older initd layouts.
//
// Cleanup can remove these safely only when the runtime path resolves to the
// expected legacy source path.
func (e Env) LegacyLinks() []ManagedLink {
	return []ManagedLink{
		e.managedLink("legacy gitconfig", ".gitconfig", "git/.gitconfig"),
		e.managedLink("legacy git config directory", ".config/git", "git/.config/git"),
		e.managedLink("legacy zsh config directory", ".config/zsh", "shell/.config/zsh"),
		e.managedLink("legacy zshrc", ".zshrc", "zsh-home/.zshrc"),
		e.managedLink("legacy mise config", ".config/mise/config.toml", "mise.toml"),
	}
}

// GitConfigPath returns the runtime Git config path read by Git.
func (e Env) GitConfigPath() string {
	return e.HomePath(".gitconfig")
}

// DefaultGitProfile returns the profile selected by bootstrap on first setup.
func (e Env) DefaultGitProfile() GitProfile {
	return e.gitProfile(ProfilePersonal)
}

// GitProfiles returns the complete Git profiles supported by initd.
func (e Env) GitProfiles() []GitProfile {
	return []GitProfile{
		e.gitProfile(ProfilePersonal),
		e.gitProfile(ProfileWork),
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

func (e Env) managedLink(label, runtimeRelPath, sourceRelPath string) ManagedLink {
	return ManagedLink{
		Label:          label,
		RuntimePath:    e.HomePath(runtimeRelPath),
		SourcePath:     e.RootPath(sourceRelPath),
		RuntimeRelPath: runtimeRelPath,
		SourceRelPath:  sourceRelPath,
	}
}

func (e Env) gitProfile(name string) GitProfile {
	sourceRelPath := filepath.Join("git", "profiles", name+".gitconfig")

	return GitProfile{
		Name:          name,
		SourcePath:    e.RootPath(sourceRelPath),
		SourceRelPath: sourceRelPath,
	}
}
