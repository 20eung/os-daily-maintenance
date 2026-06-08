#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# daily_maintenance.sh
# 시스템 일일 점검 및 자동 업데이트 (Linux/macOS 통합)
# ─────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(dirname "$0")"

# 환경 설정 로드 (순서: .env -> .env.os -> .env.local)
[ -f "$SCRIPT_DIR/.env" ]             && source "$SCRIPT_DIR/.env"
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
[ -f "$SCRIPT_DIR/.env.${OS_TYPE}" ] && source "$SCRIPT_DIR/.env.${OS_TYPE}"
[ -f "$SCRIPT_DIR/.env.local" ]       && source "$SCRIPT_DIR/.env.local"

# ─────────────────────────────────────────────────────────
# 환경 설정 및 초기화
# ─────────────────────────────────────────────────────────
export HOME="${MAINTENANCE_HOME:-${HOME:-}}"
if [ -z "$HOME" ]; then
    echo "ERROR: HOME directory not found. Please set MAINTENANCE_HOME in .env" >&2
    exit 1
fi

# OS별 PATH 기본값
if [ "$OS_TYPE" = "darwin" ]; then
    export PATH="${MAINTENANCE_PATH:-$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin}:$PATH"
else
    export PATH="${MAINTENANCE_PATH:-$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}:$PATH"
fi

# NVM 설정 (cron 환경에서도 안전하게 동작하도록 조건부 처리)
if [ -d "$HOME/.nvm" ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh" 2>/dev/null || true
fi

# 변수 설정 (기본값 설정 포함)
MAINTENANCE_BOT_KEY="${MAINTENANCE_BOT_KEY:-}"
MAINTENANCE_CHAT_ID="${MAINTENANCE_CHAT_ID:-}"
# 통일된 프로젝트 루트 (macOS·OCI 모두 ~/Project 사용). 미설정 시 자동으로 안전 fallback.
USER_PROJECT_DIRS="${USER_PROJECT_DIRS:-${USER_PROJECT_DIR:-$HOME/Project}}"
# 첫 토큰이 실제로 존재하는 디렉토리가 되도록 보정 (공백 구분 다중 경로 지원)
_cleaned=""
for _d in $USER_PROJECT_DIRS; do
    if [ -d "$_d" ]; then _cleaned="${_cleaned:+$_cleaned }$_d"; fi
done
[ -n "$_cleaned" ] && USER_PROJECT_DIRS="$_cleaned"
unset _d _cleaned
LOG_STAGING_DIR="${LOG_STAGING_DIR:-$SCRIPT_DIR/logs}"
LOG_FILE="$LOG_STAGING_DIR/maintenance_${OS_TYPE}_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
NL=$'\n'

# 시스템 모니터링 임계값 (기본값)
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-85}"
MEMORY_USAGE_THRESHOLD="${MEMORY_USAGE_THRESHOLD:-85}"
CPU_TEMP_THRESHOLD="${CPU_TEMP_THRESHOLD:-80}"
DISK_TEMP_THRESHOLD="${DISK_TEMP_THRESHOLD:-55}"

# 텔레그램 설정 누락 시 경고 (단, 로깅은 계속 진행)
if [ -z "$MAINTENANCE_BOT_KEY" ] || [ -z "$MAINTENANCE_CHAT_ID" ]; then
    echo "WARNING: Telegram BOT_KEY or CHAT_ID is missing in .env. Notifications will be skipped." >&2
fi

mkdir -p "$LOG_STAGING_DIR"

# ─────────────────────────────────────────────────────────
# sudo 권한 체크 및 안내
# ─────────────────────────────────────────────────────────
SUDO_AVAILABLE=false
if command -v sudo &>/dev/null; then
    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=true
    else
        echo "WARNING: sudo requires a password or is not allowed for this user." >&2
        echo "To allow passwordless sudo for automation, add the following to 'visudo':" >&2
        if [ "$OS_TYPE" = "darwin" ]; then
            echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/find" >&2
        else
            echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/find" >&2
        fi
    fi
fi

