-- =====================================================
-- 08. 핫플레이스 집중 데이터 생성 (시나리오 2)
-- 목표: 특정 store_id에 Cheer 300개, Story 50개 집중
-- =====================================================

-- 핫플레이스로 지정할 Store 생성 (성수동 신상 맛집)
INSERT INTO store (kakao_id, category, phone_number, name, place_url, road_address, lot_number_address, district, latitude, longitude, created_at)
VALUES (
    '9999999999',
    'WESTERN',
    '02-1234-5678',
    '성수동 핫플레이스 테스트 가게',
    'http://place.map.kakao.com/9999999999',
    '서울 성동구 연무장길 123',
    '서울 성동구 성수동2가 456',
    'SEONGDONG',
    37.5445,
    127.0557,
    NOW()
);

-- 방금 생성한 Store의 ID 저장
SET @hotplace_store_id = LAST_INSERT_ID();

-- Member ID 목록을 임시 테이블로 생성 (FK 제약 조건 만족)
DROP TEMPORARY TABLE IF EXISTS member_ids;
CREATE TEMPORARY TABLE member_ids AS
SELECT id AS member_id FROM member;

-- 설명 템플릿
SET @hotplace_desc1 = '성수동 최고 핫플레이스! 여기 모르면 진짜 손해봅니다.';
SET @hotplace_desc2 = '인스타그램에서 보고 찾아왔는데 기대 이상이에요!';
SET @hotplace_desc3 = '웨이팅 2시간 했는데 아깝지 않아요. 꼭 가세요!';
SET @hotplace_desc4 = '성수 갈 때마다 여기 들르는데 매번 만족스러워요.';
SET @hotplace_desc5 = '분위기 미쳤고, 음식도 맛있고, 가격도 착해요.';
SET @hotplace_desc6 = '데이트 코스로 강추! 인생샷 건질 수 있어요.';
SET @hotplace_desc7 = '친구들이랑 왔는데 다들 또 오자고 난리예요 ㅋㅋ';
SET @hotplace_desc8 = '여기 진짜 맛집입니다. 웨이팅 각오하세요!';
SET @hotplace_desc9 = '성수에서 이만한 곳 찾기 힘들어요. 강력 추천!';
SET @hotplace_desc10 = '주말에는 예약 필수! 평일도 웨이팅 있어요.';

-- 1. 핫플레이스에 Cheer 300개 생성
-- 임시 테이블에 랜덤 Member 미리 생성
DROP TEMPORARY TABLE IF EXISTS temp_hotplace_members;
CREATE TEMPORARY TABLE temp_hotplace_members (idx INT AUTO_INCREMENT PRIMARY KEY, member_id BIGINT);
INSERT INTO temp_hotplace_members (member_id) SELECT id FROM member ORDER BY RAND() LIMIT 300;

INSERT INTO cheer (member_id, store_id, description, is_admin, created_at)
SELECT
    m.member_id,
    @hotplace_store_id AS store_id,
    CASE (nums.n % 10)
        WHEN 0 THEN @hotplace_desc1
        WHEN 1 THEN @hotplace_desc2
        WHEN 2 THEN @hotplace_desc3
        WHEN 3 THEN @hotplace_desc4
        WHEN 4 THEN @hotplace_desc5
        WHEN 5 THEN @hotplace_desc6
        WHEN 6 THEN @hotplace_desc7
        WHEN 7 THEN @hotplace_desc8
        WHEN 8 THEN @hotplace_desc9
        ELSE @hotplace_desc10
    END AS description,
    0 AS is_admin,
    DATE_ADD('2026-03-01', INTERVAL (nums.n % 117) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 300
) nums
JOIN temp_hotplace_members m ON m.idx = nums.n;

-- 2. 핫플레이스 Cheer에 이미지 추가 (평균 1.5개)
-- 방금 생성한 Cheer ID 범위 확인
SET @hotplace_cheer_start = (SELECT MIN(id) FROM cheer WHERE store_id = @hotplace_store_id);
SET @hotplace_cheer_end = (SELECT MAX(id) FROM cheer WHERE store_id = @hotplace_store_id);

-- 모든 Cheer에 첫 번째 이미지
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    c.id AS cheer_id,
    CONCAT('cheer/', c.id, '/', UUID(), '.jpeg') AS image_key,
    0 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer c
WHERE c.store_id = @hotplace_store_id;

-- 50%에 두 번째 이미지
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    c.id AS cheer_id,
    CONCAT('cheer/', c.id, '/', UUID(), '.jpeg') AS image_key,
    1 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer c
WHERE c.store_id = @hotplace_store_id
AND RAND() < 0.5;

-- 3. 핫플레이스 Cheer에 태그 추가 (평균 3개)
INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'INSTAGRAMMABLE' FROM cheer c WHERE c.store_id = @hotplace_store_id;

INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'GOOD_FOR_DATING' FROM cheer c WHERE c.store_id = @hotplace_store_id AND RAND() < 0.8;

INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'NEAR_SUBWAY' FROM cheer c WHERE c.store_id = @hotplace_store_id AND RAND() < 0.6;

INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'MANY_NEARBY_ATTRACTIONS' FROM cheer c WHERE c.store_id = @hotplace_store_id AND RAND() < 0.4;

-- 4. 핫플레이스에 Story 50개 생성
-- 임시 테이블에 랜덤 Member 미리 생성
DROP TEMPORARY TABLE IF EXISTS temp_hotplace_story_members;
CREATE TEMPORARY TABLE temp_hotplace_story_members (idx INT AUTO_INCREMENT PRIMARY KEY, member_id BIGINT);
INSERT INTO temp_hotplace_story_members (member_id) SELECT id FROM member ORDER BY RAND() LIMIT 50;

INSERT INTO story (member_id, store_kakao_id, store_name, store_road_address, store_lot_number_address, store_category, description, created_at)
SELECT
    m.member_id,
    s.kakao_id AS store_kakao_id,
    s.name AS store_name,
    s.road_address AS store_road_address,
    s.lot_number_address AS store_lot_number_address,
    s.category AS store_category,
    CASE (nums.n % 10)
        WHEN 0 THEN '성수동 핫플 진짜 맛있어요! 인생맛집 등극!'
        WHEN 1 THEN '여기 분위기 미쳤습니다... 데이트 필수 코스'
        WHEN 2 THEN '웨이팅 2시간 했지만 후회 없어요 ㅠㅠ'
        WHEN 3 THEN '성수동 오면 꼭 들러야 하는 그곳!'
        WHEN 4 THEN '인스타에서 보고 왔는데 실물이 더 예뻐요'
        WHEN 5 THEN '친구들이랑 다같이 감탄했어요 ㄷㄷ'
        WHEN 6 THEN '재방문 의사 300%! 다음 주에 또 올 거예요'
        WHEN 7 THEN '성수 핫플의 끝판왕... 여기가 진리입니다'
        WHEN 8 THEN '웨이팅 각오하고 가세요! 그래도 기다릴 가치 있음'
        ELSE '진짜 찐 맛집이에요. 주변 사람들한테 다 추천했습니다'
    END AS description,
    DATE_ADD('2026-03-01', INTERVAL (nums.n % 117) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 50
) nums
JOIN temp_hotplace_story_members m ON m.idx = nums.n
CROSS JOIN store s
WHERE s.id = @hotplace_store_id;

-- 5. 핫플레이스 Story에 이미지 추가 (평균 2개)
SET @hotplace_story_start = (SELECT MIN(id) FROM story WHERE store_kakao_id = '9999999999');
SET @hotplace_story_end = (SELECT MAX(id) FROM story WHERE store_kakao_id = '9999999999');

-- 모든 Story에 첫 번째 이미지
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    s.id AS story_id,
    CONCAT('story/', s.id, '/', UUID(), '.jpeg') AS image_key,
    0 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story s
WHERE s.store_kakao_id = '9999999999';

-- 80%에 두 번째 이미지
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    s.id AS story_id,
    CONCAT('story/', s.id, '/', UUID(), '.jpeg') AS image_key,
    1 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story s
WHERE s.store_kakao_id = '9999999999'
AND RAND() < 0.8;

-- 생성 결과 확인
SELECT
    '핫플레이스 Store ID' AS metric,
    @hotplace_store_id AS value
UNION ALL
SELECT
    '핫플레이스 Cheer 수',
    COUNT(*)
FROM cheer
WHERE store_id = @hotplace_store_id
UNION ALL
SELECT
    '핫플레이스 Story 수',
    COUNT(*)
FROM story
WHERE store_kakao_id = '9999999999'
UNION ALL
SELECT
    '핫플레이스 CheerImage 수',
    COUNT(*)
FROM cheer_image ci
JOIN cheer c ON ci.cheer_id = c.id
WHERE c.store_id = @hotplace_store_id
UNION ALL
SELECT
    '핫플레이스 StoryImage 수',
    COUNT(*)
FROM story_image si
JOIN story s ON si.story_id = s.id
WHERE s.store_kakao_id = '9999999999';

-- 핫플레이스 가게 정보 출력
SELECT
    id,
    name,
    district,
    road_address,
    (SELECT COUNT(*) FROM cheer WHERE store_id = @hotplace_store_id) AS cheer_count,
    (SELECT COUNT(*) FROM story WHERE store_kakao_id = kakao_id) AS story_count
FROM store
WHERE id = @hotplace_store_id;
