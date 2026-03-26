# Daily Maintenance System Prompt

## 목표
macOS 시스템과 개발 환경(Homebrew, npm, pip, Docker, Git, Conda 등)을 매일 오전 09:00에 자동으로 점검하고 최신 상태로 유지하는 자동화 쉘 스크립트를 작성합니다.

## 핵심 요구사항
1. **OS 및 패키지 관리**:
   - `brew update`, `brew upgrade`, `brew upgrade --greedy`를 수행합니다.
   - `brew autoremove`, `brew cleanup`을 수행합니다.
2. **AI 및 플러그인**:
   - `claude update` 및 `bkit` 플러그인 업데이트를 진행합니다.
3. **개발 환경**:
   - `npm update -g`를 수행합니다.
   - `pip3`의 핵심 패키지(boto3, requests, pandas 등)를 최신 버전으로 업데이트합니다.
4. **Docker 관리**:
   - `docker desktop update -q`를 사용하여 Docker Desktop 앱을 업데이트합니다.
   - 주요 퍼블릭 이미지(`nginx:alpine`, `portainer/portainer-ce` 등)를 `docker pull` 합니다.
   - `docker image prune -f`로 정리합니다.
5. **Git 저장소**:
   - `$HOME/Project` 하위의 모든 `.git` 디렉토리를 찾아 `fetch`하고, `ahead/behind/diverged`를 체크하여 가능하면 `pull`합니다.
6. **Conda**:
   - `conda update conda -y`를 수행합니다. 반드시 `conda.sh`를 소싱하여 쉘 함수 `conda`를 활성화해야 합니다.
7. **시스템 및 로그**:
   - `softwareupdate -l` 정보를 확인하고 디스크 사용량을 보고합니다.
   - 30일이 지난 로그 파일을 정리합니다.
8. **보고**:
   - `curl`을 통해 텔레그램 봇으로 작업 결과(업데이트 항목, 최신 상태, 오류/경고)를 전송합니다.

## 환경 설정
- **기본 환경**: macOS M1 Pro, bash (v3.2+), UTF-8 모드
- **경로**: `/Users/a04258` 홈 디렉토리 기준
- **오류 처리**: `set -uo pipefail` 사용, 모든 작업은 로그 파일에 기록합니다.
