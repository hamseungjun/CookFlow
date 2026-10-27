# Cookflow · 소개 홈

홈은 특정 음식의 상세 화면이 아닌 서비스 소개와 탐색의 시작점입니다. 크림·숲 초록 팔레트와 여백을 유지하고, 음식 사진은 표시하지 않습니다.

- 소개: 내 주방의 화력·보유 재료·취향에 맞춘 요리 안내
- 내 주방: 미등록 상태에서는 신규 등록, 등록 후에는 주방 목록으로 이동
- 레시피: 메뉴 탐색 화면으로 이동. 된장찌개·김치찌개·순두부찌개를 이 안에 표시
- 나의 레시피북: 저장한 기록 수와 레시피북 진입
- 진행 중인 조리: 준비·조리·일시정지 상태일 때 이어하기 표시
- iPhone은 세로, iPad는 주방·레시피 진입을 두 열로 배치

현재 외부 AI 레시피 생성이 연결되어 있지 않으므로 홈에서 AI가 생성한다고 표현하지 않습니다. 완성 화면에서도 예시 음식 사진을 제거했습니다.

이전 음식 이미지와 생성 프롬프트는 아래에 제작 이력으로 남깁니다. 이미지 에셋은 현재 화면에서 사용하지 않습니다.

## 이미지 생성

- 방식: 내장 imagegen 도구
- 최종 파일: `CookFlow/Assets.xcassets/DoenjangHero.imageset/hero.png`
- 앱 아이콘: CoreGraphics/CoreText로 직접 만든 벡터 형태를 PNG로 저장

### 최종 생성 프롬프트

Create a premium editorial food photograph for a Korean cooking app. Authentic doenjang-jjigae, appetizing warm soybean paste broth with soft tofu cubes, zucchini half moons, mushrooms and green scallions, in a beautiful dark charcoal Korean earthenware bowl with small handles. Gentle real steam, warm natural morning window light, refined Korean home cooking magazine photography, tactile muted sage green linen and warm ivory tabletop, restrained styling with a wooden spoon near the edge. Three-quarter overhead view, bowl centrally composed fully visible with generous breathing room, square composition, realistic food textures, quietly beautiful and welcoming, no lettering, no logos, no graphic illustration, no cartoon, no collage. Color palette forest green, sage, cream and warm broth brown. Image must work cropped to a landscape hero as well as square.

장보기는 별도 탭으로 제공하고 메뉴·레시피에서 같은 목록으로 연결합니다. 음식 사진을 다시 넣지 않습니다.

## 집밥 레시피 탐색

30종을 국·찌개, 메인요리, 반찬, 밥·한그릇으로 분류합니다. 상단에는 된장찌개 시작 카드, 검색, 가로 분류 버튼을 두고 메뉴 카드는 폭에 따라 열 수가 변합니다. 메뉴별 장보기와 만개의레시피 검색을 제공하며, 유튜브 가져오기는 목록 아래에서 이어집니다. 소개 홈의 메뉴 사진 없는 구성은 유지합니다.


## 생성·가져오기·저장
홈의 레시피 항목은 AI 맞춤 생성, 유튜브 가져오기, 기본 집밥 탐색을 직접 제공합니다. 레시피북은 조리 완료 여부와 독립적으로 저장되며 AI 맞춤/유튜브/기본 집밥 출처, 재료 검색, 즐겨찾기로 다시 찾습니다. 완료한 조리 기록은 별도 항목에 모읍니다. 검토 화면의 저장 버튼은 긴 단계 목록보다 앞에 두어 조리 시작 없이 저장할 수 있게 합니다.


## 요리 단계와 화력
동작별 확인에서 요리 단계별 진행으로 변경했습니다. 된장찌개는 18동작→5단계. 짧은 동작 타이머를 빼고 재료 준비도 한 번의 시작 버튼으로 확인합니다. 의미 있는 가열 구간에 타이머를 두되 실제로 익었다면 먼저 다음으로 넘어갑니다. 하단 고정 버튼으로 긴 내용을 읽는 중에도 진행할 수 있습니다.

화력은 ‘중강불’만 표시하지 않고 등록된 숫자(예: 6단계) 또는 실제 다이얼 포인터를 먼저 보여줍니다. 일반 화력 이름은 함께 표시합니다. 음성에서도 ‘6단계, 중강불’처럼 주방 기준과 요리 기준을 연결하며 Gemini TTS의 따뜻한 목소리를 기본 연결합니다.
