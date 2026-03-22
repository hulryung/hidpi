# HiDPI

macOS 외장 모니터 HiDPI 설정 및 밝기 관리 도구

![HiDPI App 스크린샷](docs/screenshot.png)

## 만든 이유

Mac을 사용하면서 필요한 소프트웨어가 뭔가 불편하면 직접 만드는 편입니다. BetterDisplay나 Display Buddy 같은 앱들이 HiDPI와 디스플레이 관리를 지원하고 있지만, DDC/CI 밝기 조절이 제가 쓰는 모니터 — 27인치 LG 4K, 32인치 LG 4K — 에서 제대로 동작하지 않아서 괴로웠습니다. 그래서 공부도 할 겸, 제 환경에 맞는 도구를 직접 만들기로 했습니다. 전체 프로젝트는 기능만 요청하면서 바이브 코딩으로 만들었습니다.

## 설치

```bash
brew tap hulryung/tap
brew install --cask hidpi
```

또는 [Releases](https://github.com/hulryung/hidpi/releases) 페이지에서 최신 DMG를 다운로드하세요.

설치 후 DDC/CI를 통한 키보드 밝기 키 동기화를 사용하려면 **시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용**에서 앱 권한을 허용해야 합니다.

## 어떤 앱인가

HiDPI는 macOS에서 외장 모니터를 제어하기 위한 두 가지 도구를 제공합니다:

- **HiDPITool** — 디스플레이 관리 CLI 도구 (모드 전환, 오버라이드, EDID 조회 등)
- **HiDPIApp** — 메뉴바에서 디스플레이 모드, 밝기, HDR을 빠르게 제어하는 앱

핵심적으로 해결하는 문제: macOS가 기본적으로 HiDPI를 지원하지 않는 외장 모니터에 Retina 해상도를 활성화하고, 키보드 밝기 키와 연동되는 안정적인 DDC/CI 밝기 조절을 제공합니다.

## 기능

- **디스플레이 모드 관리** — HiDPI 포함 디스플레이 모드 목록 조회 및 전환
- **Display Override 생성** — 외장 모니터에 HiDPI 해상도를 활성화하는 오버라이드 plist 생성/관리
- **DDC/CI 밝기 조절** — I2C를 통한 DDC/CI 프로토콜로 외장 모니터 하드웨어 밝기 제어
- **키보드 밝기 동기화** — 밝기 키(F1/F2)로 내장 디스플레이와 외장 모니터를 동시에 조절, 낮은 밝기에서는 소프트웨어 디밍 추가 적용
- **HDR 토글** — 디스플레이별 HDR 켜기/끄기
- **가상 디스플레이** — 테스트나 화면 공유를 위한 HiDPI 가상 디스플레이 생성
- **EDID 파싱** — 디스플레이 EDID 데이터 읽기 및 디코딩

## 사용법

### HiDPIApp (메뉴바 앱)

빌드 및 실행:

```bash
cd HiDPIApp
swift build
open .build/debug/HiDPIApp
```

메뉴바에 디스플레이 아이콘이 나타납니다. 클릭하면:
- 연결된 모든 디스플레이와 현재 모드 확인
- 해상도 전환 (15초 롤백 안전 타이머 포함)
- 슬라이더로 밝기 조절
- HDR 토글

키보드 밝기 동기화를 위해 **시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용**에서 앱 권한을 허용해야 합니다.

### HiDPITool (CLI)

빌드 및 사용:

```bash
cd HiDPITool
swift build

# 모든 디스플레이 목록
.build/debug/HiDPITool list

# 메인 디스플레이의 사용 가능한 모드 보기
.build/debug/HiDPITool modes main

# 특정 모드로 전환
.build/debug/HiDPITool set main 42

# 유연한 HiDPI 스케일링 활성화 (sudo 필요)
sudo .build/debug/HiDPITool override create main --flexible

# 특정 HiDPI 해상도 추가
sudo .build/debug/HiDPITool override create 0x1234 --res 2560x1440 --res 1920x1080

# 오버라이드 plist 미리보기 (설치 없이)
.build/debug/HiDPITool override create main --res 2560x1440 --preview

# EDID 데이터 읽기
.build/debug/HiDPITool edid main

# HiDPI 가상 디스플레이 생성
.build/debug/HiDPITool virtual create --width 5120 --height 2880 --name "5K HiDPI"
```

전체 명령어는 `hidpi help`로 확인할 수 있습니다.

## 빌드

```bash
# CLI 도구
cd HiDPITool && swift build

# 메뉴바 앱
cd HiDPIApp && swift build
```

## 요구 사항

- macOS 13+
- Apple Silicon 또는 Intel Mac

## 참고

이 프로젝트는 Apple의 Private API(SkyLight, CoreDisplay, DisplayServices 등)를 사용합니다. 따라서 **App Store 배포가 불가**하며, 직접 배포만 가능합니다. 이 API들은 macOS 업데이트 시 변경될 수 있습니다.

## 라이선스

MIT License — [LICENSE](LICENSE) 파일을 참고하세요.

## 감사의 글

이 프로젝트가 참고한 오픈소스 프로젝트에 대한 정보는 [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md)를 참고하세요.
