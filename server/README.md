# CookFlow AI 연결

음성 받아쓰기는 OpenAI `gpt-4o-transcribe`, 음성 의도 판정은 OpenAI Decisions의 `gpt-6-luna`, AI 맞춤 레시피 생성은 OpenAI Responses API의 `gpt-6-luna`를 사용합니다. 공개 YouTube 레시피 추출과 음성 안내는 BAZE의 Gemini API를 사용합니다. 손질 참고 이미지는 재료·손질 설명을 바탕으로 이미지 생성 API에서 만듭니다. 앱은 실제 손질 식재료 사진을 서버로 보내지 않습니다. API 키는 `server/.env`에 보관하며 이 파일은 Git과 배포 ZIP에서 제외합니다. 로컬 서버와 앱은 사진·영상 내용을 로그로 남기지 않습니다. AI 서비스 자체의 보관 정책은 제공자 정책을 따릅니다.

## 개발용 실행

```sh
python3 scripts/start_ai_server.py
```

개발 터미널을 닫아도 현재 Mac 세션에서 계속 실행됩니다. 종료는 `.build/ai-server.pid`에 기록된 프로세스를 종료하면 됩니다. Mac을 재시작하면 위 명령으로 다시 실행합니다. 추가 패키지는 필요하지 않습니다. `http://localhost:8765/health`로 서버와 모델을 확인합니다. 개발 시뮬레이터는 다음 주소를 기본 사용합니다.

- 손질 참고 이미지: `http://localhost:8765/api/preparation-image`
- 영상: `http://localhost:8765/api/video-recipe`
- 음성 의도: `http://localhost:8765/api/voice/decide`

기본 서버는 127.0.0.1에 연결합니다. `python3 scripts/configure_phone_ai.py`로 이 Mac과 앱을 연결하면 서버는 로컬 네트워크에서도 요청을 받고, 실물 iPhone/iPad는 같은 Wi-Fi의 Mac `.local` 주소를 자동 사용합니다. 처음 로컬 네트워크 권한을 허용해야 합니다. 이 개발 연결은 Mac이 켜져 있고 서버가 실행 중일 때 동작합니다. 외부 네트워크 이용은 HTTPS 서버 배포가 별도로 필요합니다. 배포 시 HTTPS 역방향 프록시와 사용자 인증·사용량 제한을 적용하고 각 API 경로를 노출하세요. OpenAI/BAZE 공급자 키는 서버에만 보관합니다. 앱에는 이 Mac 개발 서버 전용 접근 토큰만 포함되며 LAN 요청을 인증합니다. 다른 서버 주소로 공급자 키나 접근 토큰을 전송하지 않습니다. 공개 배포/호스팅은 포함하지 않습니다.

## 생성형 손질 모양 참고 이미지

`/api/preparation-image`는 재료와 손질 방법에 맞는 예시 이미지를 비동기로 생성하고, 동일 요청은 SQLite 캐시에서 재사용합니다. 이 이미지는 사용자가 손질 모양을 참고하는 용도입니다. 생성된 이미지는 손질 모양 참고용입니다. 이미지를 만들 수 없으면 글 안내를 따라 준비할 수 있습니다.

영상 레시피는 공개 YouTube URL에서 제목·설명·자막을 분석해 단계와 계량을 구성합니다. 인분과 영상에 나오지 않은 정보는 사용자가 검토·보완합니다.

## 테스트

```sh
python3 -m unittest discover -s server -p 'test_*.py'
```

자동 테스트는 실제 유료 모델을 호출하지 않습니다. 실제 모델 연결은 공개 김치찌개 영상과 사용자가 제공한 닭볶음탕 영상 추출을 확인했습니다. 손질 참고 이미지는 생성형 이미지로 제공됩니다.

