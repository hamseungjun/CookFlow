# CookFlow 프로젝트 현황

마지막 정리: 2026-10-13

이 문서는 새 채팅이나 작업 세션에서 프로젝트를 이어가기 위한 시작점입니다. 사용자 기능은 [FEATURES.md](FEATURES.md), UX 결정과 AI 기술 연결은 [UX_REVIEW.md](UX_REVIEW.md), 개발·서버 실행 방법은 [README.md](README.md)와 [server/README.md](server/README.md)를 확인하세요.

## 프로젝트와 저장소

- CookFlow는 iOS/iPadOS 17 이상을 지원하는 SwiftUI 요리 안내 앱입니다. 웹사이트가 아닙니다.
- GitHub 저장소: https://github.com/hamseungjun/cookflow-ios (비공개, `main` 브랜치)
- 마지막 코드 변경 커밋: `ce30134` (`Show seasoning amounts in spoon measures`). 해당 시점의 변경은 GitHub `main`에 push했습니다.
- 앱: `CookFlow/`, Xcode 프로젝트: `CookFlow.xcodeproj/`, AI 서버: `server/`.
- API 키, 사용자 로컬 DB와 개발 캐시는 Git에 넣지 않습니다.

## 사용자 여정과 기능 요약

메뉴·재료 선택 → 레시피 생성과 검토 → 손질 문구 및 생성형 참고 이미지 확인 → 사용자가 준비 완료 → 단계별 조리·타이머·음성/화면 제어 → 맛 평가와 기록 → 저장 레시피 재조리.

- 한식 집밥 메뉴 30종, 찌개 3종의 로컬 규칙 레시피, AI 맞춤 레시피, 공개 YouTube 조리 영상에서 추출하는 레시피.
- 재료·보유량·인분·맵기·간 설정, 육류·해산물 제외, 장보기 목록과 쿠팡 검색.
- 양념은 큰술·작은술 계량, 두부·채소·고기 등 식재료는 개수·모·봉·컵·g 등으로 표시.
- 재료별 손질 문구와 생성형 참고 이미지. 이미지를 실제 음식 사진 판정에 쓰지 않으며 사용자가 준비 상태를 직접 확인.
- 주방 화력 설정(숫자/다이얼), 단계별 조리 안내, 로컬 타이머·화면 잠금 알림, 보조 타이머, 일시정지·복원·이전 단계 복귀·미투입 재료 분량 조정.
- 한국어 음성 안내와 받아쓰기, 현재 단계 문맥의 음성 의도 판정, 음성 제어 켜기/끄기 분리, 화면 버튼 대안.
- 조리 기록, 레시피북, 재조리, 앱 내부 저장과 세션 복구.
- 알레르기 기능은 없습니다. 화구를 앱이 직접 제어하거나 조리 안전을 보장하지 않습니다.

상세 기능과 제한은 `FEATURES.md`에 있습니다.

## 기술 구조

- iOS 앱은 SwiftUI입니다. `CookFlow/Views/`는 화면, `CookFlow/Core/`는 모델·레시피·조리 상태, `CookFlow/Services/`는 저장·음성·네트워크를 담당합니다.
- `server/app.py`가 AI API 라우팅과 검증을 수행하며 API 키는 서버 환경변수에만 둡니다.
- 맞춤 레시피와 YouTube 분석은 Gemini API를 사용합니다. 맞춤 레시피는 서버에서 계량과 조리 규칙을 확인하고 어긋나면 한 번 보정합니다.
- 음성 흐름은 앱 마이크 → OpenAI `gpt-4o-transcribe` 받아쓰기 → OpenAI Decisions `gpt-6-luna` 의도 판정 → 앱의 현재 단계·타이머 상태 재확인입니다. 받아쓰기 결과만으로 단계가 넘어가지는 않습니다.
- 안내 음성은 Gemini TTS `gemini-3.1-flash-tts-preview` / `Sulafat`을 사용하고, 실패 시 기기 TTS로 이어집니다.
- 손질 이미지는 OpenAI 이미지 생성 API로 재료명과 손질 설명을 바탕으로 만듭니다. 사용자가 찍은 재료 사진을 보내거나 손질 결과를 평가하지 않습니다.
- 준비 참고 이미지는 `server/preparation_images.py`와 SQLite/앱 캐시를 사용합니다.

세부 입력·모델·제한은 `UX_REVIEW.md`와 `server/README.md`에 정리했습니다.

## 최근 변경과 배포 상태

- ‘셰프’ 호출어 안내를 제거했습니다. 별도 호출어 없이 현재 단계와 관련된 말을 인식해 판정합니다.
- 양념 계량은 앱 표시에서 큰술·작은술을 우선 사용하고, AI 맞춤 레시피 생성 지침도 숟가락 단위로 바꿨습니다. 식재료 양은 기존 단위를 유지합니다.
- 양념 계량 변경으로 iPhone 15 Pro용 앱을 빌드·서명·설치하고 실행했습니다. macOS의 앱 번들 `FinderInfo` 때문에 Xcode 기본 CodeSign이 실패했지만 속성을 정리하고 수동 서명해 설치를 완료했습니다.
- 양념 계량 변경을 AI 서버 런타임에 복사하고 사용자 LaunchAgent 서비스를 재설치·재시작했습니다.
- Python 문법 확인과 `git diff --check`를 통과했습니다. 이번 변경 요청에서 테스트 스위트는 실행하지 않았습니다.
- 실제 주방 소음에서 음성 명령의 정확도와 반응을 보장하는 검증은 별도 현장 확인이 필요합니다. `Previews/`의 과거 기록은 각 문서의 날짜·기기·합성 음성 여부를 기준으로 읽으세요.

## 실행과 새 채팅에서 이어가기

- Xcode: `CookFlow.xcodeproj`를 열고 연결된 iPhone/iPad 대상으로 실행합니다.
- 시뮬레이터: `./scripts/run-ios.sh iphone` 또는 `./scripts/run-ios.sh ipad`.
- 폰 AI 연결: `python3 scripts/start_phone_ai.py`; 백그라운드 서비스 설치·갱신: `python3 scripts/install_background_ai.py`.
- 먼저 `PROJECT_STATUS.md`, `FEATURES.md`, `UX_REVIEW.md`를 읽고 필요한 경우 `README.md`와 `server/README.md`를 확인합니다.
- 기능 변경 후 이 현황 문서와 사용자 기능 안내도 실제 코드 상태에 맞춰 갱신합니다. 비밀키·DB·개발 캐시를 커밋하지 않습니다.
