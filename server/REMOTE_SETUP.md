# Mac 상주 AI 서버

현재 외부 HTTPS 주소는 `~/Library/Application Support/CookFlowServer/AI 서버 주소.txt`에 저장됩니다. 같은 Wi-Fi가 아니어도 폰에 인터넷이 있으면 접속할 수 있습니다.

- 서버는 로그인 시 자동 실행되고 종료되면 다시 실행됩니다.
- 노트북은 켜둔 채 전원과 인터넷을 연결하세요. 유휴 절전은 방지하지만 뚜껑 닫기·수동 잠자기·전원 종료·로그아웃에서는 서버를 사용할 수 없습니다.
- 클라우드 호스팅 요금은 없습니다. 기존 AI API 및 새 이미지 생성 API는 제공자 사용량으로 과금됩니다. 동일 재료·손질 방법은 DB에서 재사용합니다.
- 이미지 DB: `~/Library/Application Support/CookFlowServer/data/preparation-images.sqlite3`. 생성된 손질 참고 이미지는 SQLite BLOB 캐시로 보관하고 재사용합니다. 사용자가 촬영한 재료 사진은 저장하지 않습니다. 앱에도 다운로드 캐시가 있습니다.
- 무료 Quick Tunnel은 영구 주소가 아닙니다. 터널 재접속으로 주소가 바뀌면 위 주소 파일을 확인하고 앱의 **내 주방 → AI 연결 → 서버 주소 변경**에서 새 주소를 입력하세요. 이후 다시 빌드할 필요는 없습니다.

## 코드 변경 후 서비스 갱신

프로젝트에서 `python3 scripts/install_background_ai.py`를 실행하세요. DB는 유지됩니다. 현재 외부 주소가 유효하면 기존 터널을 유지합니다.

## 서비스 정지

`launchctl bootout gui/$(id -u)/com.cookflow.ai`

`launchctl bootout gui/$(id -u)/com.cookflow.remote`

`launchctl bootout gui/$(id -u)/com.cookflow.awake`

LaunchAgents plist 파일을 지우지 않으면 다음 로그인 시 다시 실행됩니다.
