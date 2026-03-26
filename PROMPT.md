# Daily Maintenance System Prompt

## 목표
macOS 환경에서 개발 도구와 시스템을 매일 오전 09:00에 자동으로 점검하고 최신 상태로 유지하는 견고한 Bash 쉘 스크립트를 작성합니다.

## 핵심 요구사항

### 1. 환경 설정 및 초기화
- `set -uo pipefail`로 오류 발생 시 중단 및 변수 엄격 체크.
- `PATH`는 `/opt/homebrew/bin`, `~/.local/bin` 등을 포함하도록 설정.
- `nvm` 및 `conda.sh`를 소싱하여 관련 명령어가 사용 가능한 상태로 환경을 구성.

### 2. 패키지 및 AI 도구 관리
- **Homebrew**: `update`, `upgrade`, `upgrade --greedy` 수행 후 `autoremove`, `cleanup` 정리.
- **Claude Code**: `claude update`를 수행하고, 업데이트 전후 버전을 비교하여 보고용 텍스트 생성.
- **bkit 플러그인**: `marketplace update`와 `plugin update bkit@bkit-marketplace`를 연달아 수행하고 버전 변동 체크.

### 3. 개발 언어 및 라이브러리
- **npm**: `npm update -g` 수행.
- **pip3**: `boto3`, `requests`, `anthropic`, `pandas`, `websockets` 등 핵심 패키지 리스트를 상수로 관리하고, `pip3 install --upgrade` 직전에 버전 체크를 통해 새 버전이 있을 때만 설치하도록 순회 처리.

### 4. Docker 및 이미지 관리
- **Docker Desktop**: `docker desktop update -q` 명령어로 앱 자체 업데이트 시도 (버전 4.38 이상).
- **Public 이미지**: `nginx:alpine`, `portainer/portainer-ce`, `lipanski/docker-static-website` 등을 `docker pull` 하고 이미지 ID 변경 여부로 업데이트 여부 판별.
- **정리**: `docker image prune -f` 수행.

### 5. Git 저장소 동기화 (핵심 로직)
- `$HOME/Project` 하위의 모든 `.git` 디렉토리를 탐색.
- 각 저장소에서 `fetch` 후 `ahead`/`behind` 카운트를 계산.
- `behind`만 존재할 경우 자동 `pull` 수행. `ahead`가 있거나 `diverged` 상태면 경고 목록에 추가하여 수동 처리를 유도.

### 6. 시스템 관리 및 보고
- **Conda**: `update conda -y` 및 `clean --all` 수행.
- **시스템**: `softwareupdate -l` 정보를 확인하고, 디스크 사용량이 80%를 초과할 경우 경고 알림.
- **로그 정리**: `/Library/Logs`, `~/Library/Logs`, 프로젝트 로그 디렉토리에서 30일이 지난 로그(`.log`, `.gz`, `.ips` 등)를 삭제하고 확보된 용량(MB) 계산.
- **텔레그램 알림**: `curl`을 사용하여 업데이트된 항목(✅), 최신인 상태(✔), 오류/경고 항목(⚠️)을 포맷팅하여 전송.

## 환경 설정
- **기본 환경**: macOS M1 Pro, bash (v3.2+), UTF-8 모드
- **경로**: `/Users/a04258` 홈 디렉토리 기준
- **로깅**: 상세 실행 과정은 날짜별 로그 파일(`logs/maintenance_YYYYMMDD.log`)에 기록.
