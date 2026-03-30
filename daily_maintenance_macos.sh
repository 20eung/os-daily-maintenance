#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# daily_maintenance_macos.sh
# macOS 시스템 일일 점검 및 자동 업데이트
# ─────────────────────────────────────────────────────────

set -uo pipefail

# ─────────────────────────────────────────────────────────
# 환경 설정 로드 (순서: .env -> .env.os -> .env.local)
# ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$0")"

# 1. 공통 설정
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

# 2. OS 전용 설정 (darwin/linux)
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
[ -f "$SCRIPT_DIR/.env.${OS_TYPE}" ] && source "$SCRIPT_DIR/.env.${OS_TYPE}"

# 3. 머신별 로컬 설정 (있을 경우 최우선)
[ -f "$SCRIPT_DIR/.env.local" ] && source "$SCRIPT_DIR/.env.local"

# ─────────────────────────────────────────────────────────
# 환경 설정 및 초기화
# ─────────────────────────────────────────────────────────
# HOME이 설정되지 않은 경우 (예: cron) MAINTENANCE_HOME 또는 현재 환경의 HOME을 사용합니다.
export HOME="${MAINTENANCE_HOME:-${HOME:-}}"
if [ -z "$HOME" ]; then
    echo "ERROR: HOME directory not found. Please set MAINTENANCE_HOME in .env" >&2
    exit 1
fi

export PATH="${MAINTENANCE_PATH:-$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin}:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# 변수 설정 (기본값 설정 포함)
MAINTENANCE_BOT_KEY="${MAINTENANCE_BOT_KEY:-}"
MAINTENANCE_CHAT_ID="${MAINTENANCE_CHAT_ID:-}"
# 프로젝트들의 상위 디렉토리 목록 (여러 개인 경우 공백으로 구분)
USER_PROJECT_DIRS="${USER_PROJECT_DIRS:-${USER_PROJECT_DIR:-$HOME/Project}}"
LOG_STAGING_DIR="${LOG_STAGING_DIR:-$HOME/Project/Daily-Maintenance/logs}"
LOG_FILE="$LOG_STAGING_DIR/maintenance_macos_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NL=$'\n'

# 시스템 모니터링 임계값 (기본값)
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-80}"
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
        echo "To allow passwordless sudo for automation on macOS, add the following to 'visudo':" >&2
        echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/find" >&2
    fi
fi

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
section() { echo "" >> "$LOG_FILE"; log "━━━ $1 ━━━"; }

# 텔레그램 전송
send_msg() {
    [ -z "$MAINTENANCE_BOT_KEY" ] || [ -z "$MAINTENANCE_CHAT_ID" ] && return
    curl -s -X POST "https://api.telegram.org/bot${MAINTENANCE_BOT_KEY}/sendMessage" \
        --data-urlencode "chat_id=${MAINTENANCE_CHAT_ID}" \
        --data-urlencode "text=$1" \
        --data-urlencode "parse_mode=Markdown" > /dev/null 2>&1
}

