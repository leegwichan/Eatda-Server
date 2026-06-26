-- =====================================================
-- 07. StoryImage (스토리 이미지) 대량 생성
-- 목표: 평균 Story당 2개 = 약 60,000개
-- 전략: 각 Story마다 1~4개 랜덤 생성
-- UNIQUE KEY: (story_id, order_index) - 같은 Story에 동일한 order_index는 불가
-- =====================================================

-- 기존 더미 StoryImage 삭제 (init.sql의 실제 데이터는 story_id <= 50 보존)
DELETE FROM story_image WHERE story_id > 50;

-- Story ID 범위 확인
SET @min_story_id = (SELECT MIN(id) FROM story);
SET @max_story_id = (SELECT MAX(id) FROM story);

-- 1. 모든 Story에 첫 번째 이미지 생성 (필수, order_index = 0)
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    s.id AS story_id,
    CONCAT('story/', s.id, '/', UUID(), '.jpeg') AS image_key,
    0 AS order_index,
    'image/jpeg' AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story s;

-- 2. order_index=0이 있는 Story 중 70%에 두 번째 이미지 추가 (order_index = 1)
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    si.story_id,
    CONCAT('story/', si.story_id, '/', UUID(), '.jpeg') AS image_key,
    1 AS order_index,
    CASE WHEN MOD(si.story_id, 10) < 9 THEN 'image/jpeg' ELSE 'image/png' END AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story_image si
INNER JOIN story s ON s.id = si.story_id
WHERE si.order_index = 0
  AND MOD(si.story_id, 10) < 7;  -- 70%

-- 3. order_index=1이 있는 Story 중 43%에 세 번째 이미지 추가 (order_index = 2)
-- 전체의 70% * 43% ≈ 30%
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    si.story_id,
    CONCAT('story/', si.story_id, '/', UUID(), '.jpeg') AS image_key,
    2 AS order_index,
    CASE WHEN MOD(si.story_id, 10) < 9 THEN 'image/jpeg' ELSE 'image/png' END AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story_image si
INNER JOIN story s ON s.id = si.story_id
WHERE si.order_index = 1
  AND MOD(si.story_id, 10) < 4;  -- 약 40-43%

-- 4. order_index=2가 있는 Story 중 33%에 네 번째 이미지 추가 (order_index = 3, 최대 4개)
-- 전체의 30% * 33% ≈ 10%
INSERT INTO story_image (story_id, image_key, order_index, content_type, file_size, created_at)
SELECT
    si.story_id,
    CONCAT('story/', si.story_id, '/', UUID(), '.jpeg') AS image_key,
    3 AS order_index,
    CASE WHEN MOD(si.story_id, 10) < 9 THEN 'image/jpeg' ELSE 'image/png' END AS content_type,
    500000 + FLOOR(RAND() * 4500000) AS file_size,
    s.created_at
FROM story_image si
INNER JOIN story s ON s.id = si.story_id
WHERE si.order_index = 2
  AND MOD(si.story_id, 3) = 0;  -- 약 33%

-- 생성 결과 확인
SELECT
    '총 StoryImage 수' AS metric,
    COUNT(*) AS value
FROM story_image
UNION ALL
SELECT
    'Story당 평균 이미지 수',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM story), 2)
FROM story_image
UNION ALL
SELECT
    'image/jpeg 비율',
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM story_image), 1), '%')
FROM story_image
WHERE content_type = 'image/jpeg'
UNION ALL
SELECT
    'image/png 비율',
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM story_image), 1), '%')
FROM story_image
WHERE content_type = 'image/png'
UNION ALL
SELECT
    '이미지 1개인 Story',
    COUNT(*)
FROM (
    SELECT story_id
    FROM story_image
    GROUP BY story_id
    HAVING COUNT(*) = 1
) t
UNION ALL
SELECT
    '이미지 2개인 Story',
    COUNT(*)
FROM (
    SELECT story_id
    FROM story_image
    GROUP BY story_id
    HAVING COUNT(*) = 2
) t
UNION ALL
SELECT
    '이미지 3개인 Story',
    COUNT(*)
FROM (
    SELECT story_id
    FROM story_image
    GROUP BY story_id
    HAVING COUNT(*) = 3
) t
UNION ALL
SELECT
    '이미지 4개인 Story',
    COUNT(*)
FROM (
    SELECT story_id
    FROM story_image
    GROUP BY story_id
    HAVING COUNT(*) = 4
) t;
