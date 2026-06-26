-- =====================================================
-- 05. CheerTag (응원 태그) 대량 생성
-- 목표: 평균 Cheer당 2.5개 = 약 300,000개
-- 전략: 각 Cheer마다 1~4개 랜덤 생성 (중복 없음)
-- UNIQUE KEY: (cheer_id, name) - 같은 Cheer에 동일한 태그는 불가
-- =====================================================

-- 기존 더미 CheerTag 삭제 (init.sql의 실제 데이터는 cheer_id <= 200 보존)
DELETE FROM cheer_tag WHERE cheer_id > 200;

-- 태그 목록 (15개 - CheerTagName enum 기준)
-- GOOD_FOR_DRINKING, NEAR_SUBWAY, GOOD_FOR_DATING, INSTAGRAMMABLE,
-- ENERGETIC, GROUP_RESERVATION, MANY_NEARBY_ATTRACTIONS, CLEAN_RESTROOM,
-- QUIET, GOOD_FOR_FAMILY, LATE_NIGHT, OLD_STORE_MOOD, YOUTUBE_FAMOUS,
-- LARGE_PARKING, PET_FRIENDLY

-- =====================================================
-- 1. 모든 Cheer에 첫 번째 태그 추가 (가중치 반영)
-- =====================================================
INSERT INTO cheer_tag (cheer_id, name)
SELECT
    c.id AS cheer_id,
    CASE MOD(c.id, 100)
        WHEN 0 THEN 'GOOD_FOR_DRINKING'
        WHEN 1 THEN 'GOOD_FOR_DRINKING'
        WHEN 2 THEN 'GOOD_FOR_DRINKING'
        WHEN 3 THEN 'GOOD_FOR_DRINKING'
        WHEN 4 THEN 'GOOD_FOR_DRINKING'
        WHEN 5 THEN 'NEAR_SUBWAY'
        WHEN 6 THEN 'NEAR_SUBWAY'
        WHEN 7 THEN 'NEAR_SUBWAY'
        WHEN 8 THEN 'NEAR_SUBWAY'
        WHEN 9 THEN 'GOOD_FOR_DATING'
        WHEN 10 THEN 'GOOD_FOR_DATING'
        WHEN 11 THEN 'GOOD_FOR_DATING'
        WHEN 12 THEN 'INSTAGRAMMABLE'
        WHEN 13 THEN 'INSTAGRAMMABLE'
        WHEN 14 THEN 'ENERGETIC'
        WHEN 15 THEN 'ENERGETIC'
        WHEN 16 THEN 'GROUP_RESERVATION'
        WHEN 17 THEN 'MANY_NEARBY_ATTRACTIONS'
        WHEN 18 THEN 'CLEAN_RESTROOM'
        WHEN 19 THEN 'QUIET'
        WHEN 20 THEN 'GOOD_FOR_FAMILY'
        WHEN 21 THEN 'LATE_NIGHT'
        WHEN 22 THEN 'OLD_STORE_MOOD'
        WHEN 23 THEN 'YOUTUBE_FAMOUS'
        WHEN 24 THEN 'LARGE_PARKING'
        ELSE CASE MOD(c.id, 15)
            WHEN 0 THEN 'GOOD_FOR_DRINKING'
            WHEN 1 THEN 'NEAR_SUBWAY'
            WHEN 2 THEN 'GOOD_FOR_DATING'
            WHEN 3 THEN 'INSTAGRAMMABLE'
            WHEN 4 THEN 'ENERGETIC'
            WHEN 5 THEN 'GROUP_RESERVATION'
            WHEN 6 THEN 'MANY_NEARBY_ATTRACTIONS'
            WHEN 7 THEN 'CLEAN_RESTROOM'
            WHEN 8 THEN 'QUIET'
            WHEN 9 THEN 'GOOD_FOR_FAMILY'
            WHEN 10 THEN 'LATE_NIGHT'
            WHEN 11 THEN 'OLD_STORE_MOOD'
            WHEN 12 THEN 'YOUTUBE_FAMOUS'
            WHEN 13 THEN 'LARGE_PARKING'
            ELSE 'PET_FRIENDLY'
        END
    END AS name
FROM cheer c;

