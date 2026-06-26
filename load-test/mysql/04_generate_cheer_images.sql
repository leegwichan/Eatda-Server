-- =====================================================
-- 04. CheerImage (응원 이미지) 대량 생성
-- 목표: 평균 Cheer당 1.5개 = 약 180,000개
-- 전략: 각 Cheer마다 0~3개 랜덤 생성
-- UNIQUE KEY: (cheer_id, order_index) - 같은 Cheer에 동일한 order_index는 불가
-- =====================================================

-- 기존 CheerImage 삭제 (재실행 대비)
DELETE FROM cheer_image;

-- Cheer ID 범위 확인
SET @min_cheer_id = (SELECT MIN(id) FROM cheer);
SET @max_cheer_id = (SELECT MAX(id) FROM cheer);

-- 1. Cheer의 70%에 이미지 1개 생성 (order_index = 0)
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    c.id AS cheer_id,
    CONCAT('cheer/', c.id, '/', UUID(), '.jpeg') AS image_key,
    0 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer c
WHERE MOD(c.id, 10) < 7;  -- 70% (ID % 10이 0~6인 경우)

-- 2. order_index=0이 있는 Cheer 중 40%에 이미지 2개째 추가 (order_index = 1)
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    ci.cheer_id,
    CONCAT('cheer/', ci.cheer_id, '/', UUID(), '.jpeg') AS image_key,
    1 AS order_index,
    CASE WHEN MOD(ci.cheer_id, 10) < 9 THEN 'image/jpeg' ELSE 'image/png' END AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer_image ci
INNER JOIN cheer c ON c.id = ci.cheer_id
WHERE ci.order_index = 0
  AND MOD(ci.cheer_id, 10) < 4;  -- 40% (0~3)

-- 3. order_index=1이 있는 Cheer 중 50%에 이미지 3개째 추가 (order_index = 2)
INSERT INTO cheer_image (cheer_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    ci.cheer_id,
    CONCAT('cheer/', ci.cheer_id, '/', UUID(), '.jpeg') AS image_key,
    2 AS order_index,
    CASE WHEN MOD(ci.cheer_id, 10) < 9 THEN 'image/jpeg' ELSE 'image/png' END AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    c.created_at
FROM cheer_image ci
INNER JOIN cheer c ON c.id = ci.cheer_id
WHERE ci.order_index = 1
  AND MOD(ci.cheer_id, 2) = 0;  -- 50%

-- 생성 결과 확인
SELECT
    '총 CheerImage 수' AS metric,
    COUNT(*) AS value
FROM cheer_image
UNION ALL
SELECT
    'Cheer당 평균 이미지 수',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM cheer), 2)
FROM cheer_image
UNION ALL
SELECT
    'image/jpeg 비율',
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cheer_image), 1), '%')
FROM cheer_image
WHERE content_type = 'image/jpeg'
UNION ALL
SELECT
    'image/png 비율',
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cheer_image), 1), '%')
FROM cheer_image
WHERE content_type = 'image/png'
UNION ALL
SELECT
    '이미지 0개인 Cheer',
    COUNT(*)
FROM cheer c
WHERE NOT EXISTS (SELECT 1 FROM cheer_image ci WHERE ci.cheer_id = c.id)
UNION ALL
SELECT
    '이미지 1개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_image
    GROUP BY cheer_id
    HAVING COUNT(*) = 1
) t
UNION ALL
SELECT
    '이미지 2개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_image
    GROUP BY cheer_id
    HAVING COUNT(*) = 2
) t
UNION ALL
SELECT
    '이미지 3개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_image
    GROUP BY cheer_id
    HAVING COUNT(*) = 3
) t;
