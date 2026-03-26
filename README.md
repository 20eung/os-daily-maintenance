# 🛠️ Multi-OS Daily Maintenance System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![macOS](https://img.shields.io/badge/OS-macOS-000000.svg?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Ubuntu](https://img.shields.io/badge/OS-Ubuntu-E94333.svg?logo=ubuntu&logoColor=white)](https://ubuntu.com/)

macOS 및 Ubuntu 시스템과 다양한 개발 환경(Homebrew, APT, npm, pip, Docker, Git, Conda 등)을 매일 자동으로 점검하고 최신 상태로 유지하는 견고한 자동화 솔루션입니다.

---

## ✨ 핵심 기능 (Core Features)

- **📦 OS 패키지 관리**: 
  - **macOS**: Homebrew 및 Cask(greedy) 업데이트 및 불필요 파일 정리 (`autoremove`, `cleanup`)
  - **Ubuntu**: APT 패키지 업데이트 및 자동 정리 (`autoremove`, `autoclean`)
- **🤖 AI 개발 도구**: Claude Code 및 `bkit` 플러그인의 실시간 버전 동기화
- **💻 개발 라이브러리**: `npm` 전역 패키지 및 10종의 핵심 `pip3` 라이브러리 자동 업데이트
- **🐳 컨테이너 최적화**: Docker 앱 업데이트 체크(macOS) 및 주요 Public 이미지 자동 `pull`, 미사용 이미지 정리
- **📂 Git 프로젝트 동기화**: `~/Project` 하위 모든 저장소의 로컬/원격 상태 점검 및 안전한 자동 병합
- **🧹 시스템 유지보수**: 30일 경과 로그 자동 삭제 및 디스크 여유 공간 실시간 모니터링
- **📢 실시간 보고**: 작업 결과를 한눈에 보기 쉬운 포맷으로 텔레그램 봇을 통해 즉시 전송

---

## 🚀 시작하기 (Getting Started)

### 1️⃣ 요구사항 (Prerequisites)
- **OS**: macOS (M1/Intel) 또는 Ubuntu/Debian 기반 Linux
- **Shell**: Bash v3.2 이상
- **Tools**: `brew` (macOS) 또는 `apt` (Ubuntu), `git` 등이 설치되어 있어야 합니다.

### 2️⃣ 설치 및 설정 (Installation)
저장소를 클론한 후 환경 변수 설정을 진행합니다.

```bash
# 저장소 클론
git clone https://github.com/your-username/Daily-Maintenance.git
cd Daily-Maintenance

# 설정 파일 생성 및 수정
cp .env.sample .env
nano .env
```

### 3️⃣ `.env` 설정 항목
`.env` 파일에 텔레그램 토큰과 본인의 사용자 경로를 입력하세요.
- `MAINTENANCE_BOT_KEY`: 텔레그램 봇 API 키
- `MAINTENANCE_CHAT_ID`: 텔레그램 채팅방 ID
- `USER_PROJECT_DIR`: Git 저장소를 탐색할 루트 경로

---

## 📅 자동화 설정 (Automation with Cron)

매일 오전 09:00에 스크립트가 실행되도록 설정하는 것을 권장합니다.

```bash
# crontab 편집
crontab -e

# 아래 내용 추가 (macOS 예시)
00 09 * * * /Users/YOUR_USERNAME/Project/Daily-Maintenance/daily_maintenance.sh

# 아래 내용 추가 (Ubuntu 예시)
00 09 * * * /home/YOUR_USERNAME/Project/Daily-Maintenance/daily_maintenance_ubuntu.sh
```

---

## 📁 프로젝트 구조 (Folder Structure)

```text
Daily-Maintenance/
├── daily_maintenance.sh        # macOS 실행 스크립트
├── daily_maintenance_ubuntu.sh # Ubuntu/Debian 실행 스크립트
├── .env                        # 사용자 환경 설정 (Git 제외)
├── .env.sample                 # 설정 샘플 파일
├── .gitignore                  # Git 기록 제외 설정
├── README.md                   # 프로젝트 매뉴얼
└── logs/                       # 실행 이력 로그 (날짜별)
```

---

## ✅ 개발 상황 (Roadmap)
- [x] Multi-OS (macOS & Ubuntu) 지원 스크립트 분리
- [x] Docker Desktop 앱 자동 업데이트 연동 (macOS 전용)
- [x] Git 저장소 간 충돌(Diverged) 자동 감지 로직
- [x] 시스템/사용자 로그 정리 범위 확대
- [x] 텔레그램 보고서 인터페이스 개선

---

## 📄 라이선스 (License)
이 프로젝트는 MIT License를 따릅니다.
