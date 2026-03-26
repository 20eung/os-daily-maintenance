#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# daily_maintenance.sh
# 매일 09:00 macOS 전체 업데이트 점검 및 자동 업그레이드
# ─────────────────────────────────────────────────────────

set -uo pipefail

export HOME="/Users/a04258"
export PATH="/Users/a04258/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

BOT_KEY="8585859981:AAEOTnOnk6qmBTOPrwYyVNaR-IY3Zwx6X7c"
CHAT_ID="204089935"
LOG_DIR="$HOME/.cokacdir/workspace/admin/logs"
LOG_FILE="$LOG_DIR/maintenance_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NL=$'\n'

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
section() { echo "" >> "$LOG_FILE"; log "━━━ $1 ━━━"; }

# 텔레그램 전송
send_msg() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_KEY}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=$1" \
        --data-urlencode "parse_mode=Markdown" > /dev/null 2>&1
}

{
log "=== 시스템 일일 점검 시작: $TIMESTAMP ==="

RESULTS=()
UPDATED=()
ERRORS=()

# ── 1. OS 패키지 업데이트 ──────────────────────────────────
section "OS 패키지 (brew)"
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

# ── 1-2. Homebrew Cask (greedy) 업데이트 ──────────────────
section "Cask (greedy)"
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

# ── 2. Claude Code 업데이트 ───────────────────────────────
section "Claude Code"
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

# ── 3. bkit 플러그인 업데이트 ─────────────────────────────
section "bkit 플러그인"
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

# ── 4. npm 전역 패키지 업데이트 ──────────────────────────
section "npm 전역 패키지"
npm outdated -g 2>/dev/null
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

# ── 5. pip 핵심 패키지 업데이트 ───────────────────────────
section "pip 핵심 패키지"
# 시스템 패키지 제외, 주요 사용 패키지만 업데이트
PIP_PACKAGES=(boto3 botocore requests urllib3 certifi anthropic tavily-python pycryptodome pandas websockets)
pip_updated=0
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
if [ "$pip_updated" -gt 0 ]; then
    UPDATED+=("pip ${pip_updated}개")
else
    log "pip 핵심 패키지 최신 상태"
    RESULTS+=("pip: 최신")
fi

# ── 6. Docker 업데이트 ─────────────────────────────────────
# 6-1. Docker Desktop 앱 업데이트 (4.38+ 지원)
if command -v docker &>/dev/null && docker desktop update --help &>/dev/null; then
    DOCKER_APP_VER=$(defaults read /Applications/Docker.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown")
    log "현재 Docker Desktop 앱 버전: $DOCKER_APP_VER"
    docker desktop update -q 2>>"$LOG_FILE" && log "Docker Desktop 앱 업데이트 체크 완료"
fi

section "Docker 이미지"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    # public 이미지만 pull (custom 빌드 이미지 제외)
    PUBLIC_IMAGES=(
        "nginx:alpine"
        "portainer/portainer-ce:latest"
        "portainer/agent:latest"
        "lipanski/docker-static-website:latest"
    )
    docker_updated=0
    for img in "${PUBLIC_IMAGES[@]}"; do
        old_id=$(docker inspect --format '{{.Id}}' "$img" 2>/dev/null || echo "")
        pull_out=$(docker pull "$img" 2>&1)
        new_id=$(docker inspect --format '{{.Id}}' "$img" 2>/dev/null || echo "")
        if [ -n "$old_id" ] && [ "$old_id" != "$new_id" ]; then
            log "업데이트: $img"
            docker_updated=$((docker_updated+1))
        else
            log "최신: $img"
        fi
    done
    docker image prune -f -q 2>>"$LOG_FILE"
    if [ "$docker_updated" -gt 0 ]; then
        UPDATED+=("Docker 이미지 ${docker_updated}개")
    else
        RESULTS+=("Docker: 최신")
    fi
else
    log "Docker 미실행 — 건너뜀"
    RESULTS+=("Docker: 미실행")
fi

# ── 6-2. GitHub 저장소 동기화 (pull 자동, push 알림) ──────
section "GitHub 저장소"
PROJECT_DIR="$HOME/Project"
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
done < <(find "$PROJECT_DIR" -maxdepth 2 -name ".git" -type d 2>/dev/null | sed 's|/.git||' | sort)

[ ${#git_pulled[@]} -gt 0 ]      && UPDATED+=("Git pull: ${#git_pulled[@]}개 (${git_pulled[*]})")
[ ${#git_pull_failed[@]} -gt 0 ] && { for r in "${git_pull_failed[@]}"; do ERRORS+=("Git: $r"); done; }
[ ${#git_ahead[@]} -gt 0 ]       && { for r in "${git_ahead[@]}"; do ERRORS+=("Git push 필요: $r"); done; }
[ ${#git_noremote[@]} -gt 0 ]    && log "remote 없음: ${git_noremote[*]}"
[ ${#git_pulled[@]} -eq 0 ] && [ ${#git_pull_failed[@]} -eq 0 ] && [ ${#git_ahead[@]} -eq 0 ] && RESULTS+=("GitHub: 모두 최신")

# ── 8. conda 업데이트 ─────────────────────────────────────
section "conda"

# conda 환경 로드 (shell function 활성화)
if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
    source "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" 2>/dev/null
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
fi

# ── 9. 디스크 상태 확인 ───────────────────────────────────
section "디스크 상태"
df -h / 2>/dev/null
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%' | tr -d ' ')
log "루트 파티션 사용률: ${DISK_USAGE}%"
[ "$DISK_USAGE" -gt 80 ] && ERRORS+=("디스크 ${DISK_USAGE}% 경고")

# ── 10. macOS 시스템 업데이트 확인 (보고만) ───────────────
section "macOS 시스템 업데이트"
SW_LIST=$(softwareupdate -l 2>&1)
SW_COUNT=$(echo "$SW_LIST" | grep -c '^\*' || true)
if [ "$SW_COUNT" -gt 0 ]; then
    log "시스템 업데이트 ${SW_COUNT}개 대기 중"
    echo "$SW_LIST" >> "$LOG_FILE"
    ERRORS+=("macOS 업데이트 ${SW_COUNT}개 대기 (수동 설치 필요)")
else
    log "macOS 최신 상태"
    RESULTS+=("macOS: 최신")
fi

# ── 11. 로그 파일 정리 (30일 이상 된 것 삭제) ────────────
section "로그 정리"

# 프로젝트 로그
find "$LOG_DIR" -name "maintenance_*.log" -mtime +30 -delete 2>/dev/null
find "$HOME/.cokacdir/workspace/trading/logs" -name "cto_trading_*.log" -mtime +30 -delete 2>/dev/null
find "$HOME/.cokacdir/workspace/us-ko-chart" -name "*.log" -mtime +30 -delete 2>/dev/null

# macOS 사용자 앱 로그 (~/Library/Logs)
before_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
find "$HOME/Library/Logs" -type f \( -name "*.log" -o -name "*.ips" -o -name "*.gz" -o -name "*.bz2" \) -mtime +30 -delete 2>/dev/null
find "$HOME/Library/Logs/DiagnosticReports" -type f -mtime +30 -delete 2>/dev/null
after_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
freed=$((before_size - after_size))
log "~/Library/Logs 정리: ${before_size}MB → ${after_size}MB (${freed}MB 확보)"

# macOS 시스템 앱 로그 (/Library/Logs)
find "/Library/Logs" -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 -delete 2>/dev/null
log "/Library/Logs 30일 이상 로그 정리 완료"

log "전체 로그 정리 완료"
[ "$freed" -gt 0 ] && UPDATED+=("로그 정리 ${freed}MB 확보") || RESULTS+=("로그: 정리 완료")

# ── 12. 텔레그램 보고 ─────────────────────────────────────
log ""
log "=== 점검 완료 ==="

MSG="🔧 MacBook M1 Pro 일일 점검 완료
📅 $(date '+%Y-%m-%d %H:%M')
━━━━━━━━━━━━━━━"

if [ ${#UPDATED[@]} -gt 0 ]; then
    MSG+="${NL}✅ 업데이트됨:"
    for item in "${UPDATED[@]}"; do
        MSG+="${NL}  ▪ $item"
    done
fi

if [ ${#RESULTS[@]} -gt 0 ]; then
    MSG+="${NL}✔ 최신 상태:"
    for item in "${RESULTS[@]}"; do
        MSG+="${NL}  ▪ $item"
    done
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    MSG+="${NL}⚠️ 오류/경고:"
    for item in "${ERRORS[@]}"; do
        MSG+="${NL}  ▪ $item"
    done
fi

MSG+="${NL}━━━━━━━━━━━━━━━${NL}💾 디스크: ${DISK_USAGE}% 사용중"

send_msg "$MSG"
log "텔레그램 보고 완료"

} >> "$LOG_FILE" 2>&1