-- =====================================================
-- 2. Cheer의 80%에 두 번째 태그 추가 (첫 번째와 다른 태그)
-- =====================================================
INSERT INTO cheer_tag (cheer_id, name)
SELECT
    c.id AS cheer_id,
    CASE MOD(c.id + 7, 15)  -- offset을 더해서 첫 번째 태그와 달라지도록
        WHEN 0 THEN 'NEAR_SUBWAY'
        WHEN 1 THEN 'GOOD_FOR_DATING'
        WHEN 2 THEN 'INSTAGRAMMABLE'
        WHEN 3 THEN 'ENERGETIC'
        WHEN 4 THEN 'GROUP_RESERVATION'
        WHEN 5 THEN 'MANY_NEARBY_ATTRACTIONS'
        WHEN 6 THEN 'CLEAN_RESTROOM'
        WHEN 7 THEN 'QUIET'
        WHEN 8 THEN 'GOOD_FOR_FAMILY'
        WHEN 9 THEN 'LATE_NIGHT'
        WHEN 10 THEN 'OLD_STORE_MOOD'
        WHEN 11 THEN 'YOUTUBE_FAMOUS'
        WHEN 12 THEN 'LARGE_PARKING'
        WHEN 13 THEN 'PET_FRIENDLY'
        ELSE 'GOOD_FOR_DRINKING'
    END AS name
FROM cheer c
WHERE MOD(c.id, 10) < 8  -- 80%
  AND NOT EXISTS (
    SELECT 1 FROM cheer_tag ct
    WHERE ct.cheer_id = c.id
    AND ct.name = CASE MOD(c.id + 7, 15)
        WHEN 0 THEN 'NEAR_SUBWAY'
        WHEN 1 THEN 'GOOD_FOR_DATING'
        WHEN 2 THEN 'INSTAGRAMMABLE'
        WHEN 3 THEN 'ENERGETIC'
        WHEN 4 THEN 'GROUP_RESERVATION'
        WHEN 5 THEN 'MANY_NEARBY_ATTRACTIONS'
        WHEN 6 THEN 'CLEAN_RESTROOM'
        WHEN 7 THEN 'QUIET'
        WHEN 8 THEN 'GOOD_FOR_FAMILY'
        WHEN 9 THEN 'LATE_NIGHT'
        WHEN 10 THEN 'OLD_STORE_MOOD'
        WHEN 11 THEN 'YOUTUBE_FAMOUS'
        WHEN 12 THEN 'LARGE_PARKING'
        WHEN 13 THEN 'PET_FRIENDLY'
        ELSE 'GOOD_FOR_DRINKING'
    END
);

-- =====================================================
-- 3. Cheer의 50%에 세 번째 태그 추가
-- =====================================================
INSERT INTO cheer_tag (cheer_id, name)
SELECT
    c.id AS cheer_id,
    CASE MOD(c.id + 13, 15)  -- 또 다른 offset
        WHEN 0 THEN 'INSTAGRAMMABLE'
        WHEN 1 THEN 'ENERGETIC'
        WHEN 2 THEN 'GROUP_RESERVATION'
        WHEN 3 THEN 'MANY_NEARBY_ATTRACTIONS'
        WHEN 4 THEN 'CLEAN_RESTROOM'
        WHEN 5 THEN 'QUIET'
        WHEN 6 THEN 'GOOD_FOR_FAMILY'
        WHEN 7 THEN 'LATE_NIGHT'
        WHEN 8 THEN 'OLD_STORE_MOOD'
        WHEN 9 THEN 'YOUTUBE_FAMOUS'
        WHEN 10 THEN 'LARGE_PARKING'
        WHEN 11 THEN 'PET_FRIENDLY'
        WHEN 12 THEN 'GOOD_FOR_DRINKING'
        WHEN 13 THEN 'NEAR_SUBWAY'
        ELSE 'GOOD_FOR_DATING'
    END AS name
FROM cheer c
WHERE MOD(c.id, 2) = 0  -- 50%
  AND NOT EXISTS (
    SELECT 1 FROM cheer_tag ct
    WHERE ct.cheer_id = c.id
    AND ct.name = CASE MOD(c.id + 13, 15)
        WHEN 0 THEN 'INSTAGRAMMABLE'
        WHEN 1 THEN 'ENERGETIC'
        WHEN 2 THEN 'GROUP_RESERVATION'
        WHEN 3 THEN 'MANY_NEARBY_ATTRACTIONS'
        WHEN 4 THEN 'CLEAN_RESTROOM'
        WHEN 5 THEN 'QUIET'
        WHEN 6 THEN 'GOOD_FOR_FAMILY'
        WHEN 7 THEN 'LATE_NIGHT'
        WHEN 8 THEN 'OLD_STORE_MOOD'
        WHEN 9 THEN 'YOUTUBE_FAMOUS'
        WHEN 10 THEN 'LARGE_PARKING'
        WHEN 11 THEN 'PET_FRIENDLY'
        WHEN 12 THEN 'GOOD_FOR_DRINKING'
        WHEN 13 THEN 'NEAR_SUBWAY'
        ELSE 'GOOD_FOR_DATING'
    END
);