공식 참고: [BAZE Gemini 네이티브 API](https://docs.mindlogic.ai/docs/general/api-gateway/reference/gemini-native), [Gemini 공개 YouTube 입력](https://ai.google.dev/gemini-api/docs/generate-content/video-understanding).


### AI 맞춤 생성
`POST /api/recipe/generate`에는 dish, ingredients(재료·양념 문자열), servings(1~4), spice/salt(0~2), excludeMeat/excludeSeafood를 보냅니다. 실제 모델이 새 레시피를 작성하며 영상 입력은 사용하지 않습니다. 앱과 공유하는 재료·단계 스키마를 사용하고, 불 조절과 최종 OFF 확인을 앱 단계로 연결합니다. 입력한 재료와 취향도 AI 제공자로 전달됩니다. 모델 결과의 조리 전 검토가 필요합니다.


### 자연스러운 음성 안내
`POST /api/speech`에 `{ "text": "한국어 안내 문장" }`을 전달합니다(1~2000자). BAZE `/audio/speech/`의 `gemini-3.1-flash-tts-preview`, `Sulafat`을 호출하며 `COOKFLOW_TTS_MODEL`로 모델을 변경할 수 있습니다. 원시 PCM 24kHz mono 16-bit LE를 WAV로 변환해 `audio/wav`로 반환합니다. 반복 문장은 24개까지 서버 메모리에만 캐시하며 텍스트·오디오를 파일이나 로그에 저장하지 않습니다. 앱은 재생 지연/실패 시 기기 TTS로 이어갑니다. TTS 호출도 AI 제공자의 사용량과 크레딧을 사용합니다. 연결 검증용 공개 안내 샘플은 `Previews/voice-demo.wav`로 별도 보관합니다.


## OpenAI Decisions

음성 받아쓰기 문장과 현재 조리 단계로 다음 의도를 판단합니다. 음성 서비스가 불명확한 입력을 완료로 처리하지 않도록 기존 단계 검사를 적용합니다.

손질 참고 이미지는 별도 이미지 생성 API가 만듭니다. 재료명과 자를 모양 등 이미지 생성에 필요한 설명이 입력되며, 사용자가 촬영한 식재료 사진이나 영상은 입력되지 않습니다. 이미지 생성 결과는 참고 예시이며 실제 손질 결과에 대한 검증 판정이 아닙니다.

## 실제 폰 HTTPS 연결 (현재 설치본)

Cloudflare의 [개발용 Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)을 통해 인터넷에서 Mac 서버에 접속합니다. 모든 요청에 Mac 개발 서버 전용 앱 토큰이 필요하고, 터널의 localhost 요청도 인증을 생략하지 않습니다. 서버는 다시 127.0.0.1에만 바인딩합니다. 공급자 API 키는 폰에 없습니다.

```sh
python3 scripts/start_phone_ai.py
```

현재 터널이 실행 중이면 주소를 재사용합니다. 앱의 기본 주소는 Info.plist에 자동 반영됩니다. 새로운 터널을 만든 경우 주소가 달라질 수 있으므로 Xcode에서 다시 빌드해 설치해야 합니다. Quick Tunnel은 임시 개발 연결이며 Mac 종료·절전·터널 종료 시 AI 연결이 끊깁니다. 앱의 내 주방 → AI 연결 확인으로 접속 상태를 확인합니다. 상시 배포에는 고정 HTTPS 서버가 필요합니다.

실물 기기 빌드는 Desktop의 파일 제공자 속성이 서명에 섞이지 않도록 `/tmp/CookFlow-device-build`를 사용했습니다. Xcode의 기본 DerivedData 위치로 빌드할 때는 이 개발용 .build 폴더를 사용할 필요가 없습니다.


## 음성·레시피 검증

음성은 앱의 음량 기반 감지 후 `speech_gate.py`의 20ms WebRTC VAD를 통과해야 `gpt-4o-transcribe`로 전달됩니다. 현재 조리 재료와 완료 문구를 받아쓰기 힌트로 보내지 않습니다. ASR logprobs가 낮거나 한국어 발화가 아니면 빈 문자열을 반환하고, 빈 결과에는 반복 안내를 띄우지 않습니다. 원음은 검사 중 메모리에서만 처리합니다. 말소리가 있는 TV·다른 사람의 대화를 사용자 명령과 완전히 구별하는 기능은 아니므로, 실제 주방 소음 샘플로 오반응률을 계속 조정해야 합니다.

`skip`은 서버와 iOS 엔진 모두 실행하지 않습니다. `confirm`은 대기 상태에서만 실행하며 진행 중 타이머를 종료하지 않습니다. 앱은 안내 종료 후 1.2초 뒤 듣기를 재개합니다. AI 연결 실패 시 받아쓴 문장만으로 상태를 변경하지 않습니다.

`recipe_rules.json`은 AI 생성 요청에 들어가는 조리 규칙입니다. 기본 분량, 선택 재료, 조리 화력·시간, 양파·마늘·김치 볶기 및 순두부찌개 고추기름·간장 과정은 생성 결과도 검사합니다. 어긋난 결과는 한 번 보정하고 계속 어긋나면 실행하지 않습니다. 맛을 자동 측정하거나 보증하는 기능은 아닙니다.

개발 서버 의존성 설치: `python3 -m pip install --target server/vendor -r server/requirements.txt`. 상주 서버 갱신은 `python3 scripts/install_background_ai.py`로 수행합니다.

### 음성 Decisions 질문 분리 (2026-10-13)

`gpt-6-luna`의 `/v1/decisions` 한 요청에 독립 질문 3개를 보냅니다.

- `current_action_report` (predicate): 현재 안내의 행동을 수행 중/완료했다는 보고인지.
- `incomplete_or_mismatched` (predicate): 일부만 수행하거나 다른 재료/행동을 보고했는지.
- `control_request` (choice): 다시 설명, 화력/시간 질문, 멈춤/재개, 타이머 정정/추가 요청 또는 none.

질문은 앞 질문의 답을 가정하지 않습니다. 서버가 보고 확률과 부분/불일치 확률을 확인하고, 앱이 현재 단계·음성 수신 시점·타이머 상태를 별도로 제한합니다. 누락, refusal, 형식 오류는 상태 유지입니다. API 확률/확신 값은 실측 정확도가 아닙니다.

`PYTHONPATH=server/vendor:server python3 scripts/verify_voice_intents.py`는 실제 API를 호출하므로 사용량이 발생하는 선택적 평가입니다. `.build/divided-decision-final-eval.log`에서 초기 텍스트 36건 중 33건이 기대한 판정, 3건은 완료 보고를 보수적으로 유지한 결과였습니다. 이 소규모 텍스트 표본은 실제 마이크·주방 소음 성능을 보장하지 않습니다.

설계 근거: https://developers.openai.com/api/docs/guides/decisions

### 레시피 생성 지연 개선 (2026-10-13)

레시피 검토 화면은 음성 생성 완료를 기다리지 않습니다. 재료 준비 화면에서 조리 시작을 누르면 첫 안내와 타이머 시작 음성만 준비를 기다리고 나머지는 백그라운드에서 받습니다.

레시피 생성에는 OpenAI Responses API의 `gpt-6-luna`와 strict JSON Schema 출력을 사용합니다. 참고 baseline에서 기기 설정·UUID·중복 음성 문구를 제거하고 재료 분량/손질, 조리 순서, 불, 시간, 안전 주의는 유지합니다. 검증을 통과한 동일 조건의 레시피 최대 32건을 프로세스 메모리에서 재사용합니다. 요청의 재료·인분·취향·기준 레시피 또는 규칙이 바뀌면 다른 캐시 키가 됩니다. 실패한 결과는 캐시하지 않고 결과는 복사해서 반환합니다. 서버 재시작 시 캐시는 초기화됩니다.

동일 순두부 테스트의 단일 전후 측정: 레시피 본문 28.49초 → 10.25초, 같은 요청 재사용 0.0006초(서버 함수 시간, 네트워크 제외). 짧은 안내 TTS는 3.81~4.90초로 외부 제공자의 응답 지연이 남아 있습니다. 실제 사용자 대기 시간은 통신과 재검증 횟수에 따라 달라집니다. 모델 호출 로그는 소요 시간과 토큰 개수만 기록합니다. 음성은 백그라운드 요청 하나와 즉시 안내 요청을 분리해 전체 2개 한도를 유지하고 준비/재생 요청을 우선합니다.

Thinking 설정 근거: https://ai.google.dev/gemini-api/docs/thinking


### 받아쓰기 입력 완화 (2026-10-13)

짧은 한국어 발화가 무음으로 버려지지 않도록 WebRTC VAD 최소 발화량을 조정하고, 받아쓰기 평균 토큰 확률 하한을 0.82에서 0.65로 낮췄습니다. 받아쓴 문장 자체가 조리 동작을 바로 수행하지는 않습니다. 기존 Decisions 의미 판정과 현재 단계·타이머 검사를 계속 통과해야 합니다. 실제 주방 소음에서의 인식 품질은 실기기 현장 확인이 필요합니다.


음성 받아쓰기는 iOS가 현재 조리 단계의 재료 이름을 문맥 힌트로 전달합니다. 모델은 발화를 그대로 받아쓰며, 확인어를 보충하지 말라는 프롬프트를 포함합니다. 음성 판정에서는 단독 완료 응답(예: “했어”, “넣었어”)을 현재 요청의 완료로 해석하고, 질문·부정·미래형·문장이 길어진 일상 대화는 계속 Decision API의 의미 판정을 거칩니다. API 확인: 두 짧은 완료 표현은 confirm, “아직 안 넣었어”, “했어?”, “내일 넣을게”, 일반 대화는 keep을 반환했습니다.
