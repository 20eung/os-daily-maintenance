# 🛠️ Multi-OS Daily Maintenance System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![macOS](https://img.shields.io/badge/OS-macOS-000000.svg?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Ubuntu](https://img.shields.io/badge/OS-Ubuntu-E94333.svg?logo=ubuntu&logoColor=white)](https://ubuntu.com/)

macOS 및 Ubuntu 시스템과 다양한 개발 환경(Homebrew, APT, npm, pip, Docker, Git, Conda 등)을 매일 자동으로 점검하고 최신 상태로 유지하는 견고한 자동화 솔루션입니다.

---

## ✨ 핵심 기능 (Core Features)

**시스템 관리:**
- **📦 OS 패키지 관리**:
  - **macOS**: Homebrew 및 Cask(greedy) 업데이트 및 불필요 파일 정리 (`autoremove`, `cleanup`)
  - **Ubuntu**: APT 패키지 업데이트 및 자동 정리 (`autoremove`, `autoclean`)
  - **🔴 보안 업데이트**: 보안 패치 우선 감지 및 알림
- **💾 시스템 상태 모니터링**:
  - 디스크 사용률, 메모리 사용률 실시간 감시
  - CPU/디스크 온도 감지 (lm-sensors, smartctl)
  - systemd 서비스 상태 확인 및 실패 서비스 감지
  - 네트워크 연결 상태 확인
- **🔄 커널 & 파일시스템 관리**:
  - 커널 업데이트 상태 및 재부팅 필요 여부 감지
  - 주간 파일시스템 무결성 검사(fsck) 스케줄

**개발 환경 관리:**
- **🤖 AI 개발 도구**: Claude Code 및 `bkit` 플러그인의 실시간 버전 동기화
- **💻 개발 라이브러리**: `npm` 전역 패키지 및 설치된 모든 `pip3` 라이브러리 자동 감지 및 업데이트
- **🐳 컨테이너 최적화**: Docker 앱 업데이트 체크(macOS) 및 모든 `docker-compose.yml` 자동 발견하여 이미지 `pull` & 컨테이너 재시작, 미사용 이미지 정리
- **📂 Git 프로젝트 동기화**: `USER_PROJECT_DIR` 하위 모든 저장소의 로컬/원격 상태 점검 및 안전한 자동 병합

**유지보수 & 모니터링:**
- **🧹 자동 정리**: 30일 경과 로그 자동 삭제, Orphaned 프로세스 감지
- **📢 실시간 보고**: 작업 결과를 한눈에 보기 쉬운 포맷으로 텔레그램 봇을 통해 즉시 전송
- **🛡️ 범용성 및 견고함**:
  - 도구(brew, docker 등) 미설치 시 자동으로 건너뛰고 리포트에 표시
  - `.env` 기반의 완전한 독립적 환경 설정 지원 (Portable Config)
  - `sudo` 권한 부족 시 자동 안내 가이드(visudo) 제공

---

## 🚀 시작하기 (Getting Started)

### 1️⃣ 요구사항 (Prerequisites)
- **OS**: macOS (M1/Intel) 또는 Ubuntu/Debian 기반 Linux
- **Shell**: Bash v3.2 이상
- **기본 도구**: 설치된 도구가 있다면 자동으로 감지하여 업데이트를 시도합니다. (선택 사항: `brew`, `apt`, `git`, `docker`, `npm`, `pip3`, `claude` 등)

**온도 감지 (선택사항, Ubuntu):**
```bash
# CPU 온도 감지 (선택사항)
sudo apt install lm-sensors
sudo sensors-detect

# 디스크 온도 감지 (선택사항)
sudo apt install smartmontools
sudo smartctl -a /dev/sda
```

### 2️⃣ 설치 및 설정 (Installation)
저장소를 클론한 후 환경 변수 설정을 진행합니다.

```bash
# 저장소 클론
git clone https://github.com/20eung/os-daily-maintenance.git
cd os-daily-maintenance

# 1. 공통 설정 파일 생성 (텔레그램 등)
cp .env.sample .env

# 2. OS별 전용 설정 파일 생성 (Mac 기준 예시)
cp .env.darwin.sample .env.darwin

# 3. 설정 수정
nano .env
nano .env.darwin
```

