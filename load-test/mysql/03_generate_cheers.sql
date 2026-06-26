-- =====================================================
-- 03. Cheer (응원) 대량 생성
-- 목표: 120,000개 추가 (기존 125개 + 120,000개 = 총 120,125개)
-- 시나리오: 초기 서비스 (론칭 후 6개월~1년) - Store당 평균 12개
-- 전략: 롱테일 분포 (상위 5% 가게에 80% 집중)
-- =====================================================

-- 기존 더미 Cheer 삭제 (init.sql의 실제 데이터는 id <= 200 보존)
DELETE FROM cheer WHERE id > 200;

-- 설명 템플릿 배열 (랜덤 선택용)
SET @desc1 = '정말 맛있는 집이에요! 강추합니다.';
SET @desc2 = '분위기도 좋고 음식도 훌륭해요.';
SET @desc3 = '가격 대비 가성비 최고입니다!';
SET @desc4 = '재방문 의사 100% 입니다 ㅎㅎ';
SET @desc5 = '주변에 여기 아는 사람이 별로 없어서 웨이팅 없이 편하게 다녀요~';
SET @desc6 = '친구들이랑 같이 가기 너무 좋아요!';
SET @desc7 = '혼자 먹기에도 부담없는 곳이에요.';
SET @desc8 = '데이트 코스로 완전 추천합니다 💕';
SET @desc9 = '여기만큼 맛있는 곳 찾기 힘들어요.';
SET @desc10 = '사장님이 너무 친절하세요!';

-- Member/Store ID 임시 테이블 (인덱스 포함)
DROP TEMPORARY TABLE IF EXISTS temp_member_pool;
CREATE TEMPORARY TABLE temp_member_pool (
    idx INT AUTO_INCREMENT PRIMARY KEY,
    member_id BIGINT
);
INSERT INTO temp_member_pool (member_id) SELECT id FROM member ORDER BY RAND();

DROP TEMPORARY TABLE IF EXISTS temp_top_store_pool;
CREATE TEMPORARY TABLE temp_top_store_pool (
    idx INT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT
);
INSERT INTO temp_top_store_pool (store_id)
SELECT id FROM store ORDER BY RAND() LIMIT 500;

DROP TEMPORARY TABLE IF EXISTS temp_normal_store_pool;
CREATE TEMPORARY TABLE temp_normal_store_pool (
    idx INT AUTO_INCREMENT PRIMARY KEY,
    store_id BIGINT
);
INSERT INTO temp_normal_store_pool (store_id)
SELECT id FROM store WHERE id NOT IN (SELECT store_id FROM temp_top_store_pool);

SET @member_count = (SELECT COUNT(*) FROM temp_member_pool);
SET @top_store_count = (SELECT COUNT(*) FROM temp_top_store_pool);
SET @normal_store_count = (SELECT COUNT(*) FROM temp_normal_store_pool);

-- 1. 상위 5% 인기 가게에 96,000개 Cheer 생성 (80%)
INSERT INTO cheer (member_id, store_id, description, is_admin, created_at)
SELECT
    m.member_id,
    s.store_id,
    CASE (nums.n % 10)
        WHEN 0 THEN @desc1
        WHEN 1 THEN @desc2
        WHEN 2 THEN @desc3
        WHEN 3 THEN @desc4
        WHEN 4 THEN @desc5
        WHEN 5 THEN @desc6
        WHEN 6 THEN @desc7
        WHEN 7 THEN @desc8
        WHEN 8 THEN @desc9
        ELSE @desc10
    END AS description,
    0 AS is_admin,
    DATE_ADD('2024-01-01', INTERVAL (nums.n % 542) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN information_schema.columns c3
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 96000
) nums
JOIN temp_member_pool m ON m.idx = ((nums.n * 7919) % @member_count) + 1
JOIN temp_top_store_pool s ON s.idx = ((nums.n * 7907) % @top_store_count) + 1;

-- 2. 하위 95% 일반 가게에 24,000개 Cheer 생성 (20%)
INSERT INTO cheer (member_id, store_id, description, is_admin, created_at)
SELECT
    m.member_id,
    s.store_id,
    CASE (nums.n % 10)
        WHEN 0 THEN @desc1
        WHEN 1 THEN @desc2
        WHEN 2 THEN @desc3
        WHEN 3 THEN @desc4
        WHEN 4 THEN @desc5
        WHEN 5 THEN @desc6
        WHEN 6 THEN @desc7
        WHEN 7 THEN @desc8
        WHEN 8 THEN @desc9
        ELSE @desc10
    END AS description,
    0 AS is_admin,
    DATE_ADD('2024-01-01', INTERVAL (nums.n % 542) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 24000
) nums
JOIN temp_member_pool m ON m.idx = ((nums.n * 7919) % @member_count) + 1
JOIN temp_normal_store_pool s ON s.idx = ((nums.n * 7907) % @normal_store_count) + 1;

-- 생성 결과 확인
SELECT
    '총 Cheer 수' AS metric,
    COUNT(*) AS value
FROM cheer
UNION ALL
SELECT
    'Store당 평균 Cheer 수',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM store), 2)
FROM cheer
UNION ALL
SELECT
    'Cheer 최다 보유 Store',
    MAX(cheer_count)
FROM (
    SELECT store_id, COUNT(*) AS cheer_count
    FROM cheer
    GROUP BY store_id
) sub;

-- 상위 10개 인기 가게 확인
SELECT
    s.name,
    s.district,
    COUNT(c.id) AS cheer_count
FROM store s
LEFT JOIN cheer c ON s.id = c.store_id
GROUP BY s.id, s.name, s.district
ORDER BY cheer_count DESC
LIMIT 10;