-- =====================================================
-- 4. Cheer의 20%에 네 번째 태그 추가
-- =====================================================
INSERT INTO cheer_tag (cheer_id, name)
SELECT
    c.id AS cheer_id,
    CASE MOD(c.id + 19, 15)  -- 또 다른 offset
        WHEN 0 THEN 'CLEAN_RESTROOM'
        WHEN 1 THEN 'QUIET'
        WHEN 2 THEN 'GOOD_FOR_FAMILY'
        WHEN 3 THEN 'LATE_NIGHT'
        WHEN 4 THEN 'OLD_STORE_MOOD'
        WHEN 5 THEN 'YOUTUBE_FAMOUS'
        WHEN 6 THEN 'LARGE_PARKING'
        WHEN 7 THEN 'PET_FRIENDLY'
        WHEN 8 THEN 'GOOD_FOR_DRINKING'
        WHEN 9 THEN 'NEAR_SUBWAY'
        WHEN 10 THEN 'GOOD_FOR_DATING'
        WHEN 11 THEN 'INSTAGRAMMABLE'
        WHEN 12 THEN 'ENERGETIC'
        WHEN 13 THEN 'GROUP_RESERVATION'
        ELSE 'MANY_NEARBY_ATTRACTIONS'
    END AS name
FROM cheer c
WHERE MOD(c.id, 10) < 2  -- 20%
  AND NOT EXISTS (
    SELECT 1 FROM cheer_tag ct
    WHERE ct.cheer_id = c.id
    AND ct.name = CASE MOD(c.id + 19, 15)
        WHEN 0 THEN 'CLEAN_RESTROOM'
        WHEN 1 THEN 'QUIET'
        WHEN 2 THEN 'GOOD_FOR_FAMILY'
        WHEN 3 THEN 'LATE_NIGHT'
        WHEN 4 THEN 'OLD_STORE_MOOD'
        WHEN 5 THEN 'YOUTUBE_FAMOUS'
        WHEN 6 THEN 'LARGE_PARKING'
        WHEN 7 THEN 'PET_FRIENDLY'
        WHEN 8 THEN 'GOOD_FOR_DRINKING'
        WHEN 9 THEN 'NEAR_SUBWAY'
        WHEN 10 THEN 'GOOD_FOR_DATING'
        WHEN 11 THEN 'INSTAGRAMMABLE'
        WHEN 12 THEN 'ENERGETIC'
        WHEN 13 THEN 'GROUP_RESERVATION'
        ELSE 'MANY_NEARBY_ATTRACTIONS'
    END
);

-- =====================================================
-- 생성 결과 확인
-- =====================================================
SELECT
    '총 CheerTag 수' AS metric,
    COUNT(*) AS value
FROM cheer_tag
UNION ALL
SELECT
    'Cheer당 평균 태그 수',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM cheer), 2)
FROM cheer_tag
UNION ALL
SELECT
    '태그 1개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_tag
    GROUP BY cheer_id
    HAVING COUNT(*) = 1
) t
UNION ALL
SELECT
    '태그 2개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_tag
    GROUP BY cheer_id
    HAVING COUNT(*) = 2
) t
UNION ALL
SELECT
    '태그 3개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_tag
    GROUP BY cheer_id
    HAVING COUNT(*) = 3
) t
UNION ALL
SELECT
    '태그 4개인 Cheer',
    COUNT(*)
FROM (
    SELECT cheer_id
    FROM cheer_tag
    GROUP BY cheer_id
    HAVING COUNT(*) = 4
) t;

-- 태그별 사용 빈도 상위 10개
SELECT
    name,
    COUNT(*) AS count,
    CONCAT(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cheer_tag), 1), '%') AS percentage
FROM cheer_tag
GROUP BY name
ORDER BY count DESC
LIMIT 10;