### 3️⃣ `.env` 설정 항목 (범용적 사용을 위한 최소 설정)

대부분의 설정은 **자동 감지**되므로 필수 설정은 거의 없습니다.

**필수 설정 (선택사항):**
- `USER_PROJECT_DIR`: Docker Compose 프로젝트 탐색 경로 (기본값: `/data`)
- `MAINTENANCE_BOT_KEY`: 텔레그램 봇 API 키 (알림 기능, 생략 가능)
- `MAINTENANCE_CHAT_ID`: 텔레그램 채팅방 ID (알림 기능, 생략 가능)

**자동 감지되는 설정 (설정 불필요):**
- `MAINTENANCE_HOME`: 자동으로 현재 사용자의 `$HOME` 사용
- `MAINTENANCE_PATH`: 시스템 기본 `$PATH` 사용
- **pip 패키지**: 설치된 모든 패키지 자동 감지
- **Docker Compose**: `USER_PROJECT_DIR` 아래의 모든 `docker-compose.yml` 자동 발견
- **Git 저장소**: `USER_PROJECT_DIR` 아래의 모든 `.git` 자동 발견

**추가 설정 (옵션):**
- `CLEANUP_LOG_DIRS`: 30일이 지난 로그를 정리할 추가 디렉토리 (공백으로 구분)

---

## 📅 자동화 설정 (Automation with Cron)

매일 오전 01:00에 스크립트가 실행되도록 설정하는 것을 권장합니다.

```bash
# crontab 편집
crontab -e

# 아래 내용 추가 (macOS 예시)
00 01 * * * /Users/YOUR_USERNAME/Project/os-daily-maintenance/daily_maintenance_macos.sh
```

```bash
# 아래 내용 추가 (Ubuntu 예시)
00 01 * * * /home/YOUR_USERNAME/Project/os-daily-maintenance/daily_maintenance_ubuntu.sh
```

---

## 🔑 `sudo` 권한 설정 (Passwordless Sudo)

스크립트에서 OS 패키지 업데이트(`apt`)나 시스템 로그 정리(`/var/log`, `/Library/Logs`) 작업을 수행하려면 `sudo` 권한이 필요합니다. 자동화된 환경(Cron 등)에서 비밀번호 입력 없이 작동하게 하려면 아래 설정을 추가하세요.

1. 터미널에서 `sudo visudo` 명령을 실행합니다.
2. 파일 하단에 아래 내용을 추가합니다 (사용자명에 맞게 수정).

**Ubuntu/Linux:**
```text
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/find
```

**macOS:**
```text
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/find
```

---

## 📁 프로젝트 구조 (Folder Structure)

```text
os-daily-maintenance/
├── daily_maintenance_macos.sh  # macOS 실행 스크립트 (Homebrew 기반)
├── daily_maintenance_ubuntu.sh # Ubuntu/Debian 실행 스크립트 (APT 기반)
├── .env                        # 공통 환경 설정 (텔레그램 등)
├── .env.darwin                 # macOS 로컬 전용 설정 (Git 제외)
├── .env.linux                  # Linux 로컬 전용 설정 (Git 제외)
├── .env.sample                 # 공통 설정 샘플 파일
├── .env.darwin.sample          # macOS 전용 설정 샘플 파일
├── .env.linux.sample           # Linux 전용 설정 샘플 파일
├── .gitignore                  # Git 기록 제외 설정
├── README.md                   # 프로젝트 매뉴얼
└── logs/                       # 실행 이력 로그 (날짜별)
```

---

- [x] Multi-OS (macOS & Ubuntu) 지원 스크립트 분리
- [x] Docker Desktop 앱 자동 업데이트 연동 (macOS 전용)
- [x] Git 저장소 간 충돌(Diverged) 자동 감지 로직
- [x] 시스템/사용자 로그 정리 범위 확대
- [x] 도구 미설치 시 자동 건너뜀 로직 및 리포트 적용
- [x] 비밀번호 없는 sudo 권한 가이드 및 체크 로직 추가
- [x] 텔레그램 보고서 인터페이스 개선

---

## 📄 라이선스 (License)
이 프로젝트는 MIT License를 따릅니다.
