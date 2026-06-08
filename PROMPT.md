# Daily Maintenance System Prompt

## 목표
macOS 및 Ubuntu 환경에서 개발 도구와 시스템을 매일 자동으로 점검하고 최신 상태로 유지하는 견고한 Bash 쉘 스크립트를 작성합니다.
OS 분기는 스크립트 내부에서 `$(uname -s)` 결과를 기준으로 처리하며, **단일 파일(`daily_maintenance.sh`)로 Linux/macOS를 모두 지원**합니다.

## 핵심 요구사항

### 1. 환경 설정 및 초기화
- `set -uo pipefail`로 오류 발생 시 중단 및 변수 엄격 체크.
- 환경 설정 로드 순서를 준수합니다: `.env` (공통) -> `.env.darwin`/`.env.linux` (OS 전용) -> `.env.local` (로컬).
- `HOME`과 `PATH`는 설정 파일에 정의된 `MAINTENANCE_HOME`, `MAINTENANCE_PATH`를 우선 반영하며, 하드코딩된 개인 경로는 절대 사용하지 않습니다.
- 모든 외부 도구(brew, docker 등) 실행 전 `command -v`를 통해 설치 여부를 확인하고, 미설치 시 건너뜀 목록에 추가합니다.
- `sudo` 권한이 필요한 작업 전 가용성을 체크하고, 권한 부족 시 `visudo` 설정 가이드를 콘솔에 출력합니다.
- `nvm` 및 `MAINTENANCE_CONDA_SH`를 소싱하여 관련 명령어가 사용 가능한 상태로 환경을 구성.

### 2. 패키지 및 AI 도구 관리
- **macOS (Homebrew)**: `update`, `upgrade`, `upgrade --greedy` 수행 후 `autoremove`, `cleanup` 정리.
- **Ubuntu (APT)**: `update`, `upgrade -y` 수행 후 `autoremove`, `autoclean` 정리.
- **Claude Code**: `claude update`를 수행하고, 업데이트 전후 버전을 비교하여 보고용 텍스트 생성.
- **bkit 플러그인**: `marketplace update`와 `plugin update bkit@bkit-marketplace`를 연달아 수행하고 버전 변동 체크.

### 3. 개발 언어 및 라이브러리
- **npm**: `npm update -g` 수행.
- **pip3**: `.env` 의 `PIP_TARGET_PACKAGES` 가 있으면 그것만 화이트리스트로, 없으면 `pip3 list --outdated` 결과를 사용. PEP 668(Homebrew/Ubuntu 23+) 환경에서는 `pip install --user --upgrade` 로 자동 fallback. `--break-system-packages` 플래그는 시스템 python 보호를 위해 자동 감지 후에만 사용.

### 4. Docker 및 이미지 관리
- **Watchtower 감지**: `docker ps`에서 Watchtower 컨테이너가 실행 중이면 자동으로 SKIPPED 처리 (Watchtower가 이미지 업데이트 담당).
- **Watchtower 없을 때**: **주 1회(일요일)** 에만 실행. 실행 중인 컨테이너별로 `docker pull`을 수행하고, 이미지 변경 시 compose 라벨(`com.docker.compose.project.working_dir`)을 자동 감지하여 `docker compose up -d` 로 재생성. compose 외 컨테이너는 경고 메시지로 수동 처리 안내.
- **정리**: `docker image prune -f` 수행.

### 5. Git 저장소 동기화 (핵심 로직)
- macOS / Linux 모두 **`~/Project`** (대문자 P) 를 기본 프로젝트 루트로 사용. `.env` 의 `USER_PROJECT_DIRS` 가 공백 구분 다중 경로일 때, 실제로 존재하는 디렉토리만 통과시켜 silent false-positive 방지.
- `$USER_PROJECT_DIRS` 하위의 모든 `.git` 디렉토리를 깊이 3까지 동적으로 탐색합니다. (`node_modules` 는 `-prune` 으로 정확히 제외)
- 각 저장소에서 `fetch` 후 `ahead`/`behind` 카운트를 계산.
- `behind`만 존재할 경우 자동 `pull` 수행. `ahead`가 있거나 `diverged` 상태면 경고 목록에 추가하여 수동 처리를 유도.

