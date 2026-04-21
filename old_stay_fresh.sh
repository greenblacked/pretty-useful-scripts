#!/usr/bin/env bash

# Source function library.
. ~/scripts/functions

# See hidden files.
shopt -s dotglob

# Prompt for sudo password early on.
sudo -v

step "Clear Kernel caches"
  # try sudo update_dyld_shared_cache -force
  try qlmanage -r
  if [ -n "$(ps aux | grep Finder | grep -v grep)" ]; then
    try killall Finder
  fi
next

step "Purge inactive memory"
  sudo /usr/sbin/purge
next


step "Clear history files"
  try :>~/.lesshst
  [ -f ~/.mysql_history ] && try :>~/.mysql_history
next

# step "Clear Vim history files"
#   try find ~/.vim/backup -mindepth 1 ! -name '.gitignore' -exec rm -rf -- {} +
#   [ -d ~/.vim6 ] && try find ~/.vim6/backup -mindepth 1 ! -name '.gitignore' -exec rm -rf -- {} +
#   try :>~/.viminfo  
# next

step "Clear caches"
  try rm -rf ~/.atom/.apm/*
  try find ~/Library/Caches -type f -exec rm -f '{}' \; &>/dev/null
  # try rm -rf ~/Library/Containers/com.apple.Preview/*
  # try rm -rf ~/Library/Containers/com.docker.docker/*
  try find ~/Library/Developer/Xcode/Archives -type f -exec rm -f '{}' \; &>/dev/null
  try find ~/Library/Developer/Xcode/DerivedData -type f -exec rm -f '{}' \; &>/dev/null
  try command -v composer &>/dev/null && composer clearcache 2>/dev/null
next

# # Clear docker containers and images.
# step "Clear docker containers and images"
#     ~/scripts/docker-cleanup.sh
# next

step "Update Homebrew formulae"
  BREW_REPO=$(brew --repo)
  # cd "$(brew --repo)" && git remote -v 
  # brew update --force --verbose 
  # brew upgrade --force --verbose 

  output_start
  for DIR in "$BREW_REPO" "$BREW_REPO"/Library/Taps/*/*; do
    [[ -d "$DIR/.git" ]] || continue
    git -C $DIR fetch
    git -C $DIR reset --hard origin/master
    echo Housekeeping $DIR
    git -C $DIR gc --auto --prune
  done
  output_end

  cd
  # Update to latest Homebrew and latest formulaes as well.
  HOMEBREW_FORCE_BREWED_GIT=1 brew update --force
next

step "Upgrade Homebrew formulae"
  sudo chown -R $(whoami) $LOCAL_BIN
  chmod u+w $LOCAL_BIN
  echo
  # Upgrade all installed unpinned brews.
  HOMEBREW_FORCE_BREWED_GIT=1 HOMEBREW_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew upgrade

step "Clean Homebrew caches"
  echo
  # Cleanup files & symlinks older than 3 days.
  brew cleanup --prune=3 -s
  # Delete donwload cache.
  rm -rf "$(brew --cache)"
  # Repair brew tap.
  brew tap --repair
next

step "Homebrew update"
  echo 
  brew upgrade || true && brew update
  brew list --versions || true
next

step "Terrafrom update"
  echo 
# Check if tfenv is installed
if ! command -v tfenv >/dev/null 2>&1; then
  echo "❌ tfenv is not installed or not in PATH."; exit 1
fi
# Get current and latest versions
CURRENT_TF=$(terraform version 2>/dev/null | head -n 1 | awk "{print \$2}" | tr -d "v" || echo "none")
LATEST_TF=$(tfenv list-remote 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -1)
# Validate fetch
if [ -z "$LATEST_TF" ]; then
  echo "❌ Failed to fetch latest Terraform version."; exit 2
fi
# If already latest
if [ "$CURRENT_TF" = "$LATEST_TF" ]; then
  echo "✅ Terraform is already up-to-date: $CURRENT_TF"
else
  echo "🔄 Updating Terraform from $CURRENT_TF to $LATEST_TF..."
  # Install and switch
  if tfenv install "$LATEST_TF" && tfenv use "$LATEST_TF"; then
    FINAL_TF=$(terraform version 2>/dev/null | head -n 1 | awk "{print \$2}" | tr -d "v")
    if [ "$FINAL_TF" = "$LATEST_TF" ]; then
      echo "🚀 Terraform successfully updated to $FINAL_TF"
      # Remove old version
      if [ "$CURRENT_TF" != "none" ] && [ "$CURRENT_TF" != "$LATEST_TF" ]; then
        echo "🗑 Removing old Terraform version: $CURRENT_TF"
        tfenv uninstall "$CURRENT_TF" || echo "⚠️ Failed to uninstall Terraform $CURRENT_TF"
      fi
    else
      echo "⚠️ Installed version is $FINAL_TF, expected $LATEST_TF"
    fi
  else
    echo "❌ Failed to install Terraform $LATEST_TF. Keeping current version: $CURRENT_TF"
  fi
fi
next

step "Helm update"
  echo 
# Check dependencies
if ! command -v curl >/dev/null 2>&1; then echo "❌ curl not found"; exit 1; fi
if ! command -v jq >/dev/null 2>&1; then echo "❌ jq not found"; exit 1; fi
# Get current Helm version (if any)
CURRENT_HELM=$(helm version --template "{{.Version}}" 2>/dev/null || echo "none")
# Fetch latest release from GitHub API
LATEST_HELM=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r ".tag_name")
# Validate latest version fetch
if [ -z "$LATEST_HELM" ] || [ "$LATEST_HELM" = "null" ]; then
  echo "❌ Failed to retrieve the latest Helm version."; exit 2
