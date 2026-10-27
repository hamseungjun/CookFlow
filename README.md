# CookFlow

CookFlow는 보유 재료나 YouTube 영상에서 레시피를 만들고 손질부터 조리까지 안내하는 iOS 요리 도우미입니다. 조리 단계, 화력, 타이머와 음성 제어를 지원합니다.

## 구성

- `CookFlow/`와 `CookFlow.xcodeproj/`: SwiftUI iOS 앱
- `server/`: 레시피 생성, 영상 정보 처리, 음성 및 손질 이미지용 Python 서버
- `Tests/`: 앱 핵심 로직 테스트
- `scripts/`: 개발 서버와 기기 연결 도구

## 시작하기

1. Xcode에서 `CookFlow.xcodeproj`를 열고 서명 설정을 자신의 개발 팀에 맞춥니다. iOS 17 이상이 필요합니다.
2. `server/.env.example`을 `server/.env`로 복사하고 필요한 API 키를 로컬에서 입력합니다. 이 파일은 Git에서 제외됩니다. 서버 의존성과 실행 방법은 [서버 설명서](server/README.md)를 참고하세요.
3. 시뮬레이터에서는 로컬 서버를 이용할 수 있습니다. 실제 기기 연결은 `python3 scripts/configure_phone_ai.py` 또는 `python3 scripts/start_phone_ai.py`를 사용합니다. 연결 스크립트가 만드는 `CookFlow/Local.xcconfig`는 Git에서 제외됩니다.

공급자 API 키는 서버에만 두고 앱에 포함하지 마세요. 기기 연결용 토큰은 개발용 앱에 포함되므로 배포 환경의 비밀로 취급할 수 없습니다. 공개 서버 운영에는 별도의 사용자 인증과 사용량 제한이 필요합니다.

## 테스트

서버 의존성을 설치한 뒤 `python3 -m unittest discover -s server -p 'test_*.py'`와 `swift test`를 실행할 수 있습니다. 현재 스냅샷에서는 일부 기존 테스트가 최신 소스와 맞지 않아 실패합니다. 실제 모델 연결은 별도의 키와 네트워크가 필요합니다.
