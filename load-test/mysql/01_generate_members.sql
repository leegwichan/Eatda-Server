-- =====================================================
-- 01. Member (회원) 대량 생성
-- 목표: 50,000명 추가 (기존 80명 + 50,000명 = 총 50,080명)
-- 시나리오: 초기 서비스 (론칭 후 6개월~1년) - 월 평균 4,000~5,000명 가입
-- =====================================================

-- 기존 더미 Member 삭제 (init.sql의 실제 데이터는 id <= 100 보존)
DELETE FROM member WHERE id > 100;

-- 시작 social_id 설정
SET @start_social_id = 4100000000;

-- 활성 사용자 40,000명 생성 (최근 3개월 내 가입)
INSERT INTO member (email, social_id, nickname, phone_number, opt_in_marketing, created_at)
SELECT
    CONCAT('loadtest', n, '@test.com') AS email,
    CAST(@start_social_id + n AS CHAR) AS social_id,
    CONCAT('테스트유저', n) AS nickname,
    CASE
        WHEN n % 3 = 0 THEN NULL
        ELSE CONCAT('010', LPAD(n, 8, '0'))
    END AS phone_number,
    n % 2 AS opt_in_marketing,
    DATE_ADD('2025-04-01', INTERVAL FLOOR(RAND() * 87) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN information_schema.columns c3
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 40000
) nums;

-- 휴면 사용자 10,000명 생성 (3개월 이상 경과)
INSERT INTO member (email, social_id, nickname, phone_number, opt_in_marketing, created_at)
SELECT
    CONCAT('dormant', n, '@test.com') AS email,
    CAST(@start_social_id + 40000 + n AS CHAR) AS social_id,
    CONCAT('휴면유저', n) AS nickname,
    CASE
        WHEN n % 3 = 0 THEN NULL
        ELSE CONCAT('010', LPAD(40000 + n, 8, '0'))
    END AS phone_number,
    n % 2 AS opt_in_marketing,
    DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND() * 455) DAY) AS created_at
FROM (
    SELECT @row := @row + 1 AS n
    FROM information_schema.columns c1
    CROSS JOIN information_schema.columns c2
    CROSS JOIN (SELECT @row := 0) r
    LIMIT 10000
) nums;

-- 생성 결과 확인
SELECT
    '총 회원 수' AS metric,
    COUNT(*) AS value
FROM member
UNION ALL
SELECT
    '활성 사용자 (최근 3개월)',
    COUNT(*)
FROM member
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 3 MONTH)
UNION ALL
SELECT
    '휴면 사용자 (3개월 이상)',
    COUNT(*)
FROM member
WHERE created_at < DATE_SUB(NOW(), INTERVAL 3 MONTH);
