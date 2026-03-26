# Daily Maintenance System Prompt

## 목표
macOS 및 Ubuntu 환경에서 개발 도구와 시스템을 매일 자동으로 점검하고 최신 상태로 유지하는 견고한 Bash 쉘 스크립트를 작성합니다.

## 핵심 요구사항

### 1. 환경 설정 및 초기화
- `set -uo pipefail`로 오류 발생 시 중단 및 변수 엄격 체크.
- `.env` 파일이 존재할 경우 `source`하여 환경 변수를 로드합니다.
- `HOME`과 `PATH`는 `.env`에 정의된 `MAINTENANCE_HOME`, `MAINTENANCE_PATH`를 우선 반영하며, 하드코딩된 개인 경로는 절대 사용하지 않습니다.
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
- **pip3**: `boto3`, `requests`, `anthropic`, `pandas`, `websockets` 등 핵심 패키지 리스트를 상수로 관리하고, `pip3 install --upgrade` 직전에 버전 체크를 통해 새 버전이 있을 때만 설치하도록 순회 처리.

### 4. Docker 및 이미지 관리
- **Docker Desktop (macOS)**: `docker desktop update -q` 명령어로 앱 자체 업데이트 시도 (버전 4.38 이상).
- **Public 이미지**: `nginx:alpine`, `portainer/portainer-ce`, `lipanski/docker-static-website` 등을 `docker pull` 하고 이미지 ID 변경 여부로 업데이트 여부 판별.
- **정리**: `docker image prune -f` 수행.

### 5. Git 저장소 동기화 (핵심 로직)
- `$HOME/Project` 하위의 모든 `.git` 디렉토리를 탐색.
- 각 저장소에서 `fetch` 후 `ahead`/`behind` 카운트를 계산.
- `behind`만 존재할 경우 자동 `pull` 수행. `ahead`가 있거나 `diverged` 상태면 경고 목록에 추가하여 수동 처리를 유도.

### 6. 시스템 관리 및 보고
- **Conda**: `update conda -y` 및 `clean --all` 수행.
- **시스템**: `softwareupdate -l`(macOS) 또는 `apt list --upgradable`(Ubuntu) 정보를 확인.
- **디스크**: 사용량이 80%를 초과할 경우 경고 알림.
- **로그 정리**: `/Library/Logs`, `~/Library/Logs`, 프로젝트 로그 디렉토리에서 30일이 지난 로그를 삭제하고 확보 결과 보고.
- **텔레그램 알림**: `curl`을 사용하여 업데이트된 항목(✅), 최신인 상태(✔), 오류/경고 항목(⚠️)을 포맷팅하여 전송.

## 🚀 릴리즈 관리 규칙 (Release Rules)
1. **보안 확인**: `.env` 등 민감 파일이 `.gitignore`에 포함되었는지 확인 후 `push`합니다.
2. **About 섹션 자동 업데이트**: 릴리즈 시 `gh repo edit`을 통해 다음 정보를 강제 혹은 검토 업데이트합니다.
   - **Description**: `🍎 macOS & 🐧 Ubuntu Daily Maintenance Automation (Homebrew, APT, npm, pip, Docker, Git, etc.)`
   - **Topics**: `macos`, `ubuntu`, `automation`, `maintenance`, `bash-script`, `homebrew`, `apt`, `docker`, `github`, `telegram`
3. **태그 및 릴리즈**: `gh release create`를 사용하여 버전 관리와 릴리즈 노트를 작성합니다.

## 환경 설정
- **기본 환경**: macOS M1 Pro & Ubuntu Linux, bash, UTF-8 모드
- **경로**: 사용자의 홈 디렉토리 기준 (`.env` 설정을 따름)
- **로깅**: 상세 실행 과정은 날짜별 로그 파일(`logs/maintenance_*.log`)에 기록.
