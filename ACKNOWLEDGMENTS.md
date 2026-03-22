# Acknowledgments

이 프로젝트는 다음 오픈소스 프로젝트의 기법과 패턴을 참고하였습니다.

## Third-Party Projects

### MonitorControl

- **Repository:** https://github.com/MonitorControl/MonitorControl
- **License:** MIT License
- **Referenced techniques:** DDC/CI communication patterns, display mode enumeration techniques

### m1ddc

- **Repository:** https://github.com/waydabber/m1ddc
- **License:** MIT License
- **Referenced techniques:** IOAVService I2C communication patterns for Apple Silicon

### NativeDisplayBrightness

- **Repository:** https://github.com/Bensge/NativeDisplayBrightness
- **License:** MIT License
- **Referenced techniques:** Media key event interception techniques

### one-key-hidpi

- **Repository:** https://github.com/xzhih/one-key-hidpi
- **License:** MIT License
- **Referenced techniques:** Display override plist generation techniques

## Standards and Specifications

- DDC/CI 프로토콜 구현은 VESA DDC/CI 표준을 따릅니다.
- EDID 파싱은 VESA E-EDID 표준을 구현합니다.
- Display override plist 형식은 Apple의 문서화된 override 메커니즘을 따릅니다.
- Private Apple API는 macOS 시스템 프레임워크의 런타임 인트로스펙션을 통해 발견되었습니다.