{
log "=== macOS 시스템 일일 점검 시작: $TIMESTAMP ==="

RESULTS=()
UPDATED=()
ERRORS=()
SKIPPED=()

# ── 1. OS 패키지 업데이트 (brew) ──────────────────────────
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
    log "Homebrew 미설치 — 패키지 업데이트 건너뜀"
    SKIPPED+=("Homebrew")
fi

# ── 1-2. Homebrew Cask (greedy) 업데이트 ──────────────────
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
    log "Homebrew 미설치 — Cask(greedy) 업데이트 건너뜀"
    SKIPPED+=("Cask")
fi

# ── 2. Claude Code 업데이트 ───────────────────────────────
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

# ── 3. bkit 플러그인 업데이트 ─────────────────────────────
section "bkit 플러그인"
if command -v claude &>/dev/null; then
    BKIT_BEFORE=$(cat "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['plugins']['bkit@bkit-marketplace'][0]['version'])" 2>/dev/null || echo "unknown")
    log "현재 버전: $BKIT_BEFORE"

    claude plugin marketplace update bkit-marketplace 2>>"$LOG_FILE"
    claude plugin update bkit@bkit-marketplace 2>>"$LOG_FILE" && {
        BKIT_AFTER=$(cat "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['plugins']['bkit@bkit-marketplace'][0]['version'])" 2>/dev/null || echo "unknown")
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
    log "Claude Code 미설치 — bkit 건너뜀"
    SKIPPED+=("bkit")
fi

# ── 4. npm 전역 패키지 업데이트 ──────────────────────────
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

# ── 5. pip 설치된 패키지 업데이트 ─────────────────────────
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

# ── 6. Docker 업데이트 ─────────────────────────────────────
# 6-1. Docker Desktop 앱 업데이트 (4.38+ 지원)
if command -v docker &>/dev/null && docker desktop update --help &>/dev/null 2>&1; then
    DOCKER_APP_VER=$(defaults read /Applications/Docker.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown")
    log "현재 Docker Desktop 앱 버전: $DOCKER_APP_VER"
    docker desktop update -q 2>>"$LOG_FILE" && log "Docker Desktop 앱 업데이트 체크 완료"
fi

# 6-2. Docker Compose 프로젝트 자동 감지 및 업데이트
section "Docker Compose 프로젝트"
docker_updated=0
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=""
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi

    if [ -n "$DOCKER_COMPOSE_CMD" ]; then
        # 모든 프로젝트 디렉토리 순회하며 docker-compose.yml 탐색
        while IFS= read -r compose_file; do
            [ -z "$compose_file" ] && continue
            project_dir=$(dirname "$compose_file")
            project_name=$(basename "$project_dir")
            log "Docker 점검: $project_name"
            (
                cd "$project_dir" || exit
                $DOCKER_COMPOSE_CMD pull 2>>"$LOG_FILE" && {
                    $DOCKER_COMPOSE_CMD up -d 2>>"$LOG_FILE" && log "$project_name 업데이트 완료" || log "$project_name 재시작 실패"
                    docker_updated=$((docker_updated+1))
                } || log "$project_name pull 실패"
            ) || log "$project_name 진입 실패"
        done < <(find $USER_PROJECT_DIRS -maxdepth 3 -name "docker-compose.yml" -type f -not -path "*/node_modules/*" -not -path "*/.*/*" 2>/dev/null | sort -u)
        
        docker image prune -f 2>>"$LOG_FILE"
        [ "$docker_updated" -gt 0 ] && UPDATED+=("Docker Compose ${docker_updated}개") || RESULTS+=("Docker: 최신")
    else
        log "Docker Compose 미설치 — 건너뜀"
        SKIPPED+=("Docker Compose")
    fi
else
    log "Docker 미실행 또는 미설치 — 건너뜀"
    SKIPPED+=("Docker")
fi

# ── 7. GitHub 저장소 동기화 (pull 자동, push 알림) ──────
section "GitHub 저장소"
if command -v git &>/dev/null; then
    git_pulled=()
    git_pull_failed=()
    git_ahead=()
    git_noremote=()
    while IFS= read -r repo; do
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
            # diverged: pull 불가, 알림만
            git_pull_failed+=("$repo_name (↓${behind} ↑${ahead} — diverged, 수동 처리 필요)")
        elif [ "$behind" -gt 0 ]; then
            # 자동 pull
            if git -C "$repo" pull "$remote" "$branch" -q 2>>"$LOG_FILE"; then
                log "pull 완료: $repo_name (${behind}커밋)"
                git_pulled+=("$repo_name (↓${behind})")
            else
                log "pull 실패: $repo_name"
                git_pull_failed+=("$repo_name (pull 실패)")
            fi
        elif [ "$ahead" -gt 0 ]; then
            git_ahead+=("$repo_name (↑${ahead} 커밋 미푸시)")
        else
            log "최신: $repo_name"
        fi
    done < <(find $USER_PROJECT_DIRS -maxdepth 3 -name ".git" -type d -not -path "*/node_modules/*" 2>/dev/null | sed 's|/.git||' | sort -u)

    [ ${#git_pulled[@]} -gt 0 ]      && UPDATED+=("Git pull: ${#git_pulled[@]}개 (${git_pulled[*]})")
    [ ${#git_pull_failed[@]} -gt 0 ] && { for r in "${git_pull_failed[@]}"; do ERRORS+=("Git: $r"); done; }
    [ ${#git_ahead[@]} -gt 0 ]       && { for r in "${git_ahead[@]}"; do ERRORS+=("Git push 필요: $r"); done; }
    [ ${#git_noremote[@]} -gt 0 ]    && log "remote 없음: ${git_noremote[*]}"
    [ ${#git_pulled[@]} -eq 0 ] && [ ${#git_pull_failed[@]} -eq 0 ] && [ ${#git_ahead[@]} -eq 0 ] && RESULTS+=("GitHub: 모두 최신")
else
    log "git 미설치 — 건너뜀"
    SKIPPED+=("Git")
fi

# ── 8. conda 업데이트 ─────────────────────────────────────
section "conda"

# conda 환경 로드 (shell function 활성화)
if [ -f "${MAINTENANCE_CONDA_SH:-/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh}" ]; then
    source "${MAINTENANCE_CONDA_SH:-/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh}" 2>/dev/null
fi

if command -v conda &>/dev/null; then
    CONDA_BEFORE=$(conda --version 2>&1 | awk '{print $2}')
    log "현재 conda 버전: $CONDA_BEFORE"
    conda update conda -y -q 2>>"$LOG_FILE" && {
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
    conda clean --all -y -q 2>>"$LOG_FILE"
else
    log "conda 미설치 — 건너뜀"
    SKIPPED+=("conda")
fi

# ── 9. 시스템 상태 확인 ───────────────────────────────────
section "시스템 상태"
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%' | tr -d ' ')
log "루트 파티션 사용률: ${DISK_USAGE}%"
[ "$DISK_USAGE" -gt "$DISK_USAGE_THRESHOLD" ] && ERRORS+=("디스크 ${DISK_USAGE}% 경고")

# 메모리 사용률 (macOS: vm_stat 기반)
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

# ── 9-1. 시스템 온도 확인 (macOS 전용) ───────────────────
# CPU 온도 (osx-cpu-temp 설치 시)
if command -v osx-cpu-temp &>/dev/null; then
    CPU_TEMP=$(osx-cpu-temp | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "$CPU_TEMP" ]; then
        log "CPU 온도: ${CPU_TEMP}°C"
        if (( $(echo "$CPU_TEMP > $CPU_TEMP_THRESHOLD" | bc -l) )); then
            ERRORS+=("CPU 온도 ${CPU_TEMP}°C 경고")
        fi
    fi
fi

# 디스크 온도 (smartctl 설치 시)
if command -v smartctl &>/dev/null; then
    DISK_TEMP=$(sudo smartctl -a /dev/disk0 2>/dev/null | awk '/Temperature:|Air_Flow_Temperature|Temperature_Celsius/{print $NF}' | head -1)
    if [ -n "$DISK_TEMP" ]; then
        log "디스크 온도: ${DISK_TEMP}°C"
        if [ "$DISK_TEMP" -gt "$DISK_TEMP_THRESHOLD" ]; then
            ERRORS+=("디스크 온도 ${DISK_TEMP}°C 경고")
        fi
    fi
fi

# ── 9-2. 서비스 상태 확인 (launchctl) ────────────────────
section "서비스 상태"
# 비정상 종료된 서비스 (Exit Code가 0이 아닌 것들)
failed_services=$(launchctl list | awk '$2 != 0 && $2 != "-" {print $3}' | grep -v "com.apple.coreservices.uiagent" || true)
if [ -n "$failed_services" ]; then
    while read -r service; do
        log "비정상 종료 서비스 감지: $service"
        ERRORS+=("실패 서비스: $service")
    done <<< "$failed_services"
else
    log "모든 서비스 정상"
    RESULTS+=("서비스: 정상")
fi

# ── 10. 네트워크 연결 상태 확인 ──────────────────────────
section "네트워크 연결"
if ping -c 1 8.8.8.8 &>/dev/null 2>&1; then
    log "네트워크 연결: 정상"
    RESULTS+=("네트워크: 정상")
else
    log "네트워크 연결 실패"
    ERRORS+=("네트워크 연결 실패")
fi

# ── 11. macOS 시스템 업데이트 확인 (보고만) ───────────────
section "macOS 시스템 업데이트"
SW_LIST=$(softwareupdate -l 2>&1)
SW_COUNT=$(echo "$SW_LIST" | grep -c '^\*' || true)
if [ "$SW_COUNT" -gt 0 ]; then
    log "시스템 업데이트 ${SW_COUNT}개 대기 중"
    echo "$SW_LIST" >> "$LOG_FILE"
    
    # 보안 업데이트 여부 확인
    if echo "$SW_LIST" | grep -iq "Security"; then
        ERRORS+=("💡 보안 업데이트 포함 ${SW_COUNT}개 대기 (즉시 설치 권장)")
    else
        ERRORS+=("macOS 업데이트 ${SW_COUNT}개 대기 (수동 설치 필요)")
    fi
else
    log "macOS 최신 상태"
    RESULTS+=("macOS: 최신")
fi

# ── 12. Orphaned 프로세스 확인 ────────────────────────────
section "Orphaned 프로세스"
zombie_count=$(ps aux 2>/dev/null | grep -c " <defunct>" || echo 0)
if [ "$zombie_count" -gt 1 ]; then  # grep 자신 제외
    log "Orphaned 프로세스: ${zombie_count}개 감지"
    RESULTS+=("Orphaned 프로세스 ${zombie_count}개 감지됨")
else
    log "Orphaned 프로세스: 없음"
    RESULTS+=("Orphaned 프로세스: 없음")
fi

# ── 12-1. 파일시스템 무결성 확인 (주간 체크 - 일요일) ───────
section "파일시스템 무결성"
DOW=$(date +%w)  # 0=일요일
if [ "$DOW" -eq 0 ]; then
    log "주간 파일시스템 무결성 점검 중..."
    if diskutil verifyVolume / >> "$LOG_FILE" 2>&1; then
        log "파일시스템 상태: 정상"
        RESULTS+=("파일시스템: 정상")
    else
        log "파일시스템 오류 발견! 복구가 필요할 수 있습니다."
        ERRORS+=("파일시스템 점검 오류 발견")
    fi
else
    log "파일시스템 점검: 다음 일요일에 실행 예정"
fi

# ── 13. 로그 파일 정리 (30일 이상 된 것 삭제) ────────────
section "로그 정리"

# 프로젝트 로그 및 시스템 로그 정리
find "$LOG_STAGING_DIR" -name "maintenance_macos_*.log" -mtime +30 -delete 2>/dev/null

# .env에 등록된 추가 로그 디렉토리 정리
if [ -n "${CLEANUP_LOG_DIRS:-}" ]; then
    for dir in $CLEANUP_LOG_DIRS; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -name "*.log" -mtime +30 -delete 2>/dev/null
            log "로그 디렉토리 정리: $dir"
        fi
    done
fi

# macOS 사용자 앱 로그 (~/Library/Logs)
before_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
find "$HOME/Library/Logs" -type f \( -name "*.log" -o -name "*.ips" -o -name "*.gz" -o -name "*.bz2" \) -mtime +30 -delete 2>/dev/null
find "$HOME/Library/Logs/DiagnosticReports" -type f -mtime +30 -delete 2>/dev/null
after_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
freed=$((before_size - after_size))
log "~/Library/Logs 정리: ${before_size}MB → ${after_size}MB (${freed}MB 확보)"

# macOS 시스템 앱 로그 (/Library/Logs)
if [ "$SUDO_AVAILABLE" = true ]; then
    sudo find "/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 -delete 2>/dev/null 2>&1 && log "/Library/Logs 정리 완료" || log "/Library/Logs 정리 실패 (sudo 에러)"
else
    find "/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 -delete 2>/dev/null 2>&1 || log "/Library/Logs 정리 권한 부족 (sudo 설정 필요)"
fi

log "전체 로그 정리 완료"
[ "$freed" -gt 0 ] && UPDATED+=("로그 정리 ${freed}MB 확보") || RESULTS+=("로그: 정리 완료")

# ── 14. 텔레그램 보고 ─────────────────────────────────────
log ""
log "=== 점검 완료 ==="
HOSTNAME=$(hostname)

MSG="🔧 $HOSTNAME 일일 점검 완료
📅 $(date '+%Y-%m-%d %H:%M')
━━━━━━━━━━━━━━━"

[ ${#UPDATED[@]} -gt 0 ] && { MSG+="${NL}✅ 업데이트됨:"; for i in "${UPDATED[@]}"; do MSG+="${NL}  ▪ $i"; done; }
[ ${#RESULTS[@]} -gt 0 ] && { MSG+="${NL}✔ 최신 상태:"; for i in "${RESULTS[@]}"; do MSG+="${NL}  ▪ $i"; done; }
[ ${#ERRORS[@]} -gt 0 ]  && { MSG+="${NL}⚠️ 오류/경고:"; for i in "${ERRORS[@]}"; do MSG+="${NL}  ▪ $i"; done; }

if [ ${#SKIPPED[@]} -gt 0 ]; then
    MSG+="${NL}⏭️ 건너뜀 (미설치):"
    for item in "${SKIPPED[@]}"; do
        MSG+="${NL}  ▪ $item"
    done
fi

MSG+="${NL}━━━━━━━━━━━━━━━${NL}💾 디스크: ${DISK_USAGE}% 사용중"

send_msg "$MSG"
log "텔레그램 보고 완료"

} >> "$LOG_FILE" 2>&1
