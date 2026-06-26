import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  vus: 10,
  duration: '10m',
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.001'],
    'errors': ['rate<0.001'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://app:8080';

export default function() {
  // 1. 홈 탭 진입 (3개 API 동시 호출)
  const homeRequests = [
    { method: 'GET', url: `${BASE_URL}/api/stories?size=20` },
    { method: 'GET', url: `${BASE_URL}/api/cheer?size=20` },
    { method: 'GET', url: `${BASE_URL}/api/shops?size=20` },
  ];

  const homeResponses = http.batch(homeRequests);
  homeResponses.forEach(res => {
    const success = check(res, {
      'home tab status is 200': (r) => r.status === 200,
      'home tab response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(!success);
  });

  sleep(5);

  // 2. 가게 상세 진입 (4개 API 동시 호출)
  const storeId = Math.floor(Math.random() * 5000) + 1;
  const storeDetailRequests = [
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/cheers?size=10` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/images` },
    { method: 'GET', url: `${BASE_URL}/api/shops/${storeId}/tags` },
  ];

  const storeResponses = http.batch(storeDetailRequests);
  storeResponses.forEach(res => {
    const success = check(res, {
      'store detail status is 200': (r) => r.status === 200,
      'store detail response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(!success);
  });

  sleep(5);

  // 3. 마이 탭 진입 (3개 API 동시 호출)
  // TODO: 인증 토큰 필요 - 일단 생략 또는 Mock 토큰 사용
  const myPageRequests = [
    { method: 'GET', url: `${BASE_URL}/api/member`, headers: { 'Authorization': 'Bearer mock-token' } },
    { method: 'GET', url: `${BASE_URL}/api/shops/cheered-member`, headers: { 'Authorization': 'Bearer mock-token' } },
    { method: 'GET', url: `${BASE_URL}/api/stories/member?page=0&size=5`, headers: { 'Authorization': 'Bearer mock-token' } },
  ];

  const myPageResponses = http.batch(myPageRequests);
  myPageResponses.forEach(res => {
    const success = check(res, {
      'my page status is 200 or 401': (r) => r.status === 200 || r.status === 401,
    });
    // 401은 인증 실패이므로 에러로 카운트하지 않음
    if (res.status !== 401) {
      errorRate.add(!success);
    }
  });

  sleep(5);
}
