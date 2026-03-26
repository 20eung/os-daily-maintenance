#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# daily_maintenance_ubuntu.sh
# Ubuntu/Debian 시스템 일일 점검 및 자동 업데이트 (APT 기반)
# ─────────────────────────────────────────────────────────

set -uo pipefail

# 1. 환경 설정 로드
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# ─────────────────────────────────────────────────────────
# 환경 설정 및 초기화
# ─────────────────────────────────────────────────────────
# HOME이 설정되지 않은 경우 (예: cron) MAINTENANCE_HOME 또는 현재 환경의 HOME을 사용합니다.
export HOME="${MAINTENANCE_HOME:-${HOME:-}}"
if [ -z "$HOME" ]; then
    echo "ERROR: HOME directory not found. Please set MAINTENANCE_HOME in .env" >&2
    exit 1
fi

export PATH="${MAINTENANCE_PATH:-$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}:$PATH"

# 변수 설정 (기본값 설정 포함)
MAINTENANCE_BOT_KEY="${MAINTENANCE_BOT_KEY:-}"
MAINTENANCE_CHAT_ID="${MAINTENANCE_CHAT_ID:-}"
USER_PROJECT_DIR="${USER_PROJECT_DIR:-$HOME/Project}"
LOG_STAGING_DIR="${LOG_STAGING_DIR:-$USER_PROJECT_DIR/Daily-Maintenance/logs}"
LOG_FILE="$LOG_STAGING_DIR/maintenance_ubuntu_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NL=$'\n'

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
        echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/find" >&2
    fi
fi

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
section() { echo "" >> "$LOG_FILE"; log "━━━ $1 ━━━"; }

send_msg() {
    [ -z "$MAINTENANCE_BOT_KEY" ] || [ -z "$MAINTENANCE_CHAT_ID" ] && return
    curl -s -X POST "https://api.telegram.org/bot${MAINTENANCE_BOT_KEY}/sendMessage" \
        --data-urlencode "chat_id=${MAINTENANCE_CHAT_ID}" \
        --data-urlencode "text=$1" \
        --data-urlencode "parse_mode=Markdown" > /dev/null 2>&1
}

