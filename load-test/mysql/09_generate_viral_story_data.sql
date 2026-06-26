-- =====================================================
-- 09. 바이럴 스토리 데이터 생성 (시나리오 3)
-- 목표: 특정 story_id 1개를 SNS 바이럴용으로 준비
-- =====================================================

-- 바이럴용 Store 생성 (망원동 인기 카페)
INSERT INTO store (kakao_id, category, phone_number, name, place_url, road_address, lot_number_address, district, latitude, longitude, created_at)
VALUES (
    '8888888888',
    'CAFE',
    '02-9876-5432',
    '망원동 바이럴 테스트 카페',
    'http://place.map.kakao.com/8888888888',
    '서울 마포구 월드컵로 456',
    '서울 마포구 망원동 789',
    'MAPO',
    37.5562,
    126.9102,
    NOW()
);

-- 방금 생성한 Store의 ID 저장
SET @viral_store_id = LAST_INSERT_ID();

-- 인기 있는 Member 선택 (활성 사용자 중 랜덤, 없으면 아무 Member나)
SET @viral_member_id = COALESCE(
    (SELECT id FROM member WHERE created_at >= DATE_SUB(NOW(), INTERVAL 3 MONTH) ORDER BY RAND() LIMIT 1),
    (SELECT id FROM member ORDER BY RAND() LIMIT 1)
);

-- 바이럴 Story 생성 (감성적이고 공감 가는 내용)
INSERT INTO story (member_id, store_kakao_id, store_name, store_road_address, store_lot_number_address, store_category, description, created_at)
SELECT
    @viral_member_id,
    s.kakao_id,
    s.name,
    s.road_address,
    s.lot_number_address,
    s.category,
    '망원동 숨은 보석 카페 발견...! 💎\n\n우연히 산책하다가 들어간 곳인데, 진짜 인생 카페 등극했어요.\n창가 자리에 앉아서 망원시장 풍경 바라보면서 마시는 커피 한 잔... 이게 바로 힐링이구나 싶었습니다 ☕️\n\n특히 시그니처 라떼가 진짜 미쳤어요. 달지 않고 고소하면서도 커피 향이 확 올라와요.\n사장님도 너무 친절하시고, 인테리어도 빈티지 감성 제대로입니다.\n\n평일 오후 3시쯤 가면 한산해서 조용히 책 읽기 딱 좋아요 📚\n주말에는 사람 많을 것 같으니 평일 추천드립니다!\n\n📍 위치: 망원역 2번 출구 도보 5분\n💰 가격: 아메리카노 4,500원 / 시그니처 라떼 6,000원\n⏰ 영업: 11:00 - 22:00 (월요일 휴무)\n\n#망원동카페 #힐링카페 #인생카페 #망원역맛집',
    DATE_ADD('2026-06-01', INTERVAL FLOOR(RAND() * 25) DAY)
FROM store s
WHERE s.id = @viral_store_id;

-- 방금 생성한 Story ID 저장
SET @viral_story_id = LAST_INSERT_ID();

-- 바이럴 Story에 이미지 4개 추가 (최대치)
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
VALUES
    (@viral_story_id, CONCAT('story/', @viral_story_id, '/', UUID(), '.jpeg'), 0, 'image/jpeg', 3500000, NOW()),
    (@viral_story_id, CONCAT('story/', @viral_story_id, '/', UUID(), '.jpeg'), 1, 'image/jpeg', 2800000, NOW()),
    (@viral_story_id, CONCAT('story/', @viral_story_id, '/', UUID(), '.jpeg'), 2, 'image/jpeg', 4100000, NOW()),
    (@viral_story_id, CONCAT('story/', @viral_story_id, '/', UUID(), '.jpeg'), 3, 'image/jpeg', 3200000, NOW());

-- 바이럴 Story의 Store에 Cheer 추가 (인기 증명)
-- Member ID 목록을 임시 테이블로 생성 (FK 제약 조건 만족)
DROP TEMPORARY TABLE IF EXISTS member_ids;
CREATE TEMPORARY TABLE member_ids AS
SELECT id AS member_id FROM member;

-- 바이럴 효과로 Cheer 100개 추가
-- 임시 테이블에 랜덤 Member 미리 생성
DROP TEMPORARY TABLE IF EXISTS temp_viral_members;
CREATE TEMPORARY TABLE temp_viral_members (idx INT AUTO_INCREMENT PRIMARY KEY, member_id BIGINT);
INSERT INTO temp_viral_members (member_id) SELECT id FROM member ORDER BY RAND() LIMIT 100;