fi
# Compare and update if needed
if [ "$CURRENT_HELM" = "$LATEST_HELM" ]; then
  echo "✅ Helm is already up to date: $CURRENT_HELM"
else
  echo "🔄 Updating Helm from $CURRENT_HELM to $LATEST_HELM..."

  # Download and install latest version safely
  if curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --version "$LATEST_HELM"; then
    UPDATED_HELM=$(helm version --template "{{.Version}}" 2>/dev/null)
    if [ "$UPDATED_HELM" = "$LATEST_HELM" ]; then
      echo "🚀 Helm successfully updated to $UPDATED_HELM"
    else
      echo "⚠️ Helm install finished but version mismatch: got $UPDATED_HELM"
    fi
  else
    echo "❌ Helm installation failed. Keeping current version: $CURRENT_HELM"
  fi
fi
next

step "Python update"
  echo 
# Check if pyenv is available
if ! command -v pyenv >/dev/null 2>&1; then
  echo "❌ pyenv is not installed or not in PATH."; exit 1
fi
# Get current Python version
CURRENT_PYTHON=$(python --version 2>/dev/null | awk "{print \$2}" || echo "none")
# Fetch latest stable version from pyenv list
LATEST_PYTHON=$(pyenv install --list | grep -E "^\s*[0-9]+\.[0-9]+\.[0-9]+$" | grep -v - | tail -1 | tr -d " ")
# Validate version fetch
if [ -z "$LATEST_PYTHON" ]; then
  echo "❌ Failed to retrieve latest Python version."; exit 2
fi
# Skip if already at latest
if [ "$CURRENT_PYTHON" = "$LATEST_PYTHON" ]; then
  echo "✅ Python is already up-to-date: $CURRENT_PYTHON"
else
  echo "🔄 Updating Python from $CURRENT_PYTHON to $LATEST_PYTHON..."
  # Install new version first
  if pyenv install "$LATEST_PYTHON"; then
    pyenv global "$LATEST_PYTHON"
    pyenv rehash

    FINAL_PYTHON=$(python --version 2>/dev/null | awk "{print \$2}")
    if [ "$FINAL_PYTHON" = "$LATEST_PYTHON" ]; then
      echo "🚀 Python successfully updated to $FINAL_PYTHON"

      # Remove old version (after successful install)
      if [ "$CURRENT_PYTHON" != "none" ] && [ "$CURRENT_PYTHON" != "$LATEST_PYTHON" ]; then
        echo "🗑 Removing old Python version: $CURRENT_PYTHON"
        pyenv uninstall -f "$CURRENT_PYTHON" || echo "⚠️ Failed to uninstall Python $CURRENT_PYTHON"
      fi
    else
      echo "⚠️ Python installed, but version mismatch: got $FINAL_PYTHON, expected $LATEST_PYTHON"
    fi
  else
    echo "❌ Failed to install Python $LATEST_PYTHON. Keeping current version: $CURRENT_PYTHON"
  fi
fi
next

step "GO update"
  echo 
# Check if gvm is installed
if ! command -v gvm >/dev/null 2>&1; then
  echo "❌ gvm is not installed or not in PATH."; exit 1
fi
# Detect current Go version
CURRENT_GO=$(go version 2>/dev/null | awk "{print \$3}" | tr -d "go" || echo "none")
# Get latest stable Go version from go.dev
LATEST_GO=$(curl -s "https://go.dev/VERSION?m=text" | head -n 1 | tr -d "go")
# Validate version fetch
if [ -z "$LATEST_GO" ]; then
  echo "❌ Failed to fetch latest Go version."; exit 2
fi
# If already latest, do nothing
if [ "$CURRENT_GO" = "$LATEST_GO" ]; then
  echo "✅ Go is already up-to-date: $CURRENT_GO"
else
  echo "🔄 Updating Go from $CURRENT_GO to $LATEST_GO..."
  # Install latest Go
  if gvm install "go$LATEST_GO"; then
    gvm use "go$LATEST_GO" --default
    FINAL_GO=$(go version 2>/dev/null | awk "{print \$3}" | tr -d "go")
    if [ "$FINAL_GO" = "$LATEST_GO" ]; then
      echo "🚀 Go successfully updated to $FINAL_GO"
      # Now remove old version safely
      if [ "$CURRENT_GO" != "none" ] && [ "$CURRENT_GO" != "$LATEST_GO" ]; then
        echo "🗑 Removing old Go version: $CURRENT_GO"
        gvm uninstall "go$CURRENT_GO" || echo "⚠️ Failed to uninstall go$CURRENT_GO"
      fi
    else
      echo "⚠️ Install succeeded, but version mismatch: got $FINAL_GO (expected $LATEST_GO)"
    fi
  else
    echo "❌ Failed to install Go $LATEST_GO. Keeping current version: $CURRENT_GO"
  fi
fi
next

step "GCP Update"
  echo 
  gcloud version
  gcloud components update -q || true 
  gcloud version
next

step "AWS Verstion"
  echo
  aws --version
next

# Clear {ba|z}sh history.
# step "Clear shell history"
#   :>~/.bash_history
#   :>~/.zsh_history
#   history -c    
# next

output_start
diskutil info / | grep --color=never "Free Space"
output_end
