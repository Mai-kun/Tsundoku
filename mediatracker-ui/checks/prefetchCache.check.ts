// Self-check for the in-memory guard (Приём 3).
// Run: `npm run check:prefetch` (node --experimental-strip-types). No test framework, no fixtures.
import assert from 'node:assert/strict'
import { createPrefetchCache } from '../src/lib/utils/prefetchCache.ts'

// 1. Повторный load по тому же id не создаёт второй запрос.
{
  const cache = createPrefetchCache<number>(1000)
  let calls = 0
  const fetch = () => {
    calls += 1
    return new Promise<number>((resolve) => setTimeout(() => resolve(42), 10))
  }

  const [a, b] = await Promise.all([cache.load('x', fetch), cache.load('x', fetch)])
  assert.equal(calls, 1, 'in-flight dedup: one fetch for concurrent loads')
  assert.equal(a, 42)
  assert.equal(b, 42)

  await cache.load('x', fetch)
  assert.equal(calls, 1, 'cached value short-circuits before the network')
  assert.equal(cache.peek('x'), 42)
}

// 2. Истечение TTL возвращает кэш к fetcher'у.
{
  const cache = createPrefetchCache<number>(-1)
  let calls = 0
  const fetch = async () => ++calls
  assert.equal(await cache.load('y', fetch), 1)
  assert.equal(await cache.load('y', fetch), 2, 'expired entry refetches')
}

// 3. Ошибка не кэшируется и не блокирует следующую попытку.
{
  const cache = createPrefetchCache<number>(1000)
  let calls = 0
  const failing = async () => {
    calls += 1
    throw new Error('boom')
  }

  await assert.rejects(cache.load('z', failing))
  await assert.rejects(cache.load('z', failing))
  assert.equal(calls, 2, 'failed fetch is retried, not cached')
  assert.equal(cache.has('z'), false)
}

// 4. invalidate() принудительно освежает запись.
{
  const cache = createPrefetchCache<string>(1000)
  let calls = 0
  const fetch = async () => `v${++calls}`
  assert.equal(await cache.load('w', fetch), 'v1')
  cache.invalidate('w')
  assert.equal(cache.has('w'), false)
  assert.equal(await cache.load('w', fetch), 'v2')
}

console.log('prefetchCache: all checks passed')
