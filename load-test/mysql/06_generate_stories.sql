-- =====================================================
-- 06. Story (스토리) 대량 생성
-- 목표: 30,000개 추가 (기존 24개 + 30,000개 = 총 30,024개)
-- 시나리오: 초기 서비스 (론칭 후 6개월~1년) - Member당 평균 0.6개
-- 전략: 파워 유저(5%)가 다수 작성, 일반 유저는 소수 작성
-- =====================================================

-- 기존 더미 Story 삭제 (init.sql의 실제 데이터는 id <= 50 보존)
DELETE FROM story WHERE id > 50;

-- Store 데이터 조회를 위한 준비
-- (Story는 store_kakao_id, store_name 등을 직접 저장)

-- 파워 유저 목록 생성 (임시 테이블)
-- 예상 Member 개수: ~50,000명 → 5% = ~2,500명
DROP TEMPORARY TABLE IF EXISTS power_users;
CREATE TEMPORARY TABLE power_users AS
SELECT id AS member_id
FROM member
ORDER BY RAND()
LIMIT 2500;

-- 일반 유저 목록 생성 (임시 테이블)
DROP TEMPORARY TABLE IF EXISTS normal_users;
CREATE TEMPORARY TABLE normal_users AS
SELECT id AS member_id
FROM member
WHERE id NOT IN (SELECT member_id FROM power_users);

-- Story 설명 템플릿
SET @story_desc1 = '오늘 다녀온 맛집인데 정말 최고였어요!';
SET @story_desc2 = '분위기 좋고 맛도 좋아서 데이트 코스로 추천합니다.';
SET @story_desc3 = '가성비 갑! 다음에 또 올 거예요.';
SET @story_desc4 = '친구들이랑 왔는데 다들 맛있다고 난리였어요 ㅎㅎ';
SET @story_desc5 = '주말에 웨이팅 좀 있었지만 기다릴 만한 가치가 있었습니다.';
SET @story_desc6 = '사진보다 실물이 훨씬 이쁘고 맛있어요!';
SET @story_desc7 = '여기 숨은 맛집이에요. 많이들 오세요~';
SET @story_desc8 = '평일 점심에 갔는데 한산해서 좋았습니다.';
SET @story_desc9 = '재방문 의사 200%! 다음엔 다른 메뉴도 먹어봐야겠어요.';
SET @story_desc10 = '인스타 감성 제대로! 사진 찍기 좋은 곳이에요.';

-- 1. 파워 유저(5%)가 15,000개 Story 작성 (50%)
INSERT INTO story (member_id, store_kakao_id, store_name, store_road_address, store_lot_number_address, store_category, description, created_at)
SELECT
    (SELECT member_id FROM power_users ORDER BY RAND() LIMIT 1) AS member_id,
    s.kakao_id AS store_kakao_id,
    s.name AS store_name,
    s.road_address AS store_road_address,
    s.lot_number_address AS store_lot_number_address,
    s.category AS store_category,
    CASE FLOOR(RAND() * 10)
        WHEN 0 THEN @story_desc1
        WHEN 1 THEN @story_desc2
        WHEN 2 THEN @story_desc3
        WHEN 3 THEN @story_desc4
        WHEN 4 THEN @story_desc5
        WHEN 5 THEN @story_desc6
        WHEN 6 THEN @story_desc7
        WHEN 7 THEN @story_desc8
        WHEN 8 THEN @story_desc9
        ELSE @story_desc10
    END AS description,
    DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND() * 542) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 15000
) nums
CROSS JOIN (
    SELECT * FROM store ORDER BY RAND() LIMIT 1
) s;

-- 2. 일반 유저(95%)가 15,000개 Story 작성 (50%)
INSERT INTO story (member_id, store_kakao_id, store_name, store_road_address, store_lot_number_address, store_category, description, created_at)
SELECT
    (SELECT member_id FROM normal_users ORDER BY RAND() LIMIT 1) AS member_id,
    s.kakao_id AS store_kakao_id,
    s.name AS store_name,
    s.road_address AS store_road_address,
    s.lot_number_address AS store_lot_number_address,
    s.category AS store_category,
    CASE FLOOR(RAND() * 10)
        WHEN 0 THEN @story_desc1
        WHEN 1 THEN @story_desc2
        WHEN 2 THEN @story_desc3
        WHEN 3 THEN @story_desc4
        WHEN 4 THEN @story_desc5
        WHEN 5 THEN @story_desc6
        WHEN 6 THEN @story_desc7
        WHEN 7 THEN @story_desc8
        WHEN 8 THEN @story_desc9
        ELSE @story_desc10
    END AS description,
    DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND() * 542) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 15000
) nums
CROSS JOIN (
    SELECT * FROM store ORDER BY RAND() LIMIT 1
) s;

-- 생성 결과 확인
SELECT
    '총 Story 수' AS metric,
    COUNT(*) AS value
FROM story
UNION ALL
SELECT
    'Member당 평균 Story 수',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM member), 2)
FROM story
UNION ALL
SELECT
    'Story 최다 작성 Member',
    MAX(story_count)
FROM (
    SELECT member_id, COUNT(*) AS story_count
    FROM story
    GROUP BY member_id
) sub;

-- 상위 10명 파워 유저 확인
SELECT
    m.nickname,
    COUNT(s.id) AS story_count
FROM member m
LEFT JOIN story s ON m.id = s.member_id
GROUP BY m.id, m.nickname
ORDER BY story_count DESC
LIMIT 10;