{
log "=== Ubuntu 시스템 일일 점검 시작: $TIMESTAMP ==="

RESULTS=()
UPDATED=()
ERRORS=()
SKIPPED=()

# ── 1. OS 패키지 업데이트 (APT) ───────────────────────────
section "OS 패키지 (apt)"
if command -v apt &>/dev/null; then
    sudo apt update -qq 2>>"$LOG_FILE"
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    log "업그레이드 가능: ${UPGRADABLE}개"

    if [ "$UPGRADABLE" -gt 0 ]; then
        sudo apt upgrade -y -qq 2>>"$LOG_FILE" && {
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

# ── 2. Claude Code 업데이트 ──────────────────────────────
section "Claude Code"
if command -v claude &>/dev/null; then
    CLAUDE_BEFORE=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    claude update 2>>"$LOG_FILE" && {
        CLAUDE_AFTER=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ "$CLAUDE_BEFORE" != "$CLAUDE_AFTER" ]; then
            log "Claude Code 업데이트: $CLAUDE_BEFORE → $CLAUDE_AFTER"
            UPDATED+=("Claude Code ${CLAUDE_BEFORE}→${CLAUDE_AFTER}")
        else
            log "Claude Code 최신 상태 ($CLAUDE_AFTER)"
            RESULTS+=("Claude: $CLAUDE_AFTER 최신")
        fi
    } || RESULTS+=("Claude: $CLAUDE_BEFORE (확인불가)")
else
    log "Claude Code 미설치 — 건너뜀"
    SKIPPED+=("Claude")
fi

# ── 3. npm 전역 패키지 업데이트 ─────────────────────────
section "npm 전역 패키지"
if command -v npm &>/dev/null; then
    npm_outdated=$(npm outdated -g 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    if [ "$npm_outdated" -gt 0 ]; then
        npm update -g 2>>"$LOG_FILE" && {
            log "npm 전역 패키지 ${npm_outdated}개 업데이트 완료"
            UPDATED+=("npm 전역 ${npm_outdated}개")
        } || ERRORS+=("npm")
    else
        log "npm 전역 패키지 최신 상태"
        RESULTS+=("npm: 최신")
    fi
else
    log "npm 미설치 — 건너뜀"
    SKIPPED+=("npm")
fi

# ── 4. pip 핵심 패키지 업데이트 ──────────────────────────
section "pip 핵심 패키지"
PIP_PACKAGES=( ${PIP_TARGET_PACKAGES:-boto3 botocore requests urllib3 certifi anthropic tavily-python pycryptodome pandas websockets} )
pip_updated=0
if command -v pip3 &>/dev/null; then
    for pkg in "${PIP_PACKAGES[@]}"; do
        latest=$(pip3 index versions "$pkg" 2>/dev/null | sed -n 's/.*Available versions: \([^,]*\).*/\1/p' | head -1)
        current=$(pip3 show "$pkg" 2>/dev/null | grep Version | awk '{print $2}')
        if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            pip3 install --upgrade "$pkg" -q 2>>"$LOG_FILE" && {
                log "$pkg: $current → $latest"
                pip_updated=$((pip_updated+1))
            }
        fi
    done
    [ "$pip_updated" -gt 0 ] && UPDATED+=("pip ${pip_updated}개") || RESULTS+=("pip: 최신")
else
    log "pip3 미설치 — 건너뜀"
    SKIPPED+=("pip3")
fi

# ── 5. Docker 이미지 업데이트 ────────────────────────────
section "Docker 이미지"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    PUBLIC_IMAGES=( ${DOCKER_TARGET_IMAGES:-"nginx:alpine" "portainer/portainer-ce:latest" "portainer/agent:latest" "lipanski/docker-static-website:latest"} )
    docker_updated=0
    for img in "${PUBLIC_IMAGES[@]}"; do
        old_id=$(docker inspect --format '{{.Id}}' "$img" 2>/dev/null || echo "")
        docker pull "$img" 2>&1 > /dev/null
        new_id=$(docker inspect --format '{{.Id}}' "$img" 2>/dev/null || echo "")
        if [ -n "$old_id" ] && [ "$old_id" != "$new_id" ]; then
            log "업데이트: $img"
            docker_updated=$((docker_updated+1))
        fi
    done
    docker image prune -f -q 2>>"$LOG_FILE"
    [ "$docker_updated" -gt 0 ] && UPDATED+=("Docker 이미지 ${docker_updated}개") || RESULTS+=("Docker: 최신")
else
    log "Docker 미실행 또는 미설치 — 건너뜀"
    SKIPPED+=("Docker")
fi

# ── 6. GitHub 저장소 동기화 ─────────────────────────────
section "GitHub 저장소"
if command -v git &>/dev/null; then
    git_pulled=()
    git_pull_failed=()
    while IFS= read -r repo; do
        repo_name=$(basename "$repo")
        branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
        remote=$(git -C "$repo" remote 2>/dev/null | head -1)
        if [ -n "$remote" ]; then
            git -C "$repo" fetch "$remote" -q 2>/dev/null
            behind=$(git -C "$repo" rev-list "HEAD..${remote}/${branch}" --count 2>/dev/null || echo 0)
            ahead=$(git -C "$repo" rev-list "${remote}/${branch}..HEAD" --count 2>/dev/null || echo 0)
            if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
                if git -C "$repo" pull "$remote" "$branch" -q 2>>"$LOG_FILE"; then
                    git_pulled+=("$repo_name (↓${behind})")
                else
                    git_pull_failed+=("$repo_name")
                fi
            fi
        fi
    done < <(find "$USER_PROJECT_DIR" -maxdepth 2 -name ".git" -type d 2>/dev/null | sed 's|/.git||' | sort)
    [ ${#git_pulled[@]} -gt 0 ] && UPDATED+=("Git pull: ${#git_pulled[@]}개")
else
    log "git 미설치 — 건너뜀"
    SKIPPED+=("Git")
fi

# ── 7. 디스크 상태 확인 ─────────────────────────────────
section "디스크 상태"
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%' | tr -d ' ')
log "루트 파티션 사용률: ${DISK_USAGE}%"
[ "$DISK_USAGE" -gt 85 ] && ERRORS+=("디스크 ${DISK_USAGE}% 경고")

# ── 8. 로그 정리 (30일 이상) ───────────────────────────
section "로그 정리"
# 프로젝트 로그 및 시스템 로그 정리
find "$LOG_STAGING_DIR" -name "maintenance_ubuntu_*.log" -mtime +30 -delete 2>/dev/null

# .env에 등록된 추가 로그 디렉토리 정리
if [ -n "${CLEANUP_LOG_DIRS:-}" ]; then
    for dir in $CLEANUP_LOG_DIRS; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -name "*.log" -mtime +30 -delete 2>/dev/null
            log "로그 디렉토리 정리: $dir"
        fi
    done
fi

# 시스템 로그 (/var/log) 정리
if [ "$SUDO_AVAILABLE" = true ]; then
    sudo find "/var/log" -name "*.log" -mtime +30 -delete 2>/dev/null 2>&1 && log "/var/log 정리 완료" || log "/var/log 정리 실패 (sudo 에러)"
else
    find "/var/log" -name "*.log" -mtime +30 -delete 2>/dev/null 2>&1 || log "/var/log 정리 권한 부족 (sudo 설정 필요)"
fi
log "시스템 로그 정리 완료"

# ── 9. 텔레그램 보고 ─────────────────────────────────────
MSG="🔧 Ubuntu Server 일일 점검 완료
📅 $(date '+%Y-%m-%d %H:%M')
━━━━━━━━━━━━━━━"

[ ${#UPDATED[@]} -gt 0 ] && { MSG+="${NL}✅ 업데이트됨:"; for i in "${UPDATED[@]}"; do MSG+="${NL}  ▪ $i"; done; }
[ ${#RESULTS[@]} -gt 0 ] && { MSG+="${NL}✔ 최신 상태:"; for i in "${RESULTS[@]}"; do MSG+="${NL}  ▪ $i"; done; }
[ ${#ERRORS[@]} -gt 0 ] && { MSG+="${NL}⚠️ 오류/경고:"; for i in "${ERRORS[@]}"; do MSG+="${NL}  ▪ $i"; done; }

if [ ${#SKIPPED[@]} -gt 0 ]; then
    MSG+="${NL}⏭️ 건너뜀 (미설치):"
    for item in "${SKIPPED[@]}"; do
        MSG+="${NL}  ▪ $item"
    done
fi

MSG+="${NL}━━━━━━━━━━━━━━━${NL}💾 디스크: ${DISK_USAGE}% 사용중"

send_msg "$MSG"
log "=== 점검 완료 ==="

} >> "$LOG_FILE" 2>&1
