#!/usr/bin/env bash
# Set up local Ruby/Jekyll dependencies; system package changes require opt-in.
set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: scripts/setup-dependencies.sh [--install-system-dependencies]' \
        'Install locked Bundler in .bundle/tools if missing, and gems in vendor/bundle.' \
        'Requires Bash, Ruby >=3.2 and <4, RubyGems, Ruby headers, make, gcc, g++,' \
        'pkg-config, and Ruby OpenSSL/zlib with CA certificates.' \
        'System package installation is opt-in and supported only on Debian/Ubuntu' \
        'with apt-get (sudo required unless already root). No server is started.' \
        'Other platforms must supply prerequisites manually; see README.md.' \
        '  -h, --help                         Show this help' \
        '  --install-system-dependencies     Install missing system prerequisites'
}

install_system=false
for argument in "$@"; do
    if [[ "${argument}" == -h || "${argument}" == --help ]]; then
        usage
        exit 0
    elif [[ "${argument}" == --install-system-dependencies ]]; then
        install_system=true
    else
        printf 'setup-dependencies.sh: unknown argument "%s"; use --help.\n' "${argument}" >&2
        exit 1
    fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
cd -- "${REPO_ROOT}"
readonly BUNDLE="${SCRIPT_DIR}/bundle.sh"

# Limit automatic system installation to the explicitly supported distro family.
supported_system=false
if [[ "$(uname -s)" == Linux && -r /etc/os-release ]]; then
    # os-release is a trusted system file, not repository-supplied configuration.
    . /etc/os-release

    if [[ "${ID:-}" == ubuntu || "${ID:-}" == debian ]]; then
        supported_system=true
    fi
fi

readonly PACKAGES=(ruby ruby-dev build-essential pkg-config libssl-dev zlib1g-dev ca-certificates)

find_missing() {
    missing=()
    for prerequisite in ruby gem make gcc g++ pkg-config; do
        if ! command -v "${prerequisite}" >/dev/null 2>&1; then
            missing+=("${prerequisite}")
        fi
    done

    if command -v ruby >/dev/null 2>&1; then
        # Check the headers for the active Ruby, not just a distro package name.
        if ! ruby -rrbconfig -e 'exit File.file?(File.join(RbConfig::CONFIG.fetch("rubyhdrdir"), "ruby.h"))'; then
            missing+=("Ruby development headers (ruby.h)")
        fi

        # RubyGems downloads require these runtime modules and certificate trust.
        if ! ruby -ropenssl -rzlib -e 'exit File.file?(OpenSSL::X509::DEFAULT_CERT_FILE)'; then
            missing+=("Ruby OpenSSL/zlib and CA certificates")
        fi
    fi
}

# Never modify system packages unless prerequisites are missing and opt-in is set.
find_missing
if (( ${#missing[@]} > 0 )); then
    printf 'setup-dependencies.sh: missing prerequisite: %s\n' "${missing[@]}" >&2

    if [[ "${install_system}" != true ]]; then
        if [[ "${supported_system}" == true ]]; then
            printf 'Re-run with --install-system-dependencies to opt in, or run:\n  sudo apt-get update\n  sudo apt-get install -y %s\n' "${PACKAGES[*]}" >&2
        else
            printf 'Install the listed prerequisites using your platform tools, then retry. Automatic installation supports only Debian/Ubuntu with apt-get.\n' >&2
        fi

        exit 1
    fi

    if [[ "${supported_system}" != true ]] || ! command -v apt-get >/dev/null 2>&1; then
        printf 'setup-dependencies.sh: system installation supports only Debian/Ubuntu with apt-get; install the listed prerequisites manually.\n' >&2
        exit 1
    fi

    # Request privileges only for apt, never for RubyGems or project files.
    privilege=()
    if (( EUID != 0 )); then
        if ! command -v sudo >/dev/null 2>&1; then
            printf 'setup-dependencies.sh: sudo is missing; ask an administrator to run apt-get update and apt-get install -y %s.\n' "${PACKAGES[*]}" >&2
            exit 1
        fi

        privilege=(sudo)
    fi

    "${privilege[@]}" apt-get update
    "${privilege[@]}" apt-get install -y "${PACKAGES[@]}"

    # Verify the actual active tools after apt, including non-system Ruby installs.
    find_missing
    if (( ${#missing[@]} > 0 )); then
        printf 'setup-dependencies.sh: still missing after system installation: %s\n' "${missing[@]}" >&2
        exit 1
    fi
fi

# Older distro Ruby versions require a deliberate user-managed upgrade.
if ! ruby -e 'exit Gem::Requirement.new(">= 3.2", "< 4.0").satisfied_by?(Gem::Version.new(RUBY_VERSION))'; then
    printf 'setup-dependencies.sh: Ruby >=3.2 and <4 is required; install Ruby 3.3 (see .ruby-version) and matching development headers, then retry. Older distro Ruby is not upgraded automatically.\n' >&2
    exit 1
fi

# Reuse compatible installed Bundler before downloading a project-local copy.
if ! "${BUNDLE}" --version; then
    bundler_version="$(ruby -e '
        version = File.read("Gemfile.lock")[/^BUNDLED WITH\n\s+(\S+)/, 1]
        abort "setup-dependencies.sh: Gemfile.lock has no BUNDLED WITH version" unless version
        puts version
    ')"
    printf 'Installing Bundler %s locally...\n' "${bundler_version}"
    gem install bundler --version "${bundler_version}" --no-document --install-dir "${REPO_ROOT}/.bundle/tools"
    "${BUNDLE}" --version
fi

# Frozen mode fails on manifest/platform mismatches instead of rewriting the lock.
export BUNDLE_FROZEN=true
"${BUNDLE}" config set --local path vendor/bundle

if ! "${BUNDLE}" check; then
    "${BUNDLE}" install
fi

"${BUNDLE}" check
printf 'Setup complete. Run:\n  cd %q\n  ./scripts/serve.sh\n  ./scripts/serve.sh --show-unpublished\n  ./scripts/bundle.sh exec ruby scripts/check.rb\n  JEKYLL_ENV=production ./scripts/bundle.sh exec jekyll build --trace\n' "${REPO_ROOT}"