log()     { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
section() { echo "" >> "$LOG_FILE"; log "━━━ $1 ━━━"; }

send_msg() {
    [ -z "$MAINTENANCE_BOT_KEY" ] || [ -z "$MAINTENANCE_CHAT_ID" ] && return

    local message="$1"
    message=$(echo "$message" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    if [ "${#message}" -gt 4000 ]; then
        message="${message:0:3900}${NL}${NL}...(메시지가 너무 길어 일부 생략되었습니다. 자세한 로그를 확인하세요.)"
    fi

    log "텔레그램 메시지 전송 시도 중 (길이: ${#message})..."
    curl -s -X POST "https://api.telegram.org/bot${MAINTENANCE_BOT_KEY}/sendMessage" \
        --data-urlencode "chat_id=${MAINTENANCE_CHAT_ID}" \
        --data-urlencode "text=$message" \
        --data-urlencode "parse_mode=HTML" >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"
}

{
log "=== 시스템 일일 점검 시작 ($OS_TYPE): $TIMESTAMP ==="
SCRIPT_START_TIME=$(date +%s)

RESULTS=()
UPDATED=()
ERRORS=()
SKIPPED=()

# ── 1. OS 패키지 업데이트 ─────────────────────────────────
if [ "$OS_TYPE" = "darwin" ]; then
    # ── 1a. Homebrew ──────────────────────────────────────
    section "OS 패키지 (brew)"
    if command -v brew &>/dev/null; then
        brew update -q 2>>"$LOG_FILE"
        UPGRADABLE=$(brew outdated 2>/dev/null | wc -l | tr -d ' ')
        log "업그레이드 가능: ${UPGRADABLE}개"
        if [ "$UPGRADABLE" -gt 0 ]; then
            brew upgrade -q 2>>"$LOG_FILE" && {
                log "brew 업그레이드 완료 (${UPGRADABLE}개)"
                UPDATED+=("OS(brew) ${UPGRADABLE}개")
            } || {
                log "brew 업그레이드 실패"
                ERRORS+=("OS(brew)")
            }
            brew autoremove -q 2>>"$LOG_FILE"
            brew cleanup -q 2>>"$LOG_FILE"
        else
            log "brew 최신 상태"
            RESULTS+=("Homebrew: 최신")
        fi
    else
        log "Homebrew 미설치 — 건너뜀"
        SKIPPED+=("Homebrew")
    fi

    # ── 1b. Homebrew Cask (greedy) ────────────────────────
    section "Cask (greedy)"
    if command -v brew &>/dev/null; then
        cask_outdated=$(brew outdated --greedy 2>/dev/null | wc -l | tr -d ' ')
        log "greedy cask 업그레이드 가능: ${cask_outdated}개"
        if [ "$cask_outdated" -gt 0 ]; then
            brew upgrade --greedy -q 2>>"$LOG_FILE" && {
                log "cask greedy 업그레이드 완료 (${cask_outdated}개)"
                UPDATED+=("Cask(greedy) ${cask_outdated}개")
            } || {
                log "cask greedy 업그레이드 일부 실패 (계속 진행)"
                RESULTS+=("Cask(greedy): 일부 실패")
            }
        else
            log "cask greedy 최신 상태"
            RESULTS+=("Cask(greedy): 최신")
        fi
    else
        log "Homebrew 미설치 — Cask(greedy) 건너뜀"
        SKIPPED+=("Cask")
    fi

else
    # ── 1. APT (Linux) ────────────────────────────────────
    section "OS 패키지 (apt)"
    if command -v apt &>/dev/null; then
        sudo apt update -qq 2>>"$LOG_FILE"
        # apt upgrade 전에 목록 캡처 (섹션 13 보안 업데이트 체크에서 재사용)
        _APT_UPGRADABLE_LIST=$(apt list --upgradable 2>/dev/null | grep -v "Listing...")
        UPGRADABLE=$(echo "$_APT_UPGRADABLE_LIST" | wc -l)
        log "업그레이드 가능: ${UPGRADABLE}개"
        if [ "$UPGRADABLE" -gt 0 ]; then
            sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq 2>>"$LOG_FILE" && {
                log "apt 업그레이드 완료 (${UPGRADABLE}개)"
                UPDATED+=("OS(apt) ${UPGRADABLE}개")
            } || {
                log "apt 업그레이드 실패"
                ERRORS+=("OS(apt)")
            }
            sudo apt autoremove -y -qq 2>>"$LOG_FILE"
            sudo apt autoclean -y -qq 2>>"$LOG_FILE"
        else
            log "apt 시스템 최신 상태"
            RESULTS+=("APT: 최신")
        fi
    else
        log "apt 미설치 (또는 권한 없음) — 건너뜀"
        SKIPPED+=("APT/OS패키지")
    fi

    # ── 1c. snap 패키지 (Linux) ───────────────────────────
    section "snap 패키지"
    if command -v snap &>/dev/null; then
        snap_outdated=$(snap refresh --list 2>/dev/null | tail -n +2 | grep -v '^$' | wc -l | tr -d ' ')
        log "snap 업그레이드 가능: ${snap_outdated}개"
        if [ "$snap_outdated" -gt 0 ]; then
            sudo snap refresh 2>>"$LOG_FILE" && {
                log "snap 업데이트 완료 (${snap_outdated}개)"
                UPDATED+=("snap ${snap_outdated}개")
            } || {
                log "snap 업데이트 실패"
                ERRORS+=("snap 업데이트 실패")
            }
        else
            log "snap 최신 상태"
            RESULTS+=("snap: 최신")
        fi
    else
        log "snap 미설치 — 건너뜀"
        SKIPPED+=("snap")
    fi
fi

# ── 2. cokacdir 업데이트 ─────────────────────────────────
section "cokacdir"
if command -v cokacctl &>/dev/null; then
    cokacctl update 2>>"$LOG_FILE" && {
        log "cokacdir 업데이트 완료"
        UPDATED+=("cokacdir")
    } || {
        log "cokacdir 최신 상태"
        RESULTS+=("cokacdir: 최신")
    }
else
    log "cokacctl 미설치 — 건너뜀"
    SKIPPED+=("cokacdir")
fi

# ── 3. Claude Code 업데이트 ───────────────────────────────
section "Claude Code"
if command -v claude &>/dev/null; then
    CLAUDE_BEFORE=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log "현재 버전: $CLAUDE_BEFORE"
    claude update 2>>"$LOG_FILE" && {
        CLAUDE_AFTER=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ "$CLAUDE_BEFORE" != "$CLAUDE_AFTER" ]; then
            log "Claude Code 업데이트: $CLAUDE_BEFORE → $CLAUDE_AFTER"
            UPDATED+=("Claude Code ${CLAUDE_BEFORE}→${CLAUDE_AFTER}")
        else
            log "Claude Code 최신 상태 ($CLAUDE_AFTER)"
            RESULTS+=("Claude: $CLAUDE_AFTER 최신")
        fi
    } || {
        log "Claude Code 업데이트 실패 (또는 최신 상태)"
        RESULTS+=("Claude: $CLAUDE_BEFORE (확인불가)")
    }
else
    log "Claude Code 미설치 — 건너뜀"
    SKIPPED+=("Claude")
fi

# ── 4. bkit 플러그인 업데이트 ─────────────────────────────
section "bkit 플러그인"
BKIT_PLUG_PATH="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$BKIT_PLUG_PATH" ]; then
    BKIT_BEFORE=$(python3 -c "import sys,json; d=json.load(open('$BKIT_PLUG_PATH')); print(d['plugins'].get('bkit@bkit-marketplace', [{'version':'unknown'}])[0]['version'])" 2>/dev/null || echo "unknown")
    log "현재 버전: $BKIT_BEFORE"
    if command -v claude &>/dev/null; then
        claude plugin marketplace update bkit-marketplace 2>>"$LOG_FILE"
        claude plugin update bkit@bkit-marketplace 2>>"$LOG_FILE" && {
            BKIT_AFTER=$(python3 -c "import sys,json; d=json.load(open('$BKIT_PLUG_PATH')); print(d['plugins'].get('bkit@bkit-marketplace', [{'version':'unknown'}])[0]['version'])" 2>/dev/null || echo "unknown")
            if [ "$BKIT_BEFORE" != "$BKIT_AFTER" ]; then
                log "bkit 업데이트: $BKIT_BEFORE → $BKIT_AFTER"
                UPDATED+=("bkit ${BKIT_BEFORE}→${BKIT_AFTER}")
            else
                log "bkit 최신 상태 ($BKIT_AFTER)"
                RESULTS+=("bkit: $BKIT_AFTER 최신")
            fi
        } || {
            log "bkit 업데이트 실패 (또는 최신 상태)"
            RESULTS+=("bkit: $BKIT_BEFORE (확인불가)")
        }
    else
        log "claude 미설치 — bkit 업데이트 건너뜀"
        SKIPPED+=("bkit (claude 미설치)")
    fi
else
    log "bkit 플러그인 미설치 — 건너뜀"
    SKIPPED+=("bkit")
fi

# ── 5. npm 전역 패키지 업데이트 ──────────────────────────
section "npm 전역 패키지"
if command -v npm &>/dev/null; then
    npm_outdated=$(npm outdated -g 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    if [ "$npm_outdated" -gt 0 ]; then
        npm update -g 2>>"$LOG_FILE" && {
            log "npm 전역 패키지 ${npm_outdated}개 업데이트 완료"
            UPDATED+=("npm 전역 ${npm_outdated}개")
        } || ERRORS+=("npm")
    else
        npm_ver=$(npm --version 2>/dev/null || echo "")
        log "npm 전역 패키지 최신 상태"
        RESULTS+=("npm: ${npm_ver:+$npm_ver }최신")
    fi
else
    log "npm 미설치 — 건너뜀"
    SKIPPED+=("npm")
fi

# ── 6. pip 설치된 패키지 업데이트 ────────────────────────
# 정책: .env 의 PIP_TARGET_PACKAGES 가 있으면 그것만 화이트리스트로,
#        없으면 pip3 list --outdated 결과를 모두 갱신. 시스템 python(PEP 668) 보호를 위해
#        user-site(--user) 또는 venv 가 아니면 pipx/python -m pip 으로 격리 시도.
section "pip 설치된 패키지"
pip_updated=0
pip_skipped_pep668=0
_has_target_pkgs=false
[ -n "${PIP_TARGET_PACKAGES:-}" ] && _has_target_pkgs=true

# pip 실행 wrapper: 가능하면 'python3 -m pip' 사용 (PATH 의 pip3 가 깨졌을 때 대비)
_pip() {
    if command -v pip3 &>/dev/null; then
        pip3 "$@"
    elif command -v python3 &>/dev/null; then
        python3 -m pip "$@"
    else
        return 127
    fi
}

# PEP 668 / user-site 가용성 사전 체크
# Ubuntu 23+, Homebrew python, 등 externally-managed-environment 환경에서는
# --upgrade, --user 둘 다 막혀있다. 이런 환경에서는 venv 가 활성화돼있을 때만 시도.
# 주의: set -o pipefail 환경에서 `cmd | grep -q` 는 grep 매치 시(grep exit 0) OK 이지만,
#        grep 가 미매치면 grep exit 1 → pipefail 로 false. 변수로 받아 직접 검사.
_pip_blocked_by_pep668=false
_pip_dryrun_out=$(_pip install --dry-run --quiet requests 2>&1 || true)
if _pip install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
    if echo "$_pip_dryrun_out" | grep -q "externally-managed-environment"; then
        _pip_dryrun_user_out=$(_pip install --user --dry-run --quiet requests 2>&1 || true)
        if ! echo "$_pip_dryrun_user_out" | grep -q "externally-managed-environment"; then
            : # --user 는 동작 — 일반 모드
        else
            _pip_blocked_by_pep668=true
        fi
    fi
fi
# venv 활성화 여부 (PEP 668 환경이라도 venv 안이면 OK)
_pip_in_venv=false
[ -n "${VIRTUAL_ENV:-}" ] && _pip_in_venv=true
unset _pip_dryrun_out _pip_dryrun_user_out

_install_one() {
    # $1: pkg, $2: scope (user|break|normal)
    local pkg="$1" scope="${2:-normal}" out
    case "$scope" in
        user)
            out=$(_pip install --user --upgrade "$pkg" -q 2>&1) && return 0
            ;;
        break)
            out=$(_pip install --break-system-packages --upgrade "$pkg" -q 2>&1) && return 0
            ;;
        *)
            out=$(_pip install --upgrade "$pkg" -q 2>&1) && return 0
            ;;
    esac
    if echo "$out" | grep -q "externally-managed-environment"; then
        return 2   # PEP 668 — caller 가 user 로 재시도
    fi
    return 1
}

