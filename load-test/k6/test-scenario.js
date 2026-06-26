import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const requestCounter = new Counter('requests');

// Configuration
export const options = {
  scenarios: {
    // Smoke test - minimal load
    smoke: {
      executor: 'constant-vus',
      vus: 1,
      duration: '1m',
      tags: { test_type: 'smoke' },
      exec: 'smokeTest',
    },
    // Load test - normal expected load
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },   // Ramp up
        { duration: '5m', target: 50 },   // Stay at 50 users
        { duration: '2m', target: 100 },  // Ramp up
        { duration: '5m', target: 100 },  // Stay at 100 users
        { duration: '2m', target: 0 },    // Ramp down
      ],
      tags: { test_type: 'load' },
      exec: 'loadTest',
    },
    // Stress test - beyond normal load
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '2m', target: 200 },
        { duration: '5m', target: 200 },
        { duration: '2m', target: 300 },
        { duration: '5m', target: 300 },
        { duration: '2m', target: 0 },
      ],
      tags: { test_type: 'stress' },
      exec: 'stressTest',
    },
    // Spike test - sudden traffic increase
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 500 },  // Quick ramp up
        { duration: '1m', target: 500 },   // Stay at peak
        { duration: '10s', target: 0 },    // Quick ramp down
      ],
      tags: { test_type: 'spike' },
      exec: 'spikeTest',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],  // 95% < 500ms, 99% < 1s
    http_req_failed: ['rate<0.01'],  // Error rate < 1%
    errors: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://app:8080';

// Test data
const testMembers = [];
const testStores = [];
const testTokens = [];

// Setup - runs once before tests
export function setup() {
  console.log('Setting up test data...');

  // In real scenario, you'd fetch or generate proper test data
  return {
    baseUrl: BASE_URL,
    memberCount: 100,
    storeCount: 100,
  };
}

// Smoke Test - Basic functionality check
export function smokeTest(data) {
  const responses = http.batch([
    ['GET', `${BASE_URL}/actuator/health`],
    ['GET', `${BASE_URL}/docs/swagger`],
  ]);

  responses.forEach(response => {
    const success = check(response, {
      'status is 200': (r) => r.status === 200,
    });
    errorRate.add(!success);
    requestCounter.add(1);
  });

  sleep(1);
}

// Load Test - Simulate typical user behavior
export function loadTest(data) {
  // Scenario 1: Browse stores (80% of traffic)
  if (Math.random() < 0.8) {
    browseStores(data);
  }
  // Scenario 2: Create cheer (15% of traffic)
  else if (Math.random() < 0.95) {
    createCheer(data);
  }
  // Scenario 3: Create story (5% of traffic)
  else {
    createStory(data);
  }

  sleep(Math.random() * 3 + 1);  // 1-4 seconds between requests
}

// Stress Test - Heavy load simulation
export function stressTest(data) {
  loadTest(data);
  sleep(Math.random() * 2 + 0.5);  // Shorter sleep for more requests
}

// Spike Test - Sudden traffic spike
export function spikeTest(data) {
  loadTest(data);
  sleep(Math.random() * 1);  // Very short sleep
}

// Helper functions for different API calls
function browseStores(data) {
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: { endpoint: 'browse_stores' },
  };

  // Get store list
  const page = Math.floor(Math.random() * 10);
  const size = 20;
  const response = http.get(
    `${BASE_URL}/api/stores?page=${page}&size=${size}`,
    params
  );

  const success = check(response, {
    'browse stores - status is 200': (r) => r.status === 200,
    'browse stores - has data': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.stores !== undefined;
      } catch (e) {
        return false;
      }
    },
  });

  errorRate.add(!success);
  responseTime.add(response.timings.duration);
  requestCounter.add(1);

  // Get store detail if list request succeeded
  if (response.status === 200) {
    try {
      const body = JSON.parse(response.body);
      if (body.stores && body.stores.length > 0) {
        const randomStore = body.stores[Math.floor(Math.random() * body.stores.length)];
        getStoreDetail(randomStore.id);
      }
    } catch (e) {
      console.error('Failed to parse store list response');
    }
  }
}

function getStoreDetail(storeId) {
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: { endpoint: 'store_detail' },
  };

  const response = http.get(`${BASE_URL}/api/stores/${storeId}`, params);

  const success = check(response, {
    'store detail - status is 200': (r) => r.status === 200,
  });

  errorRate.add(!success);
  responseTime.add(response.timings.duration);
  requestCounter.add(1);
}

function createCheer(data) {
  // For load testing, you'd need valid JWT tokens
  // This is a placeholder - implement proper authentication flow
  const token = 'your-test-jwt-token';

  const payload = {
    storeKakaoId: `load_test_store_${Math.floor(Math.random() * 1000) + 1}`,
    description: 'Load test cheer - great place!',
    cheerTagNames: ['GOOD_FOR_DRINKING', 'NEAR_SUBWAY'],
  };

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    tags: { endpoint: 'create_cheer' },
  };

  const response = http.post(
    `${BASE_URL}/api/cheers`,
    JSON.stringify(payload),
    params
  );

  const success = check(response, {
    'create cheer - status is 201 or 401': (r) => r.status === 201 || r.status === 401,
  });

  errorRate.add(!success && response.status !== 401);
  responseTime.add(response.timings.duration);
  requestCounter.add(1);
}

function createStory(data) {
  // Placeholder for story creation
  const token = 'your-test-jwt-token';

  const payload = {
    storeKakaoId: `load_test_store_${Math.floor(Math.random() * 1000) + 1}`,
    description: 'Load test story',
  };

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    tags: { endpoint: 'create_story' },
  };

  const response = http.post(
    `${BASE_URL}/api/stories`,
    JSON.stringify(payload),
    params
  );

  const success = check(response, {
    'create story - status is 201 or 401': (r) => r.status === 201 || r.status === 401,
  });

  errorRate.add(!success && response.status !== 401);
  responseTime.add(response.timings.duration);
  requestCounter.add(1);
}

// Teardown - runs once after all tests
export function teardown(data) {
  console.log('Test completed');
}

// Default function - for simple execution
export default function() {
  loadTest();
}