INSERT INTO cheer (member_id, store_id, description, is_admin, created_at)
SELECT
    m.member_id,
    @viral_store_id AS store_id,
    CASE (nums.n % 10)
        WHEN 0 THEN '그 리뷰 보고 왔는데 진짜 맛집이네요!'
        WHEN 1 THEN 'SNS에서 보고 찾아왔어요. 기대 이상입니다!'
        WHEN 2 THEN '바이럴인 줄 알았는데 진짜 찐맛집이에요 ㄷㄷ'
        WHEN 3 THEN '망원동 숨은 보석 맞네요. 분위기 최고!'
        WHEN 4 THEN '카톡방에서 공유받고 왔는데 후회 없어요'
        WHEN 5 THEN '인스타 감성 제대로네요. 사진 찍기 좋아요'
        WHEN 6 THEN '그 리뷰 덕분에 인생 카페 찾았습니다 ㅠㅠ'
        WHEN 7 THEN '친구한테 추천받고 왔는데 완전 취저예요'
        WHEN 8 THEN '평일 오후에 가니까 한산하고 좋았어요'
        ELSE '여기 진짜 힐링 카페입니다. 자주 올 것 같아요'
    END AS description,
    0 AS is_admin,
    DATE_ADD('2026-06-01', INTERVAL (nums.n % 25) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 100
) nums
JOIN temp_viral_members m ON m.idx = nums.n;

-- 바이럴 효과로 추가된 Cheer에 이미지 추가
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    c.id AS cheer_id,
    CONCAT('cheer/', c.id, '/', UUID(), '.jpeg') AS image_key,
    0 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer c
WHERE c.store_id = @viral_store_id
AND c.id > (SELECT MAX(id) FROM cheer WHERE store_id = @viral_store_id) - 100;

-- 바이럴 Cheer에 태그 추가
INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'INSTAGRAMMABLE' FROM cheer c WHERE c.store_id = @viral_store_id AND c.id > (SELECT MAX(id) FROM cheer WHERE store_id = @viral_store_id) - 100;

INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'QUIET' FROM cheer c WHERE c.store_id = @viral_store_id AND c.id > (SELECT MAX(id) FROM cheer WHERE store_id = @viral_store_id) - 100 AND RAND() < 0.7;

INSERT INTO cheer_tag (cheer_id, name)
SELECT c.id, 'GOOD_FOR_DATING' FROM cheer c WHERE c.store_id = @viral_store_id AND c.id > (SELECT MAX(id) FROM cheer WHERE store_id = @viral_store_id) - 100 AND RAND() < 0.5;

-- 생성 결과 확인
SELECT
    '바이럴 Story ID' AS metric,
    @viral_story_id AS value
UNION ALL
SELECT
    '바이럴 Store ID',
    @viral_store_id
UNION ALL
SELECT
    '바이럴 Story 이미지 수',
    COUNT(*)
FROM story_image
WHERE story_id = @viral_story_id
UNION ALL
SELECT
    '바이럴 효과 Cheer 수',
    COUNT(*)
FROM cheer
WHERE store_id = @viral_store_id
UNION ALL
SELECT
    '바이럴 효과 CheerImage 수',
    COUNT(*)
FROM cheer_image ci
JOIN cheer c ON ci.cheer_id = c.id
WHERE c.store_id = @viral_store_id;

-- 바이럴 Story 정보 출력
SELECT
    s.id AS story_id,
    s.store_name,
    m.nickname AS author,
    LEFT(s.description, 100) AS description_preview,
    s.created_at,
    (SELECT COUNT(*) FROM story_image WHERE story_id = s.id) AS image_count
FROM story s
JOIN member m ON s.member_id = m.id
WHERE s.id = @viral_story_id;

-- 바이럴 Store 정보 출력
SELECT
    st.id AS store_id,
    st.name,
    st.district,
    st.road_address,
    (SELECT COUNT(*) FROM cheer WHERE store_id = st.id) AS cheer_count,
    (SELECT COUNT(*) FROM story WHERE store_kakao_id = st.kakao_id) AS story_count
FROM store st
WHERE st.id = @viral_store_id;