_upgrade_loop() {
    # stdin: pkg 목록 (한 줄에 하나), $1: scope
    local scope="$1" pkg
    while IFS= read -r pkg; do
        pkg=$(echo "$pkg" | awk '{print $1}')
        [ -z "$pkg" ] && continue
        [ "$pkg" = "Package" ] && continue
        [ "$pkg" = "pydantic-core" ] && continue  # pip 호환성 보호
        if _install_one "$pkg" "$scope"; then
            log "  ✓ $pkg 업그레이드 완료"
            pip_updated=$((pip_updated+1))
        elif [ $? -eq 2 ] && [ "$scope" != "user" ]; then
            if _install_one "$pkg" "user"; then
                log "  ✓ $pkg 업그레이드 완료 (--user)"
                pip_updated=$((pip_updated+1))
            else
                log "  ✗ $pkg 업그레이드 실패 (--user 도 실패)"
            fi
        else
            log "  ✗ $pkg 업그레이드 실패"
        fi
    done
}

if ! command -v pip3 &>/dev/null && ! command -v python3 &>/dev/null; then
    log "pip3/python3 미설치 — 건너뜀"
    SKIPPED+=("pip3")
else
    # PEP 668 으로 시스템이 잠겨있고 venv 도 비활성화된 환경 → 안전하게 SKIPPED
    if $_pip_blocked_by_pep668 && ! $_pip_in_venv; then
        log "pip 섹션 건너뜀: PEP 668 (externally-managed) 환경 + venv 미활성."
        log "  시스템 python 보호를 위해 자동 업그레이드를 시도하지 않습니다."
        log "  활성화된 venv 가 있거나 .env 의 PIP_TARGET_PACKAGES 가 비어있으면 시도합니다."
        SKIPPED+=("pip (PEP 668)")
    else
        if $_has_target_pkgs; then
            # 화이트리스트 모드: PIP_TARGET_PACKAGES 를 그대로 사용
            log "PIP_TARGET_PACKAGES 사용: ${PIP_TARGET_PACKAGES}"
            _scope=normal
            if $_pip_blocked_by_pep668; then _scope=user; fi   # venv 안이지만 외부 lock 인 경우 user 우선
            echo "$PIP_TARGET_PACKAGES" | tr ' ' '\n' | _upgrade_loop "$_scope"
        else
            # 자동 모드: pip list --outdated 결과 전체
            _outdated_list=$(_pip list --outdated 2>/dev/null | tail -n +3)
            if [ -n "$_outdated_list" ]; then
                _scope=normal
                if $_pip_blocked_by_pep668; then _scope=user; fi
                echo "$_outdated_list" | _upgrade_loop "$_scope"
            fi
        fi
    fi
    if [ "$pip_updated" -gt 0 ]; then
        UPDATED+=("pip ${pip_updated}개")
    elif ! $_pip_blocked_by_pep668 || $_pip_in_venv; then
        # 정상 환경일 때만 "최신" 보고. PEP 668 + venv-off 는 SKIPPED 가 위에서 처리됨.
        _pip_ver=$(_pip --version 2>/dev/null | awk '{print $2}' || echo "")
        RESULTS+=("pip: ${_pip_ver:+$_pip_ver }최신")
    fi
fi
unset _pip _pip_blocked_by_pep668 _pip_in_venv _install_one _upgrade_loop _has_target_pkgs _outdated_list

