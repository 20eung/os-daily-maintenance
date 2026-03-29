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
USER_PROJECT_DIR="${USER_PROJECT_DIR:-/data}"
LOG_STAGING_DIR="${LOG_STAGING_DIR:-$HOME/os-daily-maintenance/logs}"
LOG_FILE="$LOG_STAGING_DIR/maintenance_ubuntu_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
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

# ── 4. pip 설치된 패키지 자동 업데이트 ──────────────────────────
section "pip 설치된 패키지"
pip_updated=0
if command -v pip3 &>/dev/null; then
    while IFS= read -r line; do
        pkg=$(echo "$line" | awk '{print $1}')
        if [ -n "$pkg" ]; then
            pip3 install --upgrade "$pkg" -q 2>>"$LOG_FILE" && {
                log "$pkg 업그레이드 완료"
                pip_updated=$((pip_updated+1))
            } || log "$pkg 업그레이드 실패"
        fi
    done < <(pip3 list --outdated 2>/dev/null | tail -n +3)
    [ "$pip_updated" -gt 0 ] && UPDATED+=("pip ${pip_updated}개") || RESULTS+=("pip: 최신")
else
    log "pip3 미설치 — 건너뜀"
    SKIPPED+=("pip3")
fi

# ── 5. Docker Compose 프로젝트 자동 감지 및 업데이트 ────────────────────────────
section "Docker Compose 프로젝트"
docker_updated=0
if command -v docker-compose &>/dev/null && command -v docker &>/dev/null; then
    while IFS= read -r compose_file; do
        project_dir=$(dirname "$compose_file")
        project_name=$(basename "$project_dir")
        log "점검: $project_name"
        (
            cd "$project_dir" || exit
            docker-compose pull 2>>"$LOG_FILE" && {
                docker-compose up -d 2>>"$LOG_FILE" && log "$project_name 업데이트 완료" || log "$project_name 재시작 실패"
                docker_updated=$((docker_updated+1))
            } || log "$project_name pull 실패"
        ) || log "$project_name 진입 실패"
    done < <(find "$USER_PROJECT_DIR" -maxdepth 2 -name "docker-compose.yml" -type f 2>/dev/null | sort)
    docker image prune -f -q 2>>"$LOG_FILE"
    [ "$docker_updated" -gt 0 ] && UPDATED+=("Docker Compose ${docker_updated}개") || RESULTS+=("Docker: 최신")
else
    log "Docker 또는 Docker Compose 미실행/미설치 — 건너뜈"
    SKIPPED+=("Docker Compose")
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

# ── 7. 시스템 상태 확인 (메모리, 디스크, CPU 온도) ─────────────────────────────────
section "시스템 상태"
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%' | tr -d ' ')
log "루트 파티션 사용률: ${DISK_USAGE}%"
[ "$DISK_USAGE" -gt "$DISK_USAGE_THRESHOLD" ] && ERRORS+=("디스크 ${DISK_USAGE}% 경고")

# 메모리 사용률
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", ($3/$2)*100)}')
log "메모리 사용률: ${MEM_USAGE}%"
[ "$MEM_USAGE" -gt "$MEMORY_USAGE_THRESHOLD" ] && ERRORS+=("메모리 ${MEM_USAGE}% 경고")

# CPU 온도 (lm-sensors 설치 시)
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

# 디스크 온도 (smartctl 설치 시)
if command -v smartctl &>/dev/null; then
    DISK_TEMP=$(smartctl -a /dev/sda 2>/dev/null | grep "Temperature_Celsius" | awk '{print $10}' | head -1)
    if [ -n "$DISK_TEMP" ]; then
        log "디스크 온도: ${DISK_TEMP}°C"
        if [ "$DISK_TEMP" -gt "$DISK_TEMP_THRESHOLD" ]; then
            ERRORS+=("디스크 온도 ${DISK_TEMP}°C 경고")
        fi
    fi
fi

# ── 8. systemd 서비스 상태 확인 ─────────────────────────────────
section "systemd 서비스 상태"
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

# ── 9. 네트워크 연결 상태 확인 ─────────────────────────────────
section "네트워크 연결"
if ping -c 1 8.8.8.8 &>/dev/null 2>&1; then
    log "네트워크 연결: 정상"
    RESULTS+=("네트워크: 정상")
else
    log "네트워크 연결 실패"
    ERRORS+=("네트워크 연결 실패")
fi

# ── 10. 커널 업데이트 상태 확인 ─────────────────────────────────
section "커널 업데이트 상태"
if [ -f /var/run/reboot-required ]; then
    log "커널 업데이트: 재부팅 필요"
    ERRORS+=("커널 업데이트로 인한 재부팅 필요")
else
    log "커널: 최신 상태 (재부팅 불필요)"
    RESULTS+=("커널: 최신")
fi

# ── 11. 보안 업데이트 확인 ─────────────────────────────────
section "보안 업데이트"
if command -v apt &>/dev/null; then
    security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
    if [ "$security_updates" -gt 0 ]; then
        log "보안 업데이트: ${security_updates}개 대기중"
        ERRORS+=("보안 업데이트 ${security_updates}개 필요")
    else
        log "보안 업데이트: 최신"
        RESULTS+=("보안: 최신")
    fi
fi

# ── 12. 파일시스템 무결성 확인 (주간 체크) ─────────────────────────────────
section "파일시스템 무결성"
DOW=$(date +%w)  # 0=일요일, 1=월요일, ... 6=토요일
if [ "$DOW" -eq 0 ]; then  # 일요일에만 실행
    if command -v fsck &>/dev/null && [ "$SUDO_AVAILABLE" = true ]; then
        log "주간 fsck 체크 스케줄됨 (다음 재부팅 시 실행)"
        sudo touch /forcefsck 2>/dev/null || log "fsck 플래그 설정 실패"
    fi
else
    log "fsck 체크: 다음 일요일에 실행 예정"
fi

# ── 13. Orphaned 프로세스 정리 ─────────────────────────────────
section "Orphaned 프로세스"
zombie_count=$(ps aux | grep -c " <defunct>")
if [ "$zombie_count" -gt 1 ]; then  # grep 자신 제외
    log "Orphaned 프로세스: ${zombie_count}개 감지"
    RESULTS+=("Orphaned 프로세스 ${zombie_count}개 감지됨")
else
    log "Orphaned 프로세스: 없음"
    RESULTS+=("Orphaned 프로세스: 없음")
fi

# ── 14. 로그 정리 (30일 이상) ───────────────────────────
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

# ── 15. 텔레그램 보고 ─────────────────────────────────────
HOSTNAME=$(hostname)
MSG="🔧 $HOSTNAME 일일 점검 완료
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