### 6. 시스템 관리 및 보고
- **Conda**: `update conda -y` 및 `clean --all` 수행. (macOS 전용)
- **시스템**: `softwareupdate -l`(macOS) 또는 `apt list --upgradable`(Ubuntu) 정보를 확인.
- **디스크**: 사용량이 80%를 초과할 경우 경고 알림.
- **로그 정리**: `/Library/Logs`, `~/Library/Logs`, 프로젝트 로그 디렉토리에서 `$LOG_RETENTION_DAYS`가 지난 로그를 삭제하고 확보 결과 보고.
- **텔레그램 알림**: `curl`을 사용하여 업데이트된 항목(✅), 최신인 상태(✔), 오류/경고 항목(⚠️)을 포맷팅하여 전송.

### 7. Hermes Agent 연동 (Linux 전용, 섹션 16)
- `command -v hermes`로 hermes 바이너리 경로를 **동적** 탐색 (경로 하드코딩 금지).
- `hermes` 미설치 시 `SKIPPED` 처리.
- `~/.hermes/hermes-agent/` 디렉토리의 git 커밋 해시를 `~/.hermes/.hermes-last-commit` 파일과 비교하여 변경 감지.
- 업데이트 감지 시 `.env` 의 `MAINTENANCE_HERMES_UNITS` (공백 구분) 에 등록된 `systemctl --user` 서비스들을 순차 재시작. 기본값은 `hermes-gateway.service hermes-dashboard.service` (OCI 에서는 gateway 가, 데스크탑에서는 dashboard 가 실제 운영 중인 unit).
- `XDG_RUNTIME_DIR` 또는 `systemctl --user status` 가 실패하면 (SSH / linger-off 환경) 재시작 단계를 SKIPPED 처리하여 false error 방지.
- `systemctl --user`가 사용 불가한 환경에서는 SKIPPED 처리.

### 8. Tailscale VPN 점검 (섹션 18, 공통)
- `command -v tailscale`로 바이너리 존재 확인. 미설치 시 `SKIPPED` 처리.
- `timeout 30 tailscale update --yes` 로 비 대화형 업데이트 시도 (cron 환경 sudo 행 방지). 패키지 매니저(apt/brew) 관리 인스톨은 자체 거부 메시지를 출력하므로 "pkg-mgr" 상태로 `RESULTS` 보고.
- `tailscale status --json` 의 `BackendState` 값에 따라 분기:
  - `Running` → peer 수 + self IP 와 함께 `RESULTS` 보고
  - `NeedsLogin` / `NoState` / `Stopped` → `sudo tailscale up` 안내를 `ERRORS` 에 추가
  - 그 외 비정상 상태 → `ERRORS` 에 추가
- `tailscaled` 데몬 미실행 시 `ERRORS` 에 추가.
- `tailscale update` 가 sudo 권한 부족으로 실패해도 시스템에 해를 주지 않으며, 섹션 1의 apt/brew 업데이트로 동일 패키지가 처리됨.

## 🚀 릴리즈 관리 규칙 (Release Rules)
1. **보안 확인**: `.env` 등 민감 파일이 `.gitignore`에 포함되었는지 확인 후 `push`합니다.
2. **About 섹션 자동 업데이트**: 릴리즈 시 `gh repo edit`을 통해 다음 정보를 강제 혹은 검토 업데이트합니다.
   - **Description**: `🍎 macOS & 🐧 Ubuntu Daily Maintenance Automation (Homebrew, APT, npm, pip, Docker, Git, etc.)`
   - **Topics**: `macos`, `ubuntu`, `automation`, `maintenance`, `bash-script`, `homebrew`, `apt`, `docker`, `github`, `telegram`
3. **태그 및 릴리즈**: `gh release create`를 사용하여 버전 관리와 릴리즈 노트를 작성합니다.

## 환경 설정
- **기본 환경**: macOS (M1/Intel) & Ubuntu Linux (OCI), bash, UTF-8 모드
- **프로젝트 루트 (macOS/Linux 통일)**: `$HOME/Project` (대문자 P). OCI VM 은 `mv ~/project ~/Project` 로 마이그레이션.
- **경로**: 사용자의 홈 디렉토리 기준 (`.env` 설정을 따름)
- **로깅**: 상세 실행 과정은 날짜별 로그 파일(`logs/maintenance_linux_*.log` 또는 `logs/maintenance_darwin_*.log`)에 기록.