# ── 7. GitHub 저장소 동기화 (pull 자동, push 알림) ──────
section "GitHub 저장소"
if command -v git &>/dev/null && [ -n "$USER_PROJECT_DIRS" ]; then
    git_pulled=()
    git_pull_failed=()
    git_ahead=()
    git_noremote=()
    git_repo_count=0
    while IFS= read -r repo; do
        git_repo_count=$((git_repo_count+1))
        repo_name=$(basename "$repo")
        branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
        remote=$(git -C "$repo" remote 2>/dev/null | head -1)
        if [ -z "$remote" ]; then
            git_noremote+=("$repo_name")
            continue
        fi
        git -C "$repo" fetch "$remote" -q 2>/dev/null
        behind=$(git -C "$repo" rev-list "HEAD..${remote}/${branch}" --count 2>/dev/null || echo 0)
        ahead=$(git -C "$repo" rev-list "${remote}/${branch}..HEAD" --count 2>/dev/null || echo 0)
        if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
            git_pull_failed+=("$repo_name (↓${behind} ↑${ahead} — diverged, 수동 처리 필요)")
        elif [ "$behind" -gt 0 ]; then
            if git -C "$repo" stash push -u -m "auto-maintenance-$(date +%s)" >/dev/null 2>&1; then
                if git -C "$repo" pull "$remote" "$branch" -q 2>>"$LOG_FILE"; then
                    log "pull 완료: $repo_name (${behind}커밋, 로컬 변경사항 stash됨)"
                    git_pulled+=("$repo_name (↓${behind}, 변경사항 stash)")
                else
                    log "pull 실패: $repo_name"
                    git -C "$repo" stash pop >/dev/null 2>&1
                    git_pull_failed+=("$repo_name (pull 실패, stash 복구됨)")
                fi
            else
                if git -C "$repo" pull "$remote" "$branch" -q 2>>"$LOG_FILE"; then
                    log "pull 완료: $repo_name (${behind}커밋)"
                    git_pulled+=("$repo_name (↓${behind})")
                else
                    log "pull 실패: $repo_name"
                    git_pull_failed+=("$repo_name (pull 실패 - 로컬 변경사항 있음, 수동 처리 필요)")
                fi
            fi
        elif [ "$ahead" -gt 0 ]; then
            git_ahead+=("$repo_name (↑${ahead} 커밋 미푸시)")
        else
            log "최신: $repo_name"
        fi
    done < <(find ${USER_PROJECT_DIRS:-} -maxdepth 3 -name "node_modules" -prune -o -name ".git" -type d -print 2>/dev/null | sed 's|/\.git$||' | sort -u)

    [ ${#git_pulled[@]} -gt 0 ]      && UPDATED+=("Git pull: ${#git_pulled[@]}개 (${git_pulled[*]})")
    [ ${#git_pull_failed[@]} -gt 0 ] && { for r in "${git_pull_failed[@]}"; do ERRORS+=("Git: $r"); done; }
    [ ${#git_ahead[@]} -gt 0 ]       && { for r in "${git_ahead[@]}"; do ERRORS+=("Git push 필요: $r"); done; }
    [ ${#git_noremote[@]} -gt 0 ]    && log "remote 없음: ${git_noremote[*]}"
    if [ "$git_repo_count" -eq 0 ]; then
        log "Git 저장소 없음 — 건너뜀 ($USER_PROJECT_DIRS)"
        SKIPPED+=("GitHub (저장소 없음)")
    elif [ ${#git_pulled[@]} -eq 0 ] && [ ${#git_pull_failed[@]} -eq 0 ] && [ ${#git_ahead[@]} -eq 0 ]; then
        RESULTS+=("GitHub: 모두 최신")
    fi
else
    if [ -z "$USER_PROJECT_DIRS" ]; then
        log "USER_PROJECT_DIRS 미설정 — 건너뜀"
        SKIPPED+=("GitHub (USER_PROJECT_DIRS 미설정)")
    else
        log "git 미설치 — 건너뜀"
        SKIPPED+=("Git")
    fi
fi

# ── 8. Obsidian-Wiki 자동 동기화 ─────────────────────────
section "Obsidian-Wiki 동기화"
WIKI_DIR="${OBSIDIAN_WIKI_DIR:-$HOME/Project/Obsidian-Wiki}"
if [ -d "$WIKI_DIR/.git" ]; then
    # cd 없이 git -C 만 사용 (현재 작업 디렉토리 보존)
    if ! git -C "$WIKI_DIR" diff --quiet 2>/dev/null || \
       ! git -C "$WIKI_DIR" diff --cached --quiet 2>/dev/null || \
       [ -n "$(git -C "$WIKI_DIR" ls-files --others --exclude-standard 2>/dev/null)" ]; then
        git -C "$WIKI_DIR" add -A 2>>"$LOG_FILE"
        git -C "$WIKI_DIR" commit -m "sync: $(date +%Y-%m-%d)" 2>>"$LOG_FILE" && {
            log "Obsidian-Wiki 변경사항 커밋 완료"
        } || log "Obsidian-Wiki 커밋 실패 (변경 없음 또는 오류)"
    else
        log "Obsidian-Wiki 변경사항 없음"
    fi
    git -C "$WIKI_DIR" push 2>>"$LOG_FILE" && {
        log "Obsidian-Wiki push 완료"
        UPDATED+=("Obsidian-Wiki 동기화")
    } || {
        log "Obsidian-Wiki push 실패 (이미 최신 또는 네트워크 오류)"
        RESULTS+=("Obsidian-Wiki: push 불필요")
    }
else
    log "Obsidian-Wiki 디렉토리 없음 — 건너뜀 ($WIKI_DIR)"
    SKIPPED+=("Obsidian-Wiki")
fi

# ── 9. conda 업데이트 (macOS 전용) ───────────────────────
if [ "$OS_TYPE" = "darwin" ]; then
    section "conda"
    if [ -f "${MAINTENANCE_CONDA_SH:-/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh}" ]; then
        source "${MAINTENANCE_CONDA_SH:-/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh}" 2>/dev/null
    fi
    if command -v conda &>/dev/null; then
        CONDA_BEFORE=$(conda --version 2>&1 | awk '{print $2}')
        log "현재 conda 버전: $CONDA_BEFORE"
        conda update conda --no-update-deps -y -q 2>>"$LOG_FILE" && {
            CONDA_AFTER=$(conda --version 2>&1 | awk '{print $2}')
            if [ "$CONDA_BEFORE" != "$CONDA_AFTER" ]; then
                log "conda 업데이트: ${CONDA_BEFORE}→${CONDA_AFTER}"
                UPDATED+=("conda ${CONDA_BEFORE}→${CONDA_AFTER}")
            else
                log "conda 최신 상태 ($CONDA_AFTER)"
                RESULTS+=("conda: $CONDA_AFTER 최신")
            fi
        } || {
            log "conda 업데이트 실패"
            ERRORS+=("conda")
        }
        # conda clean --all 은 root 권한이 필요할 수 있음 (macOS) → SUDO 가드
        if [ "$SUDO_AVAILABLE" = true ]; then
            sudo -n conda clean --all -y -q 2>>"$LOG_FILE" \
                || conda clean --all -y -q 2>>"$LOG_FILE" \
                || log "conda clean 권한 부족 (root/admin 필요)"
        else
            conda clean --all -y -q 2>>"$LOG_FILE" \
                || log "conda clean 실패 (root 권한 필요)"
        fi
    else
        log "conda 미설치 — 건너뜀"
        SKIPPED+=("conda")
    fi
fi

# ── 10. Docker 컨테이너 관리 ─────────────────────────────
section "Docker"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "watchtower"; then
        WATCHTOWER_NAME=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "watchtower" | head -1)
        log "Watchtower 실행 중 ($WATCHTOWER_NAME) — 컨테이너 업데이트 건너뜀"
        SKIPPED+=("Docker (Watchtower가 관리)")
    else
        DOW_DOCKER=$(date +%w)
        if [ "$DOW_DOCKER" -ne 0 ]; then
            log "Docker 이미지 업데이트: 주 1회 (일요일) 실행 — 오늘은 건너뜀"
            SKIPPED+=("Docker 이미지 pull (일요일에 실행)")
        else
        docker_updated=()
        docker_failed=()
        while IFS= read -r container; do
            image=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null)
            [ -z "$image" ] && continue
            pull_out=$(docker pull "$image" 2>&1)
            if echo "$pull_out" | grep -q "Status: Downloaded newer image"; then
                # compose 프로젝트 찾기 (라벨 기반)
                compose_file=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$container" 2>/dev/null)
                compose_dir=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container" 2>/dev/null)
                if [ -n "$compose_dir" ] && [ -f "${compose_file:-$compose_dir/docker-compose.yml}" ]; then
                    # compose 관리 컨테이너: up -d 로 재생성
                    docker compose -f "${compose_file:-$compose_dir/docker-compose.yml}" up -d 2>>"$LOG_FILE" && {
                        log "업데이트 및 재생성 완료 (compose): $container ($image)"
                        docker_updated+=("$container")
                    } || {
                        log "compose 재생성 실패: $container"
                        docker_failed+=("$container")
                    }
                else
                    # 일반 컨테이너: stop → rm → run (기존 run 명령 재현 불가 → 경고)
                    log "경고: $container 는 compose 외 컨테이너 — 수동 재생성 필요 (이미지만 pull됨)"
                    ERRORS+=("Docker 수동 재생성 필요: $container (새 이미지 pull 완료)")
                fi
            else
                log "최신 상태: $container ($image)"
            fi
        done < <(docker ps --format '{{.Names}}' 2>/dev/null)
        [ ${#docker_updated[@]} -gt 0 ] && UPDATED+=("Docker 재시작: ${docker_updated[*]}")
        [ ${#docker_failed[@]} -gt 0 ]  && { for c in "${docker_failed[@]}"; do ERRORS+=("Docker 재시작 실패: $c"); done; }
        [ ${#docker_updated[@]} -eq 0 ] && [ ${#docker_failed[@]} -eq 0 ] && RESULTS+=("Docker: 모두 최신")
        fi  # DOW_DOCKER 주 1회 조건 끝
    fi
else
    log "Docker 미설치 또는 데몬 미실행 — 건너뜀"
    SKIPPED+=("Docker")
fi

# ── 11. 시스템 상태 확인 ─────────────────────────────────
section "시스템 상태"
DISK_USAGE=$(df / 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}' | tr -d ' ')
DISK_AVAIL_K=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')
DISK_AVAIL_HUMAN=$(numfmt --to=iec --suffix=B "$((DISK_AVAIL_K * 1024))" 2>/dev/null || echo "${DISK_AVAIL_K:-0}K")
log "루트 파티션 사용률: ${DISK_USAGE}% (잔여: ${DISK_AVAIL_HUMAN})"
[ "$DISK_USAGE" -gt "$DISK_USAGE_THRESHOLD" ] && ERRORS+=("디스크 ${DISK_USAGE}% (잔여 ${DISK_AVAIL_HUMAN})")

# 메모리 사용률 (OS별)
if [ "$OS_TYPE" = "darwin" ]; then
    MEM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    if [ "$MEM_TOTAL" -gt 0 ]; then
        PAGE_SIZE=$(vm_stat 2>/dev/null | awk '/page size of/{print $8}')
        PAGE_SIZE="${PAGE_SIZE:-4096}"
        PAGES_FREE=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,"",$3); print $3}')
        PAGES_INACTIVE=$(vm_stat 2>/dev/null | awk '/Pages inactive/{gsub(/\./,"",$3); print $3}')
        PAGES_FREE="${PAGES_FREE:-0}"
        PAGES_INACTIVE="${PAGES_INACTIVE:-0}"
        MEM_FREE_BYTES=$(( (PAGES_FREE + PAGES_INACTIVE) * PAGE_SIZE ))
        MEM_USAGE=$(( (MEM_TOTAL - MEM_FREE_BYTES) * 100 / MEM_TOTAL ))
        log "메모리 사용률: ${MEM_USAGE}%"
        [ "$MEM_USAGE" -gt "$MEMORY_USAGE_THRESHOLD" ] && ERRORS+=("메모리 ${MEM_USAGE}% 경고")
    fi
else
    MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", ($3/$2)*100)}')
    log "메모리 사용률: ${MEM_USAGE}%"
    [ "$MEM_USAGE" -gt "$MEMORY_USAGE_THRESHOLD" ] && ERRORS+=("메모리 ${MEM_USAGE}% 경고")
fi

# Swap 사용률 (Linux: swap 있을 때만)
if [ "$OS_TYPE" != "darwin" ]; then
    SWAP_TOTAL=$(free | awk '/Swap:/{print $2}')
    if [ "${SWAP_TOTAL:-0}" -gt 0 ]; then
        SWAP_USAGE=$(free | awk '/Swap:/{printf("%.0f", ($3/$2)*100)}')
        log "Swap 사용률: ${SWAP_USAGE}%"
        [ "$SWAP_USAGE" -gt 50 ] && ERRORS+=("Swap ${SWAP_USAGE}% 경고 (메모리 압박 가능성)")
    fi
fi

# CPU 온도 (OS별)
if [ "$OS_TYPE" = "darwin" ]; then
    if command -v osx-cpu-temp &>/dev/null; then
        CPU_TEMP=$(osx-cpu-temp | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$CPU_TEMP" ]; then
            log "CPU 온도: ${CPU_TEMP}°C"
            if (( $(echo "$CPU_TEMP > $CPU_TEMP_THRESHOLD" | bc -l) )); then
                ERRORS+=("CPU 온도 ${CPU_TEMP}°C 경고")
            fi
        fi
    fi
else
    if command -v sensors &>/dev/null; then
        CPU_TEMP=$(sensors 2>/dev/null | grep -oP 'Core 0:.*?\+\K[0-9.]+' | head -1)
        if [ -n "$CPU_TEMP" ]; then
            log "CPU 온도: ${CPU_TEMP}°C"
            if (( $(echo "$CPU_TEMP > $CPU_TEMP_THRESHOLD" | bc -l) )); then
                ERRORS+=("CPU 온도 ${CPU_TEMP}°C 경고")
            fi
        fi
    else
        log "lm-sensors 미설치 — 온도 감지 불가"
    fi
fi

# 디스크 온도 (OS별 디바이스 경로)
if command -v smartctl &>/dev/null; then
    if [ "$OS_TYPE" = "darwin" ]; then
        DISK_TEMP=$(sudo smartctl -a /dev/disk0 2>/dev/null | awk '/Temperature:|Air_Flow_Temperature|Temperature_Celsius/{print $NF}' | head -1)
    else
        DISK_TEMP=$(smartctl -a /dev/sda 2>/dev/null | grep "Temperature_Celsius" | awk '{print $10}' | head -1)
    fi
    if [ -n "${DISK_TEMP:-}" ]; then
        log "디스크 온도: ${DISK_TEMP}°C"
        if [ "$DISK_TEMP" -gt "$DISK_TEMP_THRESHOLD" ]; then
            ERRORS+=("디스크 온도 ${DISK_TEMP}°C 경고")
        fi
    fi
fi

# ── 12. 서비스 상태 확인 ─────────────────────────────────
section "서비스 상태"
if [ "$OS_TYPE" = "darwin" ]; then
    # macOS: launchctl (양수 exit code = 오류, apple 서비스 제외)
    failed_services=$(launchctl list | awk '$2 ~ /^[0-9]+$/ && $2 > 0 {print $3}' | grep -v "^com\.apple\." || true)
    if [ -n "$failed_services" ]; then
        while read -r service; do
            log "비정상 종료 서비스 감지: $service"
            ERRORS+=("실패 서비스: $service")
        done <<< "$failed_services"
    else
        log "모든 서비스 정상 (비정상 종료 서비스 없음)"
        RESULTS+=("서비스: 정상")
    fi
else
    # Linux: systemctl
    if command -v systemctl &>/dev/null; then
        failed_units=$(systemctl list-units --failed --no-pager 2>/dev/null | grep "loaded failed failed" | awk '{print $1}')
        if [ -n "$failed_units" ]; then
            while read -r unit; do
                log "실패한 서비스: $unit"
                ERRORS+=("실패한 서비스: $unit")
            done <<< "$failed_units"
        else
            log "모든 서비스 정상"
            RESULTS+=("systemd: 모든 서비스 정상")
        fi
    else
        log "systemctl 미설치 — 건너뜀"
        SKIPPED+=("systemd")
    fi
fi

# ── 13. 시스템 업데이트 확인 ─────────────────────────────
if [ "$OS_TYPE" = "darwin" ]; then
    section "macOS 시스템 업데이트"
    SW_LIST=$(softwareupdate -l 2>&1)
    SW_COUNT=$(echo "$SW_LIST" | grep -c '^\*' || true)
    if [ "$SW_COUNT" -gt 0 ]; then
        log "시스템 업데이트 ${SW_COUNT}개 대기 중"
        echo "$SW_LIST" >> "$LOG_FILE"
        SW_NAMES=$(echo "$SW_LIST" | grep '^\*' | sed 's/^\* Label: //' | head -5 | paste -sd'\n' -)
        [ "$SW_COUNT" -gt 5 ] && SW_NAMES="${SW_NAMES}
..."
        if echo "$SW_LIST" | grep -iq "Security"; then
            ERRORS+=("💡 보안 업데이트 포함 ${SW_COUNT}개 대기 (즉시 설치 권장)")
        else
            ERRORS+=("macOS 업데이트 ${SW_COUNT}개 대기:
${SW_NAMES}")
        fi
    else
        log "macOS 최신 상태"
        RESULTS+=("macOS: 최신")
    fi
else
    section "보안 업데이트"
    if command -v apt &>/dev/null; then
        # 섹션 1에서 캡처한 목록 재사용 (apt upgrade 이전 스냅샷)
        _apt_list="${_APT_UPGRADABLE_LIST:-}"
        security_updates=$(echo "$_apt_list" | grep -i security | wc -l)
        if [ "$security_updates" -gt 0 ]; then
            log "보안 업데이트: ${security_updates}개 대기중"
            ERRORS+=("보안 업데이트 ${security_updates}개 필요")
        else
            log "보안 업데이트: 최신"
            RESULTS+=("보안: 최신")
        fi
        all_count=$(echo "$_apt_list" | grep -v '^-' | grep -v '^$' | wc -l | tr -d ' ')
        all_updates=$(echo "$_apt_list" | grep -v '^-' | grep -v '^$' | cut -d'/' -f1 | head -10)
        if [ "$all_count" -gt 0 ]; then
            all_names=$(echo "$all_updates" | paste -sd'\n' -)
            [ "$all_count" -gt 10 ] && all_names="${all_names}
..."
            ERRORS+=("OS 업데이트 ${all_count}개 대기:
${all_names}")
        fi
        unset _apt_list
    fi

    # Linux: 커널 업데이트 재부팅 필요 여부
    section "커널 업데이트 상태"
    if [ -f /var/run/reboot-required ]; then
        log "커널 업데이트: 재부팅 필요"
        ERRORS+=("커널 업데이트로 인한 재부팅 필요")
    else
        log "커널: 최신 상태 (재부팅 불필요)"
        RESULTS+=("커널: 최신")
    fi
fi

# ── 14. 파일시스템 무결성 확인 (주간 - 일요일) ───────────
section "파일시스템 무결성"
DOW=$(date +%w)
if [ "$DOW" -eq 0 ]; then
    if [ "$OS_TYPE" = "darwin" ]; then
        log "주간 파일시스템 무결성 점검 중..."
        DISK_VERIFY_OUT=$(diskutil verifyVolume / 2>&1)
        DISK_VERIFY_EXIT=$?
        echo "$DISK_VERIFY_OUT" >> "$LOG_FILE"
        if [ "$DISK_VERIFY_EXIT" -eq 0 ]; then
            log "파일시스템 상태: 정상"
            RESULTS+=("파일시스템: 정상")
        else
            log "파일시스템 오류 발견! 복구가 필요할 수 있습니다."
            DISK_ERR_SUMMARY=$(echo "$DISK_VERIFY_OUT" | grep -iE "error|fail|exit code|problem" | head -3 | tr '\n' ' ')
            [ -z "$DISK_ERR_SUMMARY" ] && DISK_ERR_SUMMARY=$(echo "$DISK_VERIFY_OUT" | tail -3 | tr '\n' ' ')
            ERRORS+=("파일시스템 점검 오류: ${DISK_ERR_SUMMARY}→ 재시동 필요")
        fi
    else
        # OCI/Ubuntu 환경은 sudo NOPASSWD 가 셋업되어 있다는 전제.
        # tune2fs 는 root 만 실행 가능하므로 SUDO 가드 안에서 sudo 사용.
        if command -v tune2fs &>/dev/null && [ "$SUDO_AVAILABLE" = true ]; then
            ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
            if [ -n "$ROOT_DEV" ]; then
                if sudo tune2fs -C 1 "$ROOT_DEV" 2>>"$LOG_FILE"; then
                    log "주간 fsck 스케줄됨: $ROOT_DEV (다음 재부팅 시 실행)"
                else
                    log "tune2fs 실패 (ext4 외 파일시스템이거나 권한 문제) — 건너뜀"
                    SKIPPED+=("fsck (tune2fs 실패)")
                fi
            else
                log "루트 디바이스 감지 실패 — fsck 건너뜀"
                SKIPPED+=("fsck")
            fi
        else
            log "fsck 사용 불가 (tune2fs 미설치 또는 sudo 없음) — 건너뜀"
            SKIPPED+=("fsck")
        fi
    fi
else
    log "파일시스템 점검: 다음 일요일에 실행 예정"
fi

# ── 15. Orphaned 프로세스 확인 ────────────────────────────
section "Orphaned 프로세스"
zombie_count=$(ps aux 2>/dev/null | grep -c " <defunct>" || echo 0)
if [ "$zombie_count" -gt 1 ]; then
    log "Orphaned 프로세스: ${zombie_count}개 감지"
    RESULTS+=("Orphaned 프로세스 ${zombie_count}개 감지됨")
else
    log "Orphaned 프로세스: 없음"
    RESULTS+=("Orphaned 프로세스: 없음")
fi

# ── 16. 로그 정리 ────────────────────────────────────────
section "로그 정리"
find "$LOG_STAGING_DIR" -name "maintenance_*_*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null

if [ -n "${CLEANUP_LOG_DIRS:-}" ]; then
    for dir in $CLEANUP_LOG_DIRS; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
            log "로그 디렉토리 정리: $dir"
        fi
    done
fi

if [ "$OS_TYPE" = "darwin" ]; then
    before_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
    find "$HOME/Library/Logs" -type f \( -name "*.log" -o -name "*.ips" -o -name "*.gz" -o -name "*.bz2" \) -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
    find "$HOME/Library/Logs/DiagnosticReports" -type f -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
    after_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
    freed=$((before_size - after_size))
    log "~/Library/Logs 정리: ${before_size}MB → ${after_size}MB (${freed}MB 확보)"
    if [ "$SUDO_AVAILABLE" = true ]; then
        sudo find "/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +"$LOG_RETENTION_DAYS" -delete >/dev/null 2>&1 \
            && log "/Library/Logs 정리 완료" || log "/Library/Logs 정리 실패 (sudo 에러)"
    else
        find "/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +"$LOG_RETENTION_DAYS" -delete >/dev/null 2>&1 \
            || log "/Library/Logs 정리 권한 부족 (sudo 설정 필요)"
    fi
    [ "$freed" -gt 0 ] && UPDATED+=("로그 정리 ${freed}MB 확보") || RESULTS+=("로그: 정리 완료")
else
    if [ "$SUDO_AVAILABLE" = true ]; then
        sudo find "/var/log" -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null \
            && log "/var/log 정리 완료" || log "/var/log 정리 실패 (sudo 에러)"
    else
        find "/var/log" -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null \
            || log "/var/log 정리 권한 부족 (sudo 설정 필요)"
    fi
    # journald vacuum (systemd 로그)
    if command -v journalctl &>/dev/null; then
        j_before=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+ ?\w+(?= in)' | head -1 || echo "?")
        if [ "$SUDO_AVAILABLE" = true ]; then
            sudo journalctl --vacuum-time="${LOG_RETENTION_DAYS}d" 2>>"$LOG_FILE" \
                && log "journald vacuum 완료 (기존 사용량: ${j_before})"
        else
            journalctl --user --vacuum-time="${LOG_RETENTION_DAYS}d" 2>>"$LOG_FILE" \
                && log "journald user-session vacuum 완료 (기존 사용량: ${j_before})"
        fi
    fi
fi
log "시스템 로그 정리 완료"

# ── 17. Hermes Agent 업데이트 및 서비스 재시작 ──────────
section "Hermes Agent"
HERMES_CMD_PATH=$(command -v hermes 2>/dev/null || echo "")
HERMES_DIR="$HOME/.hermes/hermes-agent"
# stamp 파일을 $HOME/.hermes/ 바로 아래에 둠 (scripts/ 디렉토리 의존 제거 + macOS/Linux 공통)
HERMES_STAMP_DIR="$HOME/.hermes"
HERMES_STAMP="$HERMES_STAMP_DIR/.hermes-last-commit"
# 재시작할 user unit 들. 공백 구분. .env 에서 MAINTENANCE_HERMES_UNITS 로 덮어쓸 수 있음.
HERMES_UNITS_DEFAULT="hermes-gateway.service hermes-dashboard.service"
HERMES_UNITS="${MAINTENANCE_HERMES_UNITS:-$HERMES_UNITS_DEFAULT}"

if [ -n "$HERMES_CMD_PATH" ] && [ -d "$HERMES_DIR/.git" ]; then
    HERMES_BEFORE=$(git -C "$HERMES_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
    log "Hermes 현재 커밋: $HERMES_BEFORE"
    "$HERMES_CMD_PATH" update 2>>"$LOG_FILE" && {
        HERMES_AFTER=$(git -C "$HERMES_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
        if [ "$HERMES_BEFORE" != "$HERMES_AFTER" ]; then
            log "Hermes 업데이트: ${HERMES_BEFORE:0:8} → ${HERMES_AFTER:0:8}"
            UPDATED+=("Hermes Agent ${HERMES_BEFORE:0:8}→${HERMES_AFTER:0:8}")
            # stamp 디렉토리 보장 (없으면 silent fail)
            mkdir -p "$HERMES_STAMP_DIR" 2>/dev/null
            echo "$HERMES_AFTER" > "$HERMES_STAMP" 2>/dev/null \
                || log "stamp 파일 쓰기 실패: $HERMES_STAMP"

            # user unit 재시작 (Linux 전용). 단, systemd --user 세션이 살아있을 때만.
            if [ "$OS_TYPE" = "linux" ]; then
                # cron 환경에서는 XDG_RUNTIME_DIR 이 미설정 → linger 유저는 /run/user/UID 가 실제 존재.
                XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
                export XDG_RUNTIME_DIR
                if [ -d "$XDG_RUNTIME_DIR" ] && systemctl --user status >/dev/null 2>&1; then
                    restarted_units=()
                    for unit in $HERMES_UNITS; do
                        if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
                            if systemctl --user restart "$unit" 2>>"$LOG_FILE"; then
                                log "  ✓ 재시작 완료: $unit"
                                restarted_units+=("$unit")
                            else
                                log "  ✗ 재시작 실패: $unit"
                                ERRORS+=("Hermes ${unit} 재시작 실패")
                            fi
                        else
                            log "  · $unit 실행 중이 아님 — 재시작 건너뜀"
                        fi
                    done
                    if [ ${#restarted_units[@]} -gt 0 ]; then
                        RESULTS+=("Hermes 재시작: ${restarted_units[*]}")
                    fi
                else
                    log "systemd --user 세션 없음 (linger 비활성 또는 SSH) — 서비스 재시작 건너뜀"
                fi
            fi
        else
            log "Hermes 최신 상태 (${HERMES_BEFORE:0:8})"
            RESULTS+=("Hermes: ${HERMES_BEFORE:0:8} 최신")
        fi
    } || {
        log "Hermes 업데이트 실패"
        ERRORS+=("Hermes 업데이트 실패")
    }
else
    log "Hermes 미설치 — 건너뜀"
    SKIPPED+=("Hermes")
fi

# ── 18. Tailscale 업데이트 및 상태 확인 ───────────────────
section "Tailscale"
if command -v tailscale &>/dev/null; then
    TS_BEFORE=$(tailscale version 2>/dev/null | head -1 | awk '{print $1}')
    log "현재 버전: ${TS_BEFORE:-unknown}"

    # cron 환경에서 sudo 프롬프트로 멈추지 않도록 timeout 가드.
    # 패키지 매니저로 설치된 경우 tailscale update 가 자동 거부
    # ("managed by package manager") → 섹션 1 (apt/brew) 에서 이미 처리되었음을 안내.
    UPDATE_OUT=$(timeout 30 tailscale update --yes 2>&1 || true)
    echo "$UPDATE_OUT" >> "$LOG_FILE"

    TS_AFTER=$(tailscale version 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$TS_AFTER" ] && [ -n "$TS_BEFORE" ] && [ "$TS_BEFORE" != "$TS_AFTER" ]; then
        log "Tailscale 업데이트: ${TS_BEFORE} → ${TS_AFTER}"
        UPDATED+=("Tailscale ${TS_BEFORE}→${TS_AFTER}")
    elif echo "$UPDATE_OUT" | grep -qi "managed by.*package manager\|use the system package manager"; then
        log "Tailscale 은 패키지 매니저 관리 — 섹션 1 에서 처리됨"
        RESULTS+=("Tailscale: ${TS_AFTER:-$TS_BEFORE} (pkg-mgr)")
    elif echo "$UPDATE_OUT" | grep -qi "no update available\|already.*latest\|up to date\|running latest"; then
        log "Tailscale 최신 상태 (${TS_AFTER:-$TS_BEFORE})"
        RESULTS+=("Tailscale: ${TS_AFTER:-$TS_BEFORE} 최신")
    elif echo "$UPDATE_OUT" | grep -qi "permission denied\|need.*root\|sudo"; then
        log "Tailscale 업데이트 권한 부족 (sudo 필요) — 패키지 매니저에 의존"
        RESULTS+=("Tailscale: ${TS_AFTER:-$TS_BEFORE} (sudo 필요)")
    else
        log "Tailscale 업데이트 시도 완료 (${TS_AFTER:-$TS_BEFORE})"
        RESULTS+=("Tailscale: ${TS_AFTER:-$TS_BEFORE}")
    fi

    # tailscaled 데몬 / 연결 상태
    if tailscale status --json &>/dev/null 2>&1; then
        TS_JSON=$(tailscale status --json 2>/dev/null)
        TS_BACKEND=$(echo "$TS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','Unknown'))" 2>/dev/null || echo "Unknown")
        TS_PEERS=$(echo "$TS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Peer', {})))" 2>/dev/null || echo "0")
        TS_SELF_IP=$(tailscale ip -4 2>/dev/null | head -1)
        log "BackendState: ${TS_BACKEND}, Peers: ${TS_PEERS}, Self IP: ${TS_SELF_IP:-none}"
        case "$TS_BACKEND" in
            Running)
                RESULTS+=("Tailscale: 연결됨 (peers ${TS_PEERS}개)")
                ;;
            NeedsLogin)
                ERRORS+=("Tailscale: NeedsLogin — 'sudo tailscale up' 필요")
                ;;
            NoState|Stopped)
                ERRORS+=("Tailscale: ${TS_BACKEND} — 'sudo tailscale up' 필요")
                ;;
            *)
                ERRORS+=("Tailscale: ${TS_BACKEND} (비정상)")
                ;;
        esac
    else
        log "tailscaled 데몬 미실행 — 상태 확인 불가"
        ERRORS+=("Tailscale: 데몬 미실행")
    fi
else
    log "Tailscale 미설치 — 건너뜀"
    SKIPPED+=("Tailscale")
fi

# ── 19. 텔레그램 보고 ─────────────────────────────────────
log ""
log "=== 점검 완료 ==="
HOSTNAME=$(hostname)

MSG="🔧 $HOSTNAME 일일 점검 완료
📅 $(date '+%Y-%m-%d %H:%M')
━━━━━━━━━━━━━━━"

if [ ${#ERRORS[@]} -gt 10 ]; then
    { MSG+="${NL}⚠️ 오류/경고 (상위 10개):"; for i in "${ERRORS[@]:0:10}"; do MSG+="${NL}  ▪ $i"; done; MSG+="${NL}  ... 외 $((${#ERRORS[@]} - 10))개"; }
elif [ ${#ERRORS[@]} -gt 0 ]; then
    { MSG+="${NL}⚠️ 오류/경고:"; for i in "${ERRORS[@]}"; do MSG+="${NL}  ▪ $i"; done; }
fi

[ ${#UPDATED[@]} -gt 0 ] && { MSG+="${NL}✅ 업데이트됨:"; for i in "${UPDATED[@]}"; do MSG+="${NL}  ▪ $i"; done; }

if [ ${#RESULTS[@]} -gt 10 ]; then
    { MSG+="${NL}✔ 최신 상태 (상위 10개):"; for i in "${RESULTS[@]:0:10}"; do MSG+="${NL}  ▪ $i"; done; }
elif [ ${#RESULTS[@]} -gt 0 ]; then
    { MSG+="${NL}✔ 최신 상태:"; for i in "${RESULTS[@]}"; do MSG+="${NL}  ▪ $i"; done; }
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    MSG+="${NL}⏭️ 건너뜀 (미설치): ${#SKIPPED[@]}개"
fi

MSG+="${NL}━━━━━━━━━━━━━━━${NL}💾 디스크: ${DISK_USAGE}% 사용중"

SCRIPT_END_TIME=$(date +%s)
ELAPSED=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MSG+="${NL}⏱ 소요시간: ${ELAPSED}초"

send_msg "$MSG"
log "텔레그램 보고 완료"

} >> "$LOG_FILE" 2>&1
